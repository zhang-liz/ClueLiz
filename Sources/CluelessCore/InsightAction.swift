import Foundation

/// The five one-tap actions on the insights card.
public enum InsightAction: String, CaseIterable, Identifiable {
    case sayNext, followUps, factCheck, whoIsThis, recap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sayNext: return "What should I say next"
        case .followUps: return "Follow-up questions"
        case .factCheck: return "Fact check"
        case .whoIsThis: return "Who am I talking to"
        case .recap: return "Recap"
        }
    }
}
