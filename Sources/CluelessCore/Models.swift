import Foundation

/// Who said a transcript turn. `.them(0)` is the first remote voice.
public enum Speaker: Equatable, Codable, Hashable {
    case me
    case them(Int)

    public var label: String {
        switch self {
        case .me: return "Me"
        case .them(let index): return index == 0 ? "Them" : "Them \(index + 1)"
        }
    }
}

/// One utterance in the transcript. Partial turns mutate in place until finalized.
public struct TranscriptTurn: Identifiable, Equatable, Codable {
    public let id: UUID
    public let speaker: Speaker
    public var text: String
    public let timestamp: Date
    public var isFinal: Bool

    public init(id: UUID = UUID(), speaker: Speaker, text: String, timestamp: Date = Date(), isFinal: Bool) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}
