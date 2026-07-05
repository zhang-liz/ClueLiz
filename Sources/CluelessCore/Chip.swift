import Foundation

/// A tappable suggestion surfaced below the insights card.
public struct Chip: Identifiable, Equatable, Codable {
    public enum Kind: String, Codable {
        case question, keyword, topic
    }

    public let id: UUID
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.id = UUID()
        self.kind = kind
        self.text = text
    }
}
