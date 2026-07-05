import Foundation

/// Anthropic Messages API streaming provider (SSE).
public struct AnthropicProvider: LLMProvider {
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "claude-opus-4-8", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func makeURLRequest(_ r: LLMRequest) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var contentBlocks: [[String: Any]] = []
        for part in r.parts {
            switch part {
            case .text(let text):
                contentBlocks.append(["type": "text", "text": text])
            case .imagePNG(let data):
                contentBlocks.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": r.maxTokens,
            "stream": true,
            "messages": [["role": "user", "content": contentBlocks]]
        ]
        if !r.system.isEmpty {
            body["system"] = r.system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func delta(fromChunk data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "content_block_delta",
              let delta = obj["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else { return nil }
        return text
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.http(status: -1, body: "no response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        for payload in parser.feed(Data((line + "\n").utf8)) {
                            if let delta = Self.delta(fromChunk: Data(payload.utf8)) {
                                continuation.yield(delta)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
