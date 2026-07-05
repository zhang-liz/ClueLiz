import Foundation

/// A provider-agnostic LLM request: system prompt plus user parts (text and/or images).
public struct LLMRequest {
    public enum Part {
        case text(String)
        case imagePNG(Data)
    }

    public var system: String
    public var parts: [Part]
    public var maxTokens: Int

    public init(system: String, parts: [Part], maxTokens: Int = 2048) {
        self.system = system
        self.parts = parts
        self.maxTokens = maxTokens
    }
}

public enum LLMError: Error, LocalizedError {
    case http(status: Int, body: String)
    case missingKey

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "LLM request failed (HTTP \(status)): \(body.prefix(200))"
        case .missingKey:
            return "API key missing — add it in Settings."
        }
    }
}

/// Streams text deltas for a request. Implementations: GeminiProvider, AnthropicProvider.
public protocol LLMProvider {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
