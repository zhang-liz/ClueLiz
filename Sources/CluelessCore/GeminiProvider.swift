import Foundation

/// Google Gemini streaming provider (SSE over `streamGenerateContent`).
public struct GeminiProvider: LLMProvider {
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "gemini-2.5-flash-lite", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func makeURLRequest(_ r: LLMRequest) throws -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var userParts: [[String: Any]] = []
        for part in r.parts {
            switch part {
            case .text(let text):
                userParts.append(["text": text])
            case .imagePNG(let data):
                userParts.append(["inlineData": ["mimeType": "image/png", "data": data.base64EncodedString()]])
            }
        }

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": userParts]],
            "generationConfig": ["maxOutputTokens": r.maxTokens]
        ]
        if !r.system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": r.system]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func delta(fromChunk data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
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
