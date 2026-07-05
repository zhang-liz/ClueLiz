import Foundation

/// One meeting session: transcript, timing, and (after the meeting) summary.
/// Persisted as JSON; `endedAt == nil` on disk means a crashed/live session.
public struct SessionRecord: Codable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var turns: [TranscriptTurn]
    public var summaryMarkdown: String?

    public init(startedAt: Date) {
        self.id = UUID()
        self.startedAt = startedAt
        self.turns = []
    }

    public func markdownExport() -> String {
        var out = "# Meeting \(startedAt.formatted(date: .abbreviated, time: .shortened))\n\n"
        if let summaryMarkdown {
            out += summaryMarkdown + "\n\n"
        }
        out += "---\n\n## Transcript\n\n"
        out += turns.filter(\.isFinal)
            .map { "\($0.speaker.label): \($0.text)" }
            .joined(separator: "\n\n")
        return out
    }
}
