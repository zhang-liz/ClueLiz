import Foundation
import CluelessCore

/// Orchestrates all LLM work: insight actions, freeform chat, screen answers,
/// and the suggestion-chip loop. One in-flight insight request at a time —
/// starting a new one cancels the previous.
@MainActor
final class InsightEngine {
    private let store: TranscriptStore
    private let contextProvider: () -> PromptContext
    private let liveLLM: () -> LLMProvider?
    private let summaryLLM: () -> LLMProvider?

    private var currentTask: Task<Void, Never>?
    private var chipLoopTask: Task<Void, Never>?

    private let liveTimeout: TimeInterval = 15

    init(store: TranscriptStore,
         contextProvider: @escaping () -> PromptContext,
         liveLLM: @escaping () -> LLMProvider?,
         summaryLLM: @escaping () -> LLMProvider?) {
        self.store = store
        self.contextProvider = contextProvider
        self.liveLLM = liveLLM
        self.summaryLLM = summaryLLM
    }

    // MARK: - Insight actions

    func run(action: InsightAction,
             onDelta: @escaping (String) -> Void,
             onDone: @escaping (Error?) -> Void) {
        let provider = action == .recap ? summaryLLM() : liveLLM()
        let request = PromptBuilder.request(for: action, context: contextProvider())
        runStreaming(request, provider: provider,
                     timeout: action == .recap ? 60 : liveTimeout,
                     onDelta: onDelta, onDone: onDone)
    }

    func runFreeform(question: String, smartMode: Bool,
                     onDelta: @escaping (String) -> Void,
                     onDone: @escaping (Error?) -> Void) {
        let request = PromptBuilder.chatRequest(question: question, smartMode: smartMode,
                                                context: contextProvider())
        runStreaming(request, provider: liveLLM(), timeout: liveTimeout,
                     onDelta: onDelta, onDone: onDone)
    }

    func runScreenAnswer(png: Data,
                         onDelta: @escaping (String) -> Void,
                         onDone: @escaping (Error?) -> Void) {
        let request = PromptBuilder.screenAnswerRequest(pngData: png, context: contextProvider())
        runStreaming(request, provider: liveLLM(), timeout: liveTimeout,
                     onDelta: onDelta, onDone: onDone)
    }

    private func runStreaming(_ request: LLMRequest, provider: LLMProvider?,
                              timeout: TimeInterval,
                              onDelta: @escaping (String) -> Void,
                              onDone: @escaping (Error?) -> Void) {
        currentTask?.cancel()
        guard let provider else {
            onDone(LLMError.missingKey)
            return
        }
        currentTask = Task { [weak self] in
            guard self != nil else { return }
            do {
                let activity = StreamActivity()
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await delta in provider.stream(request) {
                            if Task.isCancelled { return }
                            activity.touch()
                            await MainActor.run { onDelta(delta) }
                        }
                    }
                    // Idle watchdog: a healthy stream keeps producing deltas, and a
                    // long answer may legitimately take longer than `timeout` overall.
                    // Only give up when NOTHING has arrived for `timeout` seconds.
                    group.addTask {
                        while activity.idleSeconds < timeout {
                            try await Task.sleep(nanoseconds: 500_000_000)
                        }
                        throw LLMError.timeout(seconds: Int(timeout))
                    }
                    try await group.next()
                    group.cancelAll()
                }
                if !Task.isCancelled { onDone(nil) }
            } catch {
                if !Task.isCancelled { onDone(error) }
            }
        }
    }

    // MARK: - Auto-definitions

    /// Terms already defined (or queued) this session — never re-define.
    private var definedTerms = Set<String>()
    private var definitionQueue: [String] = []
    private var definitionWorker: Task<Void, Never>?
    private var onDefinition: ((_ term: String, _ definition: String, _ done: Bool) -> Void)?

    /// Streams a short definition for every newly mentioned acronym/keyword.
    /// Runs on its own task — never cancels or blocks user-triggered insights.
    func startAutoDefine(onDefinition: @escaping (_ term: String, _ definition: String, _ done: Bool) -> Void) {
        self.onDefinition = onDefinition
    }

    private func enqueueDefinitions(for terms: [String]) {
        guard onDefinition != nil else { return }
        for term in terms {
            let key = term.lowercased()
            guard !definedTerms.contains(key) else { continue }
            definedTerms.insert(key)
            definitionQueue.append(term)
        }
        drainDefinitionQueue()
    }

    private func drainDefinitionQueue() {
        guard definitionWorker == nil, !definitionQueue.isEmpty else { return }
        definitionWorker = Task { [weak self] in
            while let self, !Task.isCancelled, !self.definitionQueue.isEmpty {
                let term = self.definitionQueue.removeFirst()
                guard let provider = self.liveLLM() else {
                    // No key yet — drop the queue and un-mark the terms so they can
                    // be defined on a later mention once a key is added.
                    self.definedTerms.remove(term.lowercased())
                    for queued in self.definitionQueue {
                        self.definedTerms.remove(queued.lowercased())
                    }
                    self.definitionQueue.removeAll()
                    break
                }
                var context = self.contextProvider()
                context.transcript = self.store.contextText(maxWords: 200)   // short slice — fast request
                let request = PromptBuilder.definitionRequest(term: term, context: context)
                var definition = ""
                do {
                    for try await delta in provider.stream(request) {
                        definition += delta
                        self.onDefinition?(term, definition, false)
                    }
                    self.onDefinition?(term, definition, true)
                } catch {
                    // Best-effort — allow a retry on a later mention.
                    self.definedTerms.remove(term.lowercased())
                }
            }
            self?.definitionWorker = nil
            // New terms may have arrived while finishing the last one.
            self?.drainDefinitionQueue()
        }
    }

    // MARK: - Chip loop

    func startChipLoop(onChips: @escaping ([Chip]) -> Void) {
        stopChipLoop()
        definedTerms.removeAll()   // "this session" — a new session starts fresh
        chipLoopTask = Task { [weak self] in
            guard let self else { return }
            var knownChips: [Chip] = []
            var publishedChips: [Chip] = []
            var processedFinalCount = 0
            var finalsSinceExtraction = 0
            var lastExtraction = Date.distantPast

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)   // poll every 2 s
                if Task.isCancelled { break }

                // 1. Instant local question detection on new finals.
                let finals = self.store.turns.filter(\.isFinal)
                if finals.count > processedFinalCount {
                    let newFinals = finals[processedFinalCount...]
                    finalsSinceExtraction += finals.count - processedFinalCount
                    processedFinalCount = finals.count
                    let newText = newFinals.map(\.text).joined(separator: " ")
                    let localChips = ChipDetector.detectQuestions(in: newText)
                    knownChips = Self.merge(localChips, into: knownChips)
                    // Auto-define newly mentioned acronyms (e.g. "MCP") immediately.
                    await MainActor.run {
                        self.enqueueDefinitions(for: ChipDetector.detectAcronyms(in: newText))
                    }
                }

                // 2. Periodic LLM extraction: every 15 s or every 5 new finals.
                let shouldExtract = (finalsSinceExtraction >= 5)
                    || (Date().timeIntervalSince(lastExtraction) >= 15 && finalsSinceExtraction > 0)
                if shouldExtract, let provider = self.liveLLM() {
                    lastExtraction = Date()
                    finalsSinceExtraction = 0
                    let recent = self.store.contextText(maxWords: 400)
                    let request = PromptBuilder.chipExtractionRequest(recentTranscript: recent)
                    var accumulated = ""
                    do {
                        for try await delta in provider.stream(request) {
                            accumulated += delta
                        }
                        let llmChips = PromptBuilder.parseChips(fromJSON: accumulated)
                        knownChips = Self.merge(llmChips, into: knownChips)
                        // Auto-define LLM-extracted keywords too (multi-word terms).
                        let keywordTerms = llmChips.filter { $0.kind == .keyword }.map(\.text)
                        await MainActor.run { self.enqueueDefinitions(for: keywordTerms) }
                    } catch {
                        // Chip extraction is best-effort — swallow errors, retry next cycle.
                    }
                }

                if knownChips != publishedChips {
                    publishedChips = knownChips
                    let chips = knownChips
                    await MainActor.run { onChips(chips) }
                }
            }
        }
    }

    func stopChipLoop() {
        chipLoopTask?.cancel()
        chipLoopTask = nil
        definitionWorker?.cancel()
        definitionWorker = nil
        definitionQueue.removeAll()
    }

    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Dedup by lowercase text, keep newest, cap at 8.
    private static func merge(_ new: [Chip], into existing: [Chip]) -> [Chip] {
        var result = existing
        for chip in new {
            if !result.contains(where: { $0.text.lowercased() == chip.text.lowercased() }) {
                result.append(chip)
            }
        }
        if result.count > 8 { result.removeFirst(result.count - 8) }
        return result
    }
}

/// Last-delta timestamp shared between a stream loop and its idle watchdog.
private final class StreamActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()

    func touch() {
        lock.lock()
        last = Date()
        lock.unlock()
    }

    var idleSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(last)
    }
}
