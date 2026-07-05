# Clueless Meeting Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Clueless native macOS meeting assistant per `docs/superpowers/specs/2026-07-05-meeting-assistant-design.md` — live transcription overlay with AI insights, packaged as a dmg.

**Architecture:** Pure-SPM Swift project. Library target `CluelessCore` holds all pure logic (models, transcript store, chip detection, prompt building, SSE/LLM/Deepgram parsing) and is fully unit-tested. Executable target `Clueless` holds UI (SwiftUI in a non-activating NSPanel) and system services (ScreenCaptureKit, AVAudioEngine, WebSocket, EventKit, Keychain, hotkeys). Build machine has Command Line Tools only — no Xcode, no xcodebuild; `.app` is assembled by script.

**Tech Stack:** Swift 6.1 (Swift 5 language mode), SwiftUI + AppKit, ScreenCaptureKit, AVAudioEngine, URLSessionWebSocketTask, PDFKit, EventKit, Carbon hotkeys, Deepgram streaming STT, Gemini 2.5 Flash-Lite (live LLM), Claude Opus 4.8 (summary LLM).

## Global Constraints

- macOS deployment target: **14.0** (`platforms: [.macOS(.v14)]`)
- Swift tools version 5.10, language mode **v5** (avoid strict-concurrency churn with AppKit/AV APIs)
- No third-party dependencies — Apple frameworks + raw HTTP only
- LLM calls: raw HTTP + SSE (Swift has no official Anthropic/Google SDK). Anthropic headers: `x-api-key`, `anthropic-version: 2023-06-01`. Model IDs exactly: `gemini-2.5-flash-lite`, `claude-opus-4-8`
- Deepgram: `wss://api.deepgram.com/v1/listen` with `encoding=linear16&sample_rate=16000&channels=1&interim_results=true&punctuate=true&diarize=true&model=nova-3`, auth header `Authorization: Token <key>`
- All streamed responses render token-by-token; in-flight insight request cancelled when a new action fires
- API keys live in macOS Keychain only — never in files or UserDefaults
- App bundle ID: `com.clueless.app`; ad-hoc codesign (`codesign -s -`) unless `SIGN_ID` env var set
- Run unit tests with `swift test`; UI/system tasks end with a build + manual verify step
- Commit after every green step; messages concise per repo CLAUDE.md

---

### Task 1: Project skeleton + build pipeline

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: `Sources/CluelessCore/Models.swift` (placeholder types only — real content Task 2)
- Create: `Sources/Clueless/CluelessApp.swift`, `Sources/Clueless/AppDelegate.swift`
- Create: `Resources/Info.plist`, `scripts/bundle.sh`, `Makefile`
- Test: none (pipeline verification)

**Interfaces:**
- Produces: buildable SPM layout; `make build` → binary; `make app` → runnable `dist/Clueless.app`; `make test` → `swift test`

- [ ] **Step 1: Write Package.swift + .gitignore**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Clueless",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CluelessCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Clueless",
            dependencies: ["CluelessCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CluelessCoreTests", dependencies: ["CluelessCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
```

`.gitignore`: `.build/`, `dist/`, `*.dmg`, `.DS_Store`.

- [ ] **Step 2: Minimal app entry**

`CluelessApp.swift`:
```swift
import SwiftUI

@main
struct CluelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }   // real windows are managed by AppDelegate
    }
}
```

`AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let alertWindow = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        alertWindow.title = "Clueless"
        alertWindow.center()
        alertWindow.makeKeyAndOrderFront(nil)   // placeholder — replaced by overlay in Task 10
    }
}
```

`Models.swift`: `public enum CluelessCoreMarker {}` (placeholder so target compiles).

- [ ] **Step 3: Info.plist + bundle script + Makefile**

`Resources/Info.plist` (full file):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.clueless.app</string>
    <key>CFBundleName</key><string>Clueless</string>
    <key>CFBundleExecutable</key><string>Clueless</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Clueless transcribes your side of the meeting from the microphone.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Clueless uses your calendar to detect when meetings start and end.</string>
</dict></plist>
```

`scripts/bundle.sh`:
```bash
#!/bin/bash
set -euo pipefail
CONFIG="${1:-release}"
swift build -c "$CONFIG"
APP=dist/Clueless.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Clueless" "$APP/Contents/MacOS/Clueless"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s "${SIGN_ID:--}" "$APP"
echo "Built $APP"
```

`Makefile`:
```make
.PHONY: build test app run dmg
build: ; swift build
test: ; swift test
app: ; bash scripts/bundle.sh release
run: app ; open dist/Clueless.app
dmg: app ; bash scripts/make-dmg.sh   # script added in Task 16
```

- [ ] **Step 4: Verify build + launch**

Run: `swift build && make app`
Expected: `Built dist/Clueless.app`. `open dist/Clueless.app` shows the placeholder window.

- [ ] **Step 5: Commit** — `feat: SPM skeleton, app bundle pipeline`

---

### Task 2: Core models + TranscriptStore

**Files:**
- Modify: `Sources/CluelessCore/Models.swift` (replace placeholder)
- Create: `Sources/CluelessCore/TranscriptStore.swift`
- Test: `Tests/CluelessCoreTests/TranscriptStoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum Speaker: Equatable, Codable, Hashable { case me; case them(Int) }` with `public var label: String` ("Me", "Them", "Them 2"… — `them(0)` → "Them", `them(n)` → "Them \(n+1)")
  - `public struct TranscriptTurn: Identifiable, Equatable, Codable { public let id: UUID; public let speaker: Speaker; public var text: String; public let timestamp: Date; public var isFinal: Bool }`
  - `public final class TranscriptStore { public init(); public private(set) var turns: [TranscriptTurn]; public var onChange: (() -> Void)?; public func applyPartial(speaker: Speaker, text: String); public func applyFinal(speaker: Speaker, text: String); public func recentTurns(_ n: Int) -> [TranscriptTurn]; public func contextText(maxWords: Int) -> String; public var fullText: String }`
  - Semantics: one mutable partial turn per speaker — consecutive `applyPartial` for the same speaker updates that turn in place; `applyFinal` commits it (`isFinal = true`, text replaced by final text); empty partial/final text is ignored. `contextText` returns newest-last `"Label: text"` lines, trimmed from the front to ≤ maxWords. Thread-safe via internal `NSLock`.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CluelessCore

final class TranscriptStoreTests: XCTestCase {
    func testPartialCreatesMutableTurnPerSpeaker() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "hel")
        s.applyPartial(speaker: .me, text: "hello wor")
        XCTAssertEqual(s.turns.count, 1)
        XCTAssertEqual(s.turns[0].text, "hello wor")
        XCTAssertFalse(s.turns[0].isFinal)
    }

    func testFinalCommitsTurn() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "hello wor")
        s.applyFinal(speaker: .me, text: "Hello world.")
        XCTAssertEqual(s.turns.count, 1)
        XCTAssertEqual(s.turns[0].text, "Hello world.")
        XCTAssertTrue(s.turns[0].isFinal)
        // next partial starts a NEW turn
        s.applyPartial(speaker: .me, text: "again")
        XCTAssertEqual(s.turns.count, 2)
    }

    func testInterleavedSpeakersKeepSeparatePartials() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "mine")
        s.applyPartial(speaker: .them(0), text: "theirs")
        s.applyPartial(speaker: .me, text: "mine more")
        XCTAssertEqual(s.turns.count, 2)
        XCTAssertEqual(s.turns.first(where: { $0.speaker == .me })?.text, "mine more")
    }

    func testEmptyTextIgnored() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "  ")
        s.applyFinal(speaker: .me, text: "")
        XCTAssertTrue(s.turns.isEmpty)
    }

    func testContextTextTrimsFromFront() {
        let s = TranscriptStore()
        s.applyFinal(speaker: .me, text: "one two three")
        s.applyFinal(speaker: .them(0), text: "four five six")
        let ctx = s.contextText(maxWords: 5)
        XCTAssertFalse(ctx.contains("one"))       // oldest trimmed
        XCTAssertTrue(ctx.contains("Them: four five six"))
    }

    func testSpeakerLabels() {
        XCTAssertEqual(Speaker.me.label, "Me")
        XCTAssertEqual(Speaker.them(0).label, "Them")
        XCTAssertEqual(Speaker.them(1).label, "Them 2")
    }
}
```

- [ ] **Step 2: Run** `swift test --filter TranscriptStoreTests` — expect FAIL (types undefined)
- [ ] **Step 3: Implement `Models.swift` + `TranscriptStore.swift` per the interface block above** (turn list + per-speaker index of open partial; `NSLock` around mutations; `onChange` fired after each mutation on the calling thread)
- [ ] **Step 4: Run** `swift test --filter TranscriptStoreTests` — expect PASS
- [ ] **Step 5: Commit** — `feat: transcript models and store`

---

### Task 3: ChipDetector (local question detection)

**Files:**
- Create: `Sources/CluelessCore/Chip.swift`, `Sources/CluelessCore/ChipDetector.swift`
- Test: `Tests/CluelessCoreTests/ChipDetectorTests.swift`

**Interfaces:**
- Produces:
  - `public struct Chip: Identifiable, Equatable, Codable { public enum Kind: String, Codable { case question, keyword, topic }; public let id: UUID; public let kind: Kind; public let text: String; public init(kind: Kind, text: String) }`
  - `public enum ChipDetector { public static func detectQuestions(in text: String) -> [Chip] }`
  - Semantics: splits on sentence terminators; a sentence is a question chip if it ends in `?` **or** starts with an interrogative (what/how/why/when/where/who/which/can/could/should/would/do/does/did/is/are/will, case-insensitive) and has ≥ 3 words. Dedup identical texts. Returned text trimmed, ends with `?` (appended if missing).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CluelessCore

final class ChipDetectorTests: XCTestCase {
    func testDetectsQuestionMark() {
        let chips = ChipDetector.detectQuestions(in: "That's fine. What is the budget for Q3?")
        XCTAssertEqual(chips.map(\.text), ["What is the budget for Q3?"])
        XCTAssertEqual(chips[0].kind, .question)
    }
    func testDetectsInterrogativeWithoutMark() {
        let chips = ChipDetector.detectQuestions(in: "how does the pricing model work for enterprise")
        XCTAssertEqual(chips.map(\.text), ["how does the pricing model work for enterprise?"])
    }
    func testIgnoresStatementsAndShortFragments() {
        XCTAssertTrue(ChipDetector.detectQuestions(in: "We shipped it. Is it.").isEmpty)
        XCTAssertTrue(ChipDetector.detectQuestions(in: "The what now sounds fine to me").isEmpty)
    }
    func testDedup() {
        let chips = ChipDetector.detectQuestions(in: "What's the price? What's the price?")
        XCTAssertEqual(chips.count, 1)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter ChipDetectorTests` — FAIL
- [ ] **Step 3: Implement** — sentence split via regex `[.?!]` keeping terminator, interrogative-prefix check, dedup via `Set<String>`
- [ ] **Step 4: Run** — PASS
- [ ] **Step 5: Commit** — `feat: local question chip detection`

---

### Task 4: SSEParser

**Files:**
- Create: `Sources/CluelessCore/SSEParser.swift`
- Test: `Tests/CluelessCoreTests/SSEParserTests.swift`

**Interfaces:**
- Produces: `public struct SSEParser { public init(); public mutating func feed(_ data: Data) -> [String] }`
  - Accumulates bytes; returns the payload of each complete `data:` line (event terminated by blank line or newline-delimited `data:` lines), skipping `event:`/`id:`/comment lines and the literal `[DONE]`. Handles payloads split across `feed` calls.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CluelessCore

final class SSEParserTests: XCTestCase {
    func testSingleEvent() {
        var p = SSEParser()
        let out = p.feed(Data("data: {\"a\":1}\n\n".utf8))
        XCTAssertEqual(out, ["{\"a\":1}"])
    }
    func testEventSplitAcrossFeeds() {
        var p = SSEParser()
        XCTAssertEqual(p.feed(Data("data: {\"a\"".utf8)), [])
        XCTAssertEqual(p.feed(Data(":1}\n\n".utf8)), ["{\"a\":1}"])
    }
    func testSkipsEventLinesAndDone() {
        var p = SSEParser()
        let out = p.feed(Data("event: message_stop\ndata: [DONE]\ndata: x\n\n".utf8))
        XCTAssertEqual(out, ["x"])
    }
    func testMultipleEventsInOneFeed() {
        var p = SSEParser()
        let out = p.feed(Data("data: 1\n\ndata: 2\n\n".utf8))
        XCTAssertEqual(out, ["1", "2"])
    }
}
```

- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement** — buffer `String`, split on `\n`, keep trailing incomplete line in buffer, extract `data: ` prefixed payloads
- [ ] **Step 4: Run** — PASS
- [ ] **Step 5: Commit** — `feat: SSE stream parser`

---

### Task 5: LLM provider layer (Gemini + Anthropic)

**Files:**
- Create: `Sources/CluelessCore/LLM.swift` (request/response types + protocol)
- Create: `Sources/CluelessCore/GeminiProvider.swift`, `Sources/CluelessCore/AnthropicProvider.swift`
- Test: `Tests/CluelessCoreTests/LLMProviderTests.swift`

**Interfaces:**
- Produces:
  - `public struct LLMRequest { public enum Part { case text(String); case imagePNG(Data) }; public var system: String; public var parts: [Part]; public var maxTokens: Int; public init(system: String, parts: [Part], maxTokens: Int = 2048) }`
  - `public protocol LLMProvider { func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> }` — yields text deltas
  - `public struct GeminiProvider: LLMProvider { public init(apiKey: String, model: String = "gemini-2.5-flash-lite", session: URLSession = .shared) }`
    - internal (test-visible) `func makeURLRequest(_ r: LLMRequest) throws -> URLRequest` — POST `https://generativelanguage.googleapis.com/v1beta/models/<model>:streamGenerateContent?alt=sse`, key in `x-goog-api-key` header, body `{"systemInstruction":{"parts":[{"text":…}]},"contents":[{"role":"user","parts":[{"text":…},{"inlineData":{"mimeType":"image/png","data":"<b64>"}}]}],"generationConfig":{"maxOutputTokens":N}}`
    - internal `static func delta(fromChunk: Data) -> String?` — extracts `candidates[0].content.parts[*].text` joined
  - `public struct AnthropicProvider: LLMProvider { public init(apiKey: String, model: String = "claude-opus-4-8", session: URLSession = .shared) }`
    - internal `func makeURLRequest(_ r: LLMRequest) throws -> URLRequest` — POST `https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`; body `{"model":…,"max_tokens":N,"stream":true,"system":…,"messages":[{"role":"user","content":[{"type":"text","text":…}]}]}` (images: `{"type":"image","source":{"type":"base64","media_type":"image/png","data":…}}`)
    - internal `static func delta(fromChunk: Data) -> String?` — returns text only for `type == "content_block_delta"` and `delta.type == "text_delta"`
  - Both `stream` impls: `session.bytes(for:)` → feed into `SSEParser` → yield deltas; non-2xx → throw `LLMError.http(status: Int, body: String)`; `public enum LLMError: Error { case http(status: Int, body: String); case missingKey }`

- [ ] **Step 1: Write failing tests** (request encoding + chunk decoding; no network)

```swift
import XCTest
@testable import CluelessCore

final class LLMProviderTests: XCTestCase {
    func testGeminiRequestEncoding() throws {
        let p = GeminiProvider(apiKey: "KEY")
        let req = try p.makeURLRequest(LLMRequest(system: "sys", parts: [.text("hi")], maxTokens: 100))
        XCTAssertEqual(req.url!.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:streamGenerateContent?alt=sse")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "KEY")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let sys = body["systemInstruction"] as! [String: Any]
        XCTAssertNotNil(sys["parts"])
        let cfg = body["generationConfig"] as! [String: Any]
        XCTAssertEqual(cfg["maxOutputTokens"] as! Int, 100)
    }

    func testGeminiDeltaDecoding() {
        let chunk = #"{"candidates":[{"content":{"parts":[{"text":"Hel"},{"text":"lo"}],"role":"model"}}]}"#
        XCTAssertEqual(GeminiProvider.delta(fromChunk: Data(chunk.utf8)), "Hello")
    }

    func testAnthropicRequestEncoding() throws {
        let p = AnthropicProvider(apiKey: "AK")
        let req = try p.makeURLRequest(LLMRequest(system: "s", parts: [.text("q")], maxTokens: 16000))
        XCTAssertEqual(req.url!.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "AK")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as! String, "claude-opus-4-8")
        XCTAssertEqual(body["stream"] as! Bool, true)
    }

    func testAnthropicDeltaDecoding() {
        let delta = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#
        XCTAssertEqual(AnthropicProvider.delta(fromChunk: Data(delta.utf8)), "Hi")
        let other = #"{"type":"message_start"}"#
        XCTAssertNil(AnthropicProvider.delta(fromChunk: Data(other.utf8)))
    }

    func testImagePartEncodingGemini() throws {
        let p = GeminiProvider(apiKey: "K")
        let png = Data([0x89, 0x50])
        let req = try p.makeURLRequest(LLMRequest(system: "", parts: [.text("what is this"), .imagePNG(png)]))
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let contents = body["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        XCTAssertEqual(parts.count, 2)
        let inline = parts[1]["inlineData"] as! [String: Any]
        XCTAssertEqual(inline["data"] as! String, png.base64EncodedString())
    }
}
```

- [ ] **Step 2: Run** `swift test --filter LLMProviderTests` — FAIL
- [ ] **Step 3: Implement `LLM.swift`, both providers** (encoding via `JSONSerialization`; `stream` uses `URLSession.bytes`, checks `(response as! HTTPURLResponse).statusCode`, feeds `SSEParser`, maps chunks through `delta(fromChunk:)`, finishes stream on end)
- [ ] **Step 4: Run** — PASS
- [ ] **Step 5: Commit** — `feat: provider-agnostic LLM layer with Gemini and Anthropic`

---

### Task 6: PromptBuilder

**Files:**
- Create: `Sources/CluelessCore/InsightAction.swift`, `Sources/CluelessCore/PromptBuilder.swift`
- Test: `Tests/CluelessCoreTests/PromptBuilderTests.swift`

**Interfaces:**
- Produces:
  - `public enum InsightAction: String, CaseIterable, Identifiable { case sayNext, followUps, factCheck, whoIsThis, recap; public var title: String }` (titles: "What should I say next", "Follow-up questions", "Fact check", "Who am I talking to", "Recap")
  - `public struct PromptContext { public var transcript: String; public var uploadedContext: String; public var participants: [String]; public init(transcript: String, uploadedContext: String = "", participants: [String] = []) }`
  - `public enum PromptBuilder {`
    - `public static func request(for action: InsightAction, context: PromptContext) -> LLMRequest` — recap gets `maxTokens: 4096`, others 1024; every prompt embeds transcript; whoIsThis embeds participants + uploadedContext; uploadedContext appended to all when non-empty
    - `public static func chatRequest(question: String, smartMode: Bool, context: PromptContext) -> LLMRequest` — smartMode swaps system prompt to technical persona (mentions code blocks, no filler)
    - `public static func chipExtractionRequest(recentTranscript: String) -> LLMRequest` — asks for strict JSON `{"questions":[],"keywords":[],"topics":[]}`
    - `public static func screenAnswerRequest(pngData: Data, context: PromptContext) -> LLMRequest` — parts = [text prompt, .imagePNG]
    - `public static func summaryRequest(fullTranscript: String) -> LLMRequest` — asks for Markdown with sections: Key Takeaways, Decisions, Next Steps, Action Items; `maxTokens: 8192`
    - `public static func parseChips(fromJSON: String) -> [Chip]` — tolerant of markdown fences; questions→`.question`, keywords→`.keyword`, topics→`.topic` `}`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CluelessCore

final class PromptBuilderTests: XCTestCase {
    let ctx = PromptContext(transcript: "Me: hi\nThem: we need SSO by Q3",
                            uploadedContext: "ACME renewal notes",
                            participants: ["Jane Doe"])

    func testEveryActionEmbedsTranscript() {
        for action in InsightAction.allCases {
            let r = PromptBuilder.request(for: action, context: ctx)
            let text = r.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
            XCTAssertTrue(text.contains("we need SSO by Q3"), "\(action) missing transcript")
        }
    }
    func testWhoIsThisIncludesParticipantsAndFiles() {
        let r = PromptBuilder.request(for: .whoIsThis, context: ctx)
        let text = r.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        XCTAssertTrue(text.contains("Jane Doe"))
        XCTAssertTrue(text.contains("ACME renewal notes"))
    }
    func testSmartModeSwapsSystemPrompt() {
        let normal = PromptBuilder.chatRequest(question: "q", smartMode: false, context: ctx)
        let smart = PromptBuilder.chatRequest(question: "q", smartMode: true, context: ctx)
        XCTAssertNotEqual(normal.system, smart.system)
        XCTAssertTrue(smart.system.lowercased().contains("code"))
    }
    func testParseChipsTolerantOfFences() {
        let json = "```json\n{\"questions\":[\"What is SSO?\"],\"keywords\":[\"SSO\"],\"topics\":[\"security\"]}\n```"
        let chips = PromptBuilder.parseChips(fromJSON: json)
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips.filter { $0.kind == .question }.first?.text, "What is SSO?")
    }
    func testRecapGetsBiggerBudget() {
        XCTAssertGreaterThan(PromptBuilder.request(for: .recap, context: ctx).maxTokens,
                             PromptBuilder.request(for: .sayNext, context: ctx).maxTokens)
    }
}
```

- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement** per interface block (prompt templates as multiline string constants; `parseChips` strips ```` ```json ```` fences then `JSONSerialization`)
- [ ] **Step 4: Run** — PASS
- [ ] **Step 5: Commit** — `feat: prompt builder for all insight actions`

---

### Task 7: Deepgram parsing + streaming client

**Files:**
- Create: `Sources/CluelessCore/DeepgramMessageParser.swift`
- Create: `Sources/Clueless/Services/DeepgramStreamClient.swift`
- Test: `Tests/CluelessCoreTests/DeepgramMessageParserTests.swift`

**Interfaces:**
- Produces (Core):
  - `public struct DeepgramResult: Equatable { public let transcript: String; public let isFinal: Bool; public let speakerID: Int? }`
  - `public enum DeepgramMessageParser { public static func parse(_ data: Data) -> DeepgramResult? }` — nil for non-`Results` messages or empty transcripts; `speakerID` = majority `speaker` over `channel.alternatives[0].words`
- Produces (App):
  - `final class DeepgramStreamClient { init(apiKey: String, source: String); var onResult: ((DeepgramResult) -> Void)?; var onStateChange: ((Bool) -> Void)?; func connect(); func send(pcm: Data); func finish() }`
  - Behavior: URL per Global Constraints; `URLSessionWebSocketTask`; receive loop parses via `DeepgramMessageParser`; keepalive `{"type":"KeepAlive"}` every 5 s when idle; on socket failure → reconnect with backoff 1 s, 2 s, 4 s… max 30 s and buffer up to 30 s of PCM (ring buffer, flushed on reconnect); `finish()` sends `{"type":"CloseStream"}` and cancels.

- [ ] **Step 1: Write failing parser tests**

```swift
import XCTest
@testable import CluelessCore

final class DeepgramMessageParserTests: XCTestCase {
    func testParsesFinalWithSpeaker() {
        let json = #"""
        {"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"hello there",
         "words":[{"word":"hello","speaker":0},{"word":"there","speaker":0}]}]}}
        """#
        let r = DeepgramMessageParser.parse(Data(json.utf8))
        XCTAssertEqual(r, DeepgramResult(transcript: "hello there", isFinal: true, speakerID: 0))
    }
    func testMajoritySpeakerWins() {
        let json = #"""
        {"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"a b c",
         "words":[{"word":"a","speaker":1},{"word":"b","speaker":1},{"word":"c","speaker":0}]}]}}
        """#
        XCTAssertEqual(DeepgramMessageParser.parse(Data(json.utf8))?.speakerID, 1)
    }
    func testIgnoresEmptyAndNonResults() {
        XCTAssertNil(DeepgramMessageParser.parse(Data(#"{"type":"Metadata"}"#.utf8)))
        let empty = #"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":""}]}}"#
        XCTAssertNil(DeepgramMessageParser.parse(Data(empty.utf8)))
    }
}
```

- [ ] **Step 2: Run** — FAIL
- [ ] **Step 3: Implement parser** (Codable structs, optional `words`)
- [ ] **Step 4: Run** — PASS; commit — `feat: deepgram message parsing`
- [ ] **Step 5: Implement `DeepgramStreamClient`** per behavior block (no unit test — network component; exercised in Task 9 manual verify). Build: `swift build` — compiles clean.
- [ ] **Step 6: Commit** — `feat: deepgram websocket streaming client`

---

### Task 8: KeychainStore + Settings window

**Files:**
- Create: `Sources/Clueless/Services/KeychainStore.swift`
- Create: `Sources/Clueless/UI/SettingsView.swift`
- Modify: `Sources/Clueless/AppDelegate.swift` (menu item + window to open Settings)

**Interfaces:**
- Produces:
  - `enum APIKeyName: String, CaseIterable { case deepgram, gemini, anthropic; var displayName: String }`
  - `struct KeychainStore { static func set(_ value: String, for key: APIKeyName) throws; static func get(_ key: APIKeyName) -> String?; static func delete(_ key: APIKeyName) throws }` — generic-password items, service `com.clueless.app`, account = raw value
  - `SettingsView: View` — SecureFields for the three keys (load on appear, save on change), placeholder section "Context files" (filled Task 13), hotkey hint text
- Consumes: nothing from Core

- [ ] **Step 1: Implement KeychainStore** (SecItemAdd/CopyMatching/Update/Delete; `kSecClassGenericPassword`)
- [ ] **Step 2: Implement SettingsView + AppDelegate wiring** (Cmd+, opens window; standard NSWindow with NSHostingView)
- [ ] **Step 3: Verify** — `make run`; open Settings; paste dummy key; quit; relaunch; key still shown. `security find-generic-password -s com.clueless.app -a deepgram -w` prints it.
- [ ] **Step 4: Commit** — `feat: keychain-backed API key settings`

---

### Task 9: Audio capture + live transcription wiring

**Files:**
- Create: `Sources/Clueless/Services/MicTap.swift`, `Sources/Clueless/Services/SystemAudioTap.swift`
- Create: `Sources/Clueless/Services/TranscriptionService.swift`

**Interfaces:**
- Produces:
  - `final class MicTap { var onPCM: ((Data) -> Void)?; func start() throws; func stop() }` — AVAudioEngine input tap → `AVAudioConverter` to 16 kHz mono Int16 → Data chunks (~100 ms)
  - `final class SystemAudioTap: NSObject { var onPCM: ((Data) -> Void)?; func start() async throws; func stop() }` — `SCShareableContent` → display filter excluding own app, `SCStreamConfiguration` with `capturesAudio = true`, `sampleRate = 16000`, `channelCount = 1`; implements `SCStreamOutput` for `.audio` sample buffers → Int16 Data. Minimal 2×2 px video config (SCK requires a video stream; frames dropped).
  - `final class TranscriptionService { init(store: TranscriptStore); var onReconnecting: ((Bool) -> Void)?; func start(deepgramKey: String) async throws; func stop() }` — owns MicTap + SystemAudioTap + two `DeepgramStreamClient`s; mic results → `store.applyPartial/Final(speaker: .me, …)`; system results → `.them(speakerID ?? 0)`
- Consumes: `TranscriptStore`, `DeepgramStreamClient`, `DeepgramResult` (Tasks 2, 7)

- [ ] **Step 1: Implement MicTap** (installTap on inputNode, converter to `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)`)
- [ ] **Step 2: Implement SystemAudioTap** per interface
- [ ] **Step 3: Implement TranscriptionService**; temporary debug hook in AppDelegate: start on launch when Deepgram key present, `store.onChange` prints last turn to stdout
- [ ] **Step 4: Manual verify** — `make run` from terminal with real Deepgram key: speak → `Me:` lines appear; play a YouTube video → `Them:` lines appear. Expect TCC prompts for mic + screen recording on first run.
- [ ] **Step 5: Commit** — `feat: system+mic audio capture streaming into live transcript`

---

### Task 10: Overlay window + core UI

**Files:**
- Create: `Sources/Clueless/UI/OverlayPanel.swift` — NSPanel subclass
- Create: `Sources/Clueless/UI/OverlayView.swift` — root SwiftUI (transcript + insights + chips + chat bar)
- Create: `Sources/Clueless/AppState.swift` — `@MainActor final class AppState: ObservableObject`
- Modify: `Sources/Clueless/AppDelegate.swift` — replace placeholder window with overlay

**Interfaces:**
- Produces:
  - `OverlayPanel`: `styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`, `titlebarAppearsTransparent = true`, `hidesOnDeactivate = false`; content = `NSHostingView(rootView: OverlayView().environmentObject(appState))`; default size 420×640, right edge of screen
  - `AppState` published state: `turns: [TranscriptTurn]`, `chips: [Chip]`, `insightText: String`, `insightStreaming: Bool`, `activeAction: InsightAction?`, `chatInput: String`, `smartMode: Bool`, `sessionActive: Bool`, `reconnecting: Bool`, `errorBanner: String?`
  - `AppState` methods (bodies wired in Task 11; stubs OK here): `startSession()`, `endSession()`, `run(action: InsightAction)`, `runChip(_ chip: Chip)`, `sendChat()`, `runScreenAnswer()`
  - `OverlayView` layout: header (session start/stop button, reconnect badge) → `TranscriptPanel` (ScrollViewReader auto-scroll, partials `.foregroundStyle(.secondary)`, finals labeled `Me:`/`Them:`) → `InsightsCard` (5 buttons from `InsightAction.allCases`, streamed `insightText` below, spinner while streaming) → chips row (wrapping HStack of Buttons) → `ChatBar` (TextField + Smart Mode Toggle + submit on `.keyboardShortcut(.return, modifiers: .command)`)
- Consumes: `TranscriptStore` via `store.onChange` → mirror into `AppState.turns` on main queue; `Chip`, `InsightAction` (Tasks 2, 3, 6)

- [ ] **Step 1: Implement AppState** (owns `TranscriptStore`, `TranscriptionService`; stub methods post state changes only)
- [ ] **Step 2: Implement OverlayPanel + OverlayView + subviews** per layout block
- [ ] **Step 3: Wire AppDelegate** — create AppState, OverlayPanel on launch; remove Task 9 debug hook (transcript now visible in panel)
- [ ] **Step 4: Manual verify** — `make run`: overlay floats over full-screen Zoom/browser, doesn't steal focus when clicked (typing continues in Zoom), draggable by background, live transcript scrolls while speaking
- [ ] **Step 5: Commit** — `feat: floating overlay with live transcript UI`

---

### Task 11: InsightEngine wiring (actions, chips loop, chat)

**Files:**
- Create: `Sources/Clueless/Services/InsightEngine.swift`
- Modify: `Sources/Clueless/AppState.swift` (real method bodies delegate to engine)

**Interfaces:**
- Produces:
  - `@MainActor final class InsightEngine { init(store: TranscriptStore, contextProvider: @escaping () -> PromptContext, liveLLM: @escaping () -> LLMProvider?, summaryLLM: @escaping () -> LLMProvider?) }`
  - `func run(action: InsightAction, onDelta: @escaping (String) -> Void, onDone: @escaping (Error?) -> Void)` — recap uses `summaryLLM` (Opus), others `liveLLM` (Gemini); cancels previous in-flight `Task` first
  - `func runFreeform(prompt question: String, smartMode: Bool, onDelta:…, onDone:…)`, `func runScreenAnswer(png: Data, onDelta:…, onDone:…)`
  - `func startChipLoop(onChips: @escaping ([Chip]) -> Void)` / `stopChipLoop()` — local `ChipDetector.detectQuestions` on every new final turn (observe store change, diff last processed index); every 15 s **or** every 5 new finals → `PromptBuilder.chipExtractionRequest` on liveLLM, accumulate stream, `parseChips`, merge (dedup by text, keep newest 8)
  - Timeouts: 15 s per live request via `Task` race; errors surface through `onDone(error)`
- Consumes: `PromptBuilder`, `LLMProvider`, `GeminiProvider`, `AnthropicProvider`, `ChipDetector`, `TranscriptStore`, `KeychainStore`

- [ ] **Step 1: Implement InsightEngine** per interface (single `currentTask: Task<Void, Never>?` for cancellation; chip loop = repeating `Task.sleep` loop + final-count trigger)
- [ ] **Step 2: Wire AppState methods** — `run(action:)` sets `activeAction`, clears `insightText`, appends deltas; `sendChat()` uses chat bar text; chips → `AppState.chips`; errors → `errorBanner` + retry button in InsightsCard
- [ ] **Step 3: Manual verify** — real keys, live meeting audio (YouTube interview): chips appear within ~20 s; each of the 5 actions streams an answer; tapping a second action cancels the first; chat bar Cmd+Enter answers with transcript context; Smart Mode changes tone on a coding question
- [ ] **Step 4: Commit** — `feat: insight actions, suggestion chips, AI chat wired to LLM`

---

### Task 12: Screen-answer hotkey + snapshot

**Files:**
- Create: `Sources/Clueless/Services/ScreenSnapshotService.swift`, `Sources/Clueless/Services/HotkeyManager.swift`
- Modify: `Sources/Clueless/AppState.swift`, `Sources/Clueless/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `enum ScreenSnapshotService { static func captureMainDisplayPNG() async throws -> Data }` — `SCShareableContent.current` → main display → `SCScreenshotManager.captureImage(contentFilter:configuration:)` → downscale to max 1600 px wide → PNG Data (excludes own overlay via content filter `excludingApplications`)
  - `final class HotkeyManager { init(); func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void); func unregister() }` — Carbon `RegisterEventHotKey` + `InstallEventHandler` (no extra TCC permission). Default: ⌘⇧Return (`kVK_Return`, `cmdKey|shiftKey`)
- Consumes: `InsightEngine.runScreenAnswer`, `PromptBuilder.screenAnswerRequest`

- [ ] **Step 1: Implement ScreenSnapshotService**
- [ ] **Step 2: Implement HotkeyManager; register in AppDelegate → `appState.runScreenAnswer()`**
- [ ] **Step 3: Manual verify** — open a code snippet on screen, press ⌘⇧Return while overlay unfocused: streamed answer describes/answers the on-screen content
- [ ] **Step 4: Commit** — `feat: get-answer hotkey with screen snapshot vision request`

---

### Task 13: File context (ContextStore + parsers)

**Files:**
- Create: `Sources/CluelessCore/ContextStore.swift`
- Create: `Sources/Clueless/Services/FileImporter.swift`
- Modify: `Sources/Clueless/UI/SettingsView.swift` (real "Context files" section)
- Test: `Tests/CluelessCoreTests/ContextStoreTests.swift`

**Interfaces:**
- Produces (Core):
  - `public struct ContextFile: Identifiable, Codable, Equatable { public let id: UUID; public let name: String; public let text: String; public init(name: String, text: String) }`
  - `public final class ContextStore { public init(); public private(set) var files: [ContextFile]; public func add(_ file: ContextFile); public func remove(id: UUID); public func combinedText(maxChars: Int) -> String }` — combined = `"## <name>\n<text>"` blocks, truncated per-file proportionally to fit maxChars (default call site 60_000)
- Produces (App):
  - `enum FileImporter { static func importFile(at url: URL) throws -> ContextFile }` — `.pdf` → PDFKit `PDFDocument.string`; `.docx` → `Process` `/usr/bin/unzip -p <file> word/document.xml` → strip XML tags (regex `<[^>]+>` → " ", `</w:p>` → "\n" first); `.txt/.md` → String(contentsOf:); else throw `ImportError.unsupportedType`
- Consumes: `PromptContext.uploadedContext` (Task 6) — AppState builds `PromptContext` with `contextStore.combinedText(maxChars: 60_000)`

- [ ] **Step 1: Write failing tests** (ContextStore add/remove/combine/truncate; XML-strip helper exposed as `FileImporter` is App-side — test the Core store only):

```swift
import XCTest
@testable import CluelessCore

final class ContextStoreTests: XCTestCase {
    func testCombinedTextFormatsAndTruncates() {
        let s = ContextStore()
        s.add(ContextFile(name: "a.md", text: String(repeating: "x", count: 100)))
        s.add(ContextFile(name: "b.md", text: String(repeating: "y", count: 100)))
        let combined = s.combinedText(maxChars: 120)
        XCTAssertTrue(combined.contains("## a.md"))
        XCTAssertTrue(combined.contains("## b.md"))
        XCTAssertLessThanOrEqual(combined.count, 140)  // headers excluded from budget
    }
    func testRemove() {
        let s = ContextStore()
        let f = ContextFile(name: "a", text: "t")
        s.add(f); s.remove(id: f.id)
        XCTAssertTrue(s.files.isEmpty)
    }
}
```

- [ ] **Step 2: Run** — FAIL; **Step 3: Implement ContextStore** — PASS; commit `feat: context store`
- [ ] **Step 4: Implement FileImporter + SettingsView file list** (NSOpenPanel add button, list with delete)
- [ ] **Step 5: Manual verify** — import a PDF and a docx; ask "Who am I talking to" → answer references file content
- [ ] **Step 6: Commit** — `feat: uploaded file context (pdf/docx/notes)`

---

### Task 14: SessionManager (lifecycle, calendar, persistence, summary)

**Files:**
- Create: `Sources/CluelessCore/SessionRecord.swift`
- Create: `Sources/Clueless/Services/SessionManager.swift`
- Create: `Sources/Clueless/UI/SummaryView.swift`
- Modify: `Sources/Clueless/AppState.swift`, `Sources/Clueless/AppDelegate.swift`
- Test: `Tests/CluelessCoreTests/SessionRecordTests.swift`

**Interfaces:**
- Produces (Core):
  - `public struct SessionRecord: Codable { public var id: UUID; public var startedAt: Date; public var endedAt: Date?; public var turns: [TranscriptTurn]; public var summaryMarkdown: String?; public init(startedAt: Date) }` + `public func markdownExport() -> String` (summary + full transcript)
- Produces (App):
  - `final class SessionManager` — responsibilities:
    - `start()` / `end()` mutate a current `SessionRecord`
    - 10 s timer flushes record JSON to `~/Library/Application Support/Clueless/sessions/<id>.json`
    - On init: if newest session file has `endedAt == nil` → expose `recoverableSession: SessionRecord?` (AppState offers "Resume session" alert)
    - Calendar: `EKEventStore.requestFullAccessToEvents`; poll every 60 s; event with URL/notes containing zoom/meet/teams link starting now → `onMeetingDetected(title:attendees:)` (AppState shows "Start session?" prompt); event end + 2 min → `onMeetingLikelyEnded`
    - Silence: fed `lastAudioActivity: Date` from TranscriptionService; >10 min → `onSilenceTimeout` (AppState confirm dialog)
    - `generateSummary(llm: LLMProvider, transcript: String) async throws -> String` — `PromptBuilder.summaryRequest`, accumulate stream
  - `SummaryView` — rendered Markdown (`Text(AttributedString(markdown:))` per-line fallback), "Copy Markdown" + "Save .md" (NSSavePanel) buttons
- Consumes: `PromptBuilder.summaryRequest`, `AnthropicProvider`, `TranscriptStore.fullText`, `TranscriptTurn`

- [ ] **Step 1: Write failing tests** — `SessionRecord` round-trips through `JSONEncoder`/`Decoder`; `markdownExport()` contains summary + `Me:` lines:

```swift
import XCTest
@testable import CluelessCore

final class SessionRecordTests: XCTestCase {
    func testCodableRoundTrip() throws {
        var rec = SessionRecord(startedAt: Date(timeIntervalSince1970: 0))
        rec.turns = [TranscriptTurn(id: UUID(), speaker: .me, text: "hi", timestamp: Date(), isFinal: true)]
        rec.summaryMarkdown = "# Summary"
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(SessionRecord.self, from: data)
        XCTAssertEqual(back.turns[0].text, "hi")
        XCTAssertEqual(back.summaryMarkdown, "# Summary")
    }
    func testMarkdownExport() {
        var rec = SessionRecord(startedAt: Date())
        rec.turns = [TranscriptTurn(id: UUID(), speaker: .me, text: "hello", timestamp: Date(), isFinal: true)]
        rec.summaryMarkdown = "## Key Takeaways"
        let md = rec.markdownExport()
        XCTAssertTrue(md.contains("## Key Takeaways"))
        XCTAssertTrue(md.contains("Me: hello"))
    }
}
```

- [ ] **Step 2: Run** — FAIL; **Step 3: Implement SessionRecord** — PASS; commit `feat: session record persistence model`
- [ ] **Step 4: Implement SessionManager + SummaryView + AppState/AppDelegate wiring** (end of session → summary window opens with streaming summary)
- [ ] **Step 5: Manual verify** — run short fake meeting, end it → summary window streams takeaways; kill -9 app mid-session, relaunch → resume offered; save .md works
- [ ] **Step 6: Commit** — `feat: session lifecycle, calendar detection, post-meeting summary`

---

### Task 15: Onboarding + error surfaces polish

**Files:**
- Create: `Sources/Clueless/UI/OnboardingView.swift`
- Modify: `Sources/Clueless/AppDelegate.swift`, `Sources/Clueless/UI/OverlayView.swift`

**Interfaces:**
- Produces: first-run (UserDefaults flag) onboarding window: 4 pages — welcome, mic permission (trigger + status), screen recording (open System Settings deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`), calendar (optional), API keys (inline fields reusing KeychainStore)
- Overlay polish: `errorBanner` display + retry, "reconnecting" pill when Deepgram down, action buttons disabled with tooltip when key missing, session start disabled until mic or screen permission granted

- [ ] **Step 1: Implement OnboardingView + gating**
- [ ] **Step 2: Manual verify** — `tccutil reset Microphone com.clueless.app; tccutil reset ScreenCapture com.clueless.app`, delete UserDefaults flag, relaunch → onboarding walks through grants; deny screen recording → transcript still works mic-only with inline hint
- [ ] **Step 3: Commit** — `feat: first-run onboarding and graceful permission degradation`

---

### Task 16: dmg packaging + smoke test

**Files:**
- Create: `scripts/make-dmg.sh`
- Modify: `Makefile` (dmg target already references it), `README.md` (create: install + right-click-open note, key setup)

**Interfaces:**
- Produces: `dist/Clueless.dmg` with app + `/Applications` symlink

- [ ] **Step 1: Write make-dmg.sh**

```bash
#!/bin/bash
set -euo pipefail
bash scripts/bundle.sh release
STAGE=$(mktemp -d)
cp -R dist/Clueless.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/Clueless.dmg
hdiutil create -volname "Clueless" -srcfolder "$STAGE" -ov -format UDZO dist/Clueless.dmg
rm -rf "$STAGE"
echo "Built dist/Clueless.dmg"
```

- [ ] **Step 2: Run** `make dmg` — expect `Built dist/Clueless.dmg`; mount it, drag to /Applications, launch from there (right-click → Open first time)
- [ ] **Step 3: Full manual smoke pass** (spec §7): play test meeting audio → live transcript both speakers → chips → all 5 actions → chat + Smart Mode → ⌘⇧Return screen answer → file upload referenced → end session → summary → export .md → crash-resume
- [ ] **Step 4: Run** `swift test` — all green
- [ ] **Step 5: Commit** — `feat: dmg packaging and README`

---

## Self-review notes

- **Spec coverage:** §2 stack → Tasks 1,5,7; §3 architecture → all; §4 flows → Tasks 9–14; §5 permissions → Tasks 9,15; §6 errors → Tasks 7,11,15; §7 testing → per-task tests + Task 16 smoke; §8 packaging → Tasks 1,16; §9 order preserved. CRM absent by design.
- **Type consistency:** `TranscriptStore.applyPartial/applyFinal` names used in Tasks 7/9; `PromptContext` produced in Task 6 consumed in 11/13; `LLMProvider.stream` in 5/11/14; `Chip` in 3/6/11.
- **Known risk (flagged, not blocking):** SCK `capturesAudio` at 16 kHz mono direct — if SCK refuses non-48 kHz config on this OS, fall back to 48 kHz capture + downsample in `SystemAudioTap` (converter identical to MicTap's).
