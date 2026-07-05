import Foundation
import EventKit
import ClueLizCore

/// Session lifecycle: persistence + crash recovery, calendar-based meeting
/// detection, silence timeout, and post-meeting summary generation.
final class SessionManager {
    // Callbacks (delivered on the main queue)
    var onMeetingDetected: ((_ title: String, _ attendees: [String]) -> Void)?
    var onMeetingLikelyEnded: (() -> Void)?
    var onSilenceTimeout: (() -> Void)?

    private(set) var current: SessionRecord?
    private(set) var recoverableSession: SessionRecord?

    private let eventStore = EKEventStore()
    private var calendarAccess = false
    private var flushTimer: Timer?
    private var calendarTimer: Timer?
    private var silenceTimer: Timer?
    private var detectedEventID: String?
    private var promptedEventIDs = Set<String>()

    /// Set by the owner each time speech arrives (TranscriptionService.lastAudioActivity).
    var lastAudioActivity: () -> Date = { Date() }
    private let silenceLimit: TimeInterval = 10 * 60

    static let sessionsDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClueLiz/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        findRecoverableSession()
    }

    // MARK: - Lifecycle

    func start() {
        let record = SessionRecord(startedAt: Date())
        current = record
        recoverableSession = nil
        save(record)
        startTimers()
    }

    /// Marks a crash-recovered session as ended without resuming it.
    func discardRecoverableSession() {
        guard var record = recoverableSession else { return }
        record.endedAt = Date()
        save(record)
        recoverableSession = nil
    }

    func resume(_ session: SessionRecord) {
        current = session
        recoverableSession = nil
        startTimers()
    }

    /// True once the current silence episode has been reported; re-arms when audio resumes.
    private var silencePrompted = false

    private func startTimers() {
        flushTimer?.invalidate()
        silenceTimer?.invalidate()
        silencePrompted = false

        flushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.flush()
        }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.current != nil else { return }
            if Date().timeIntervalSince(self.lastAudioActivity()) > self.silenceLimit {
                // Prompt once per silence episode; if the owner keeps the session
                // going and audio resumes, a later silence prompts again.
                if !self.silencePrompted {
                    self.silencePrompted = true
                    self.onSilenceTimeout?()
                }
            } else {
                self.silencePrompted = false
            }
        }
    }

    /// Called every flush with the latest turns.
    var turnsProvider: () -> [TranscriptTurn] = { [] }

    private func flush() {
        guard var record = current else { return }
        record.turns = turnsProvider()
        current = record
        save(record)
    }

    func end() -> SessionRecord? {
        flushTimer?.invalidate()
        silenceTimer?.invalidate()
        detectedEventID = nil   // don't let a stale calendar event end the next session
        guard var record = current else { return nil }
        record.turns = turnsProvider()
        record.endedAt = Date()
        current = nil
        save(record)
        return record
    }

    func attachSummary(_ markdown: String, to record: SessionRecord) {
        var updated = record
        updated.summaryMarkdown = markdown
        save(updated)
    }

    // MARK: - Summary

    func generateSummary(llm: LLMProvider, transcript: String) async throws -> String {
        let request = PromptBuilder.summaryRequest(fullTranscript: transcript)
        var summary = ""
        for try await delta in llm.stream(request) {
            summary += delta
        }
        return summary
    }

    /// Streaming variant so the SummaryView can render as tokens arrive.
    func streamSummary(llm: LLMProvider, transcript: String,
                       onDelta: @escaping (String) -> Void) async throws -> String {
        let request = PromptBuilder.summaryRequest(fullTranscript: transcript)
        var summary = ""
        for try await delta in llm.stream(request) {
            summary += delta
            let snapshot = summary
            await MainActor.run { onDelta(snapshot) }
        }
        return summary
    }

    // MARK: - Persistence

    private func save(_ record: SessionRecord) {
        let url = Self.sessionsDirectory.appendingPathComponent("\(record.id.uuidString).json")
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func findRecoverableSession() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let newest = files
            .filter { $0.pathExtension == "json" }
            .sorted { (lhs, rhs) in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .first
        guard let newest,
              let data = try? Data(contentsOf: newest),
              let record = try? JSONDecoder().decode(SessionRecord.self, from: data),
              record.endedAt == nil, !record.turns.isEmpty else { return }
        recoverableSession = record
    }

    // MARK: - Calendar detection

    private var calendarWatchStarted = false

    func startCalendarWatch() {
        guard !calendarWatchStarted else { return }
        calendarWatchStarted = true
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            guard let self, granted else { return }
            self.calendarAccess = true
            DispatchQueue.main.async {
                self.calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    self?.checkCalendar()
                }
                self.checkCalendar()
            }
        }
    }

    private func checkCalendar() {
        guard calendarAccess else { return }
        let now = Date()
        let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-15 * 60),
                                                      end: now.addingTimeInterval(5 * 60),
                                                      calendars: nil)
        let events = eventStore.events(matching: predicate)

        // A "meeting" = event with a video-call link in URL, notes, or location.
        func isVideoMeeting(_ event: EKEvent) -> Bool {
            let haystack = [event.url?.absoluteString, event.notes, event.location]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            return ["zoom.us", "meet.google", "teams.microsoft", "webex", "whereby"].contains {
                haystack.contains($0)
            }
        }

        if current == nil {
            // Detect a meeting that started within the last 5 minutes.
            if let event = events.first(where: {
                isVideoMeeting($0) && $0.startDate <= now
                    && now.timeIntervalSince($0.startDate) < 5 * 60
                    && !promptedEventIDs.contains($0.eventIdentifier ?? "")
            }) {
                promptedEventIDs.insert(event.eventIdentifier ?? "")
                detectedEventID = event.eventIdentifier
                let attendees = (event.attendees ?? []).compactMap(\.name)
                DispatchQueue.main.async {
                    self.onMeetingDetected?(event.title ?? "Meeting", attendees)
                }
            }
        } else if let eventID = detectedEventID,
                  let event = events.first(where: { $0.eventIdentifier == eventID }),
                  let endDate = event.endDate,
                  now.timeIntervalSince(endDate) > 2 * 60 {
            // Detected meeting's calendar slot ended >2 min ago.
            detectedEventID = nil
            DispatchQueue.main.async { self.onMeetingLikelyEnded?() }
        }
    }
}
