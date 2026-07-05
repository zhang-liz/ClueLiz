import Testing
import Foundation
@testable import CluelessCore

@Suite struct LLMProviderTests {
    @Test func geminiRequestEncoding() throws {
        let p = GeminiProvider(apiKey: "KEY")
        let req = try p.makeURLRequest(LLMRequest(system: "sys", parts: [.text("hi")], maxTokens: 100))
        #expect(req.url!.absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:streamGenerateContent?alt=sse")
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "KEY")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let sys = body["systemInstruction"] as! [String: Any]
        #expect(sys["parts"] != nil)
        let cfg = body["generationConfig"] as! [String: Any]
        #expect(cfg["maxOutputTokens"] as! Int == 100)
    }

    @Test func geminiDeltaDecoding() {
        let chunk = #"{"candidates":[{"content":{"parts":[{"text":"Hel"},{"text":"lo"}],"role":"model"}}]}"#
        #expect(GeminiProvider.delta(fromChunk: Data(chunk.utf8)) == "Hello")
    }

    @Test func anthropicRequestEncoding() throws {
        let p = AnthropicProvider(apiKey: "AK")
        let req = try p.makeURLRequest(LLMRequest(system: "s", parts: [.text("q")], maxTokens: 16000))
        #expect(req.url!.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "AK")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(body["model"] as! String == "claude-opus-4-8")
        #expect(body["stream"] as! Bool == true)
    }

    @Test func anthropicDeltaDecoding() {
        let delta = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#
        #expect(AnthropicProvider.delta(fromChunk: Data(delta.utf8)) == "Hi")
        let other = #"{"type":"message_start"}"#
        #expect(AnthropicProvider.delta(fromChunk: Data(other.utf8)) == nil)
    }

    @Test func imagePartEncodingGemini() throws {
        let p = GeminiProvider(apiKey: "K")
        let png = Data([0x89, 0x50])
        let req = try p.makeURLRequest(LLMRequest(system: "", parts: [.text("what is this"), .imagePNG(png)]))
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let contents = body["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        #expect(parts.count == 2)
        let inline = parts[1]["inlineData"] as! [String: Any]
        #expect(inline["data"] as! String == png.base64EncodedString())
    }
}
