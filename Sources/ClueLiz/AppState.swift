import Foundation
import SwiftUI
import ClueLizCore

/// Single source of truth for the UI. Owns the transcript store and services.
@MainActor
final class AppState: ObservableObject {
    @Published var turns: [TranscriptTurn] = []
    @Published var chips: [Chip] = []
    @Published var insightText = ""
    @Published var insightStreaming = false
    @Published var activeAction: InsightAction?
    @Published var chatInput = ""
    @Published var smartMode = false
    @Published var sessionActive = false
    @Published var reconnecting = false
    @Published var errorBanner: String?
    @Published var definitions: [TermDefinition] = []

    struct TermDefinition: Identifiable, Equatable {
        let id: String          // lowercase term — stable across streaming updates
        let term: String
        var text: String
        var done: Bool
    }

    let store = TranscriptStore()
    let contextStore = FileContextStore()
    let sessionManager = SessionManager()
    var participants: [String] = []

    /// Set by AppDelegate — presents the summary window for an ended session.
    var presentSummary: ((SessionRecord) -> Void)?

    private var transcription: TranscriptionService?
    private(set) lazy var insightEngine: InsightEngine = {
        InsightEngine(
            store: store,
            contextProvider: { [weak self] in
                guard let self else { return PromptContext(transcript: "") }
                return PromptContext(
                    transcript: self.store.contextText(maxWords: 2000),
                    uploadedContext: self.contextStore.combinedTextSnapshot,
                    participants: self.participants,
                    domain: UserDefaults.standard.string(forKey: "meetingDomain")
                        ?? "AI and software engineering"
                )
            },
            liveLLM: {
                guard let key = KeychainStore.get(.gemini), !key.isEmpty else { return nil }
                return GeminiProvider(apiKey: key)
            },
            summaryLLM: {
                guard let key = KeychainStore.get(.anthropic), !key.isEmpty else { return nil }
                return AnthropicProvider(apiKey: key)
            }
        )
    }()

    init() {
        store.onChange = { [weak self] in
            guard let self else { return }
            // Snapshot on the main queue: onChange fires on both Deepgram callback
            // queues, and snapshots taken there can enqueue out of order,
            // transiently publishing older turns over newer ones.
            DispatchQueue.main.async { self.turns = self.store.turns }
        }
        sessionManager.turnsProvider = { [weak self] in self?.store.turns ?? [] }
        // Keychain edits (Settings, onboarding) and window focus re-check key
        // availability so action buttons enable without an app restart.
        NotificationCenter.default.addObserver(
            forName: .apiKeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKeyAvailability() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKeyAvailability() }
        }
        // Don't trigger the calendar permission dialog before onboarding has
        // explained it — AppDelegate starts the watch when onboarding finishes.
        if UserDefaults.standard.bool(forKey: "onboardingDone") {
            sessionManager.startCalendarWatch()
        }
    }

    /// Crash recovery: seed the transcript with a recovered session's turns and continue it.
    func resumeRecoveredSession() {
        guard let recovered = sessionManager.recoverableSession else { return }
        for turn in recovered.turns where turn.isFinal {
            store.applyFinal(speaker: turn.speaker, text: turn.text)
        }
        sessionManager.resume(recovered)
        startCapture()
    }

    // Published so buttons disabled on a missing key re-enable the moment a key
    // is added in Settings — computed properties would only re-evaluate when an
    // unrelated @Published property fired.
    @Published private(set) var hasDeepgramKey = KeychainStore.get(.deepgram)?.isEmpty == false
    @Published private(set) var hasGeminiKey = KeychainStore.get(.gemini)?.isEmpty == false
    @Published private(set) var hasAnthropicKey = KeychainStore.get(.anthropic)?.isEmpty == false

    /// Re-reads key availability from the Keychain (only assigns on change to
    /// avoid needless view invalidation).
    func refreshKeyAvailability() {
        let deepgram = KeychainStore.get(.deepgram)?.isEmpty == false
        let gemini = KeychainStore.get(.gemini)?.isEmpty == false
        let anthropic = KeychainStore.get(.anthropic)?.isEmpty == false
        if hasDeepgramKey != deepgram { hasDeepgramKey = deepgram }
        if hasGeminiKey != gemini { hasGeminiKey = gemini }
        if hasAnthropicKey != anthropic { hasAnthropicKey = anthropic }
    }

    // MARK: - Session

    func startSession() {
        guard !sessionActive else { return }
        // Verify the key BEFORE creating the session record — otherwise every
        // failed start writes a junk empty session JSON to disk.
        refreshKeyAvailability()
        guard hasDeepgramKey else {
            showNonRetryableError("Add your Deepgram key in Settings first.")
            return
        }
        // A new meeting starts clean — otherwise the previous session's transcript
        // leaks into this session's record and every LLM prompt.
        store.clear()
        chips = []
        definitions = []
        evictedDefinitionIDs = []
        insightText = ""
        activeAction = nil
        sessionManager.start()
        startCapture()
    }

    /// Definitions evicted from the (max 5) list — later stream deltas for them
    /// are dropped so they can't re-insert and evict newer entries in a cycle.
    private var evictedDefinitionIDs: Set<String> = []

    /// Shared by fresh start and crash-resume: capture + chip loop, no new record.
    private func startCapture() {
        guard let key = KeychainStore.get(.deepgram), !key.isEmpty else {
            showNonRetryableError("Add your Deepgram key in Settings first.")
            _ = sessionManager.end()
            return
        }
        let service = TranscriptionService(store: store)
        service.onReconnecting = { [weak self] down in
            DispatchQueue.main.async { self?.reconnecting = down }
        }
        service.onStreamError = { [weak self] message in
            DispatchQueue.main.async { self?.showNonRetryableError(message) }
        }
        sessionManager.lastAudioActivity = { [weak service] in
            service?.lastAudioActivity ?? Date()
        }
        transcription = service
        sessionActive = true
        errorBanner = nil
        Task {
            do {
                try await service.start(deepgramKey: key)
            } catch {
                self.showNonRetryableError("Could not start capture: \(error.localizedDescription)")
                _ = self.closeSession()   // stop flushing a session that never captured
            }
        }
        insightEngine.startChipLoop { [weak self] chips in
            self?.chips = chips
        }
        insightEngine.startAutoDefine { [weak self] term, definition, done in
            guard let self else { return }
            let id = term.lowercased()
            guard !self.evictedDefinitionIDs.contains(id) else { return }
            if let index = self.definitions.firstIndex(where: { $0.id == id }) {
                self.definitions[index].text = definition
                self.definitions[index].done = done
            } else {
                self.definitions.insert(
                    TermDefinition(id: id, term: term, text: definition, done: done), at: 0)
            }
            if self.definitions.count > 5 {
                self.evictedDefinitionIDs.insert(self.definitions.removeLast().id)
            }
        }
    }

    func endSession() {
        if let record = closeSession(), !record.turns.filter(\.isFinal).isEmpty {
            presentSummary?(record)
        }
    }

    /// App-termination path (⌘Q mid-session): flush the transcript and mark the
    /// session ended so the next launch doesn't claim an unclean shutdown — but
    /// skip the summary window, since the app is quitting.
    func endSessionForTermination() {
        _ = closeSession()
    }

    /// Tears down capture and closes the session record; returns it for summary.
    private func closeSession() -> SessionRecord? {
        transcription?.stop()
        transcription = nil
        insightEngine.stopChipLoop()
        cancelStreaming()   // cancellation suppresses onDone — clear the spinner here
        sessionActive = false
        reconnecting = false
        participants = []   // belong to the meeting that just ended
        return sessionManager.end()
    }

    // MARK: - Insights

    /// Re-runs whatever produced the current answer — set by every run* entry point
    /// so the error banner's Retry works for actions, chips, chat, and screen answers.
    private var lastRun: (() -> Void)?
    var canRetry: Bool { lastRun != nil }

    func retryLast() {
        lastRun?()
    }

    /// Banner for non-LLM failures (capture, keys, hotkeys). Clears `lastRun` so
    /// the banner's Retry can't re-run an unrelated LLM action.
    func showNonRetryableError(_ message: String) {
        errorBanner = message
        lastRun = nil
    }

    /// User-visible stop: abandons the in-flight stream, keeps the partial answer.
    func cancelStreaming() {
        insightEngine.cancelCurrent()
        insightStreaming = false
    }

    func run(action: InsightAction) {
        activeAction = action
        lastRun = { [weak self] in self?.run(action: action) }
        beginStreaming()
        insightEngine.run(action: action,
                          onDelta: { [weak self] delta in self?.insightText += delta },
                          onDone: { [weak self] error in self?.finishStreaming(error) })
    }

    func runChip(_ chip: Chip) {
        activeAction = nil
        lastRun = { [weak self] in self?.runChip(chip) }
        beginStreaming()
        let question: String
        switch chip.kind {
        case .question: question = "Help me answer this question that came up: \(chip.text)"
        case .keyword: question = "Briefly explain \"\(chip.text)\" in the context of this conversation."
        case .topic: question = "Summarize what has been said about \"\(chip.text)\" and suggest a useful next point."
        }
        insightEngine.runFreeform(question: question, smartMode: false,
                                  onDelta: { [weak self] delta in self?.insightText += delta },
                                  onDone: { [weak self] error in self?.finishStreaming(error) })
    }

    func sendChat() {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        chatInput = ""
        sendChat(question: question)
    }

    /// Question passed explicitly so Retry can re-send it after the input was cleared.
    private func sendChat(question: String) {
        activeAction = nil
        lastRun = { [weak self] in self?.sendChat(question: question) }
        beginStreaming()
        insightEngine.runFreeform(question: question, smartMode: smartMode,
                                  onDelta: { [weak self] delta in self?.insightText += delta },
                                  onDone: { [weak self] error in self?.finishStreaming(error) })
    }

    func runScreenAnswer() {
        activeAction = nil
        lastRun = { [weak self] in self?.runScreenAnswer() }
        // Stop any in-flight stream now — the screenshot takes a moment, and stale
        // deltas would otherwise land in the freshly cleared answer area.
        insightEngine.cancelCurrent()
        beginStreaming()
        Task {
            do {
                let png = try await ScreenSnapshotService.captureMainDisplayPNG()
                insightEngine.runScreenAnswer(png: png,
                                              onDelta: { [weak self] delta in self?.insightText += delta },
                                              onDone: { [weak self] error in self?.finishStreaming(error) })
            } catch {
                finishStreaming(error)
            }
        }
    }

    private func beginStreaming() {
        insightText = ""
        insightStreaming = true
        errorBanner = nil
    }

    private func finishStreaming(_ error: Error?) {
        insightStreaming = false
        if let error {
            errorBanner = error.localizedDescription
        }
    }
}
