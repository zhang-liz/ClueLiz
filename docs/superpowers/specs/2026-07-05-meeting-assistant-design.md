# Clueless — Real-Time Meeting Assistant for macOS

**Date:** 2026-07-05
**Status:** Approved design, pre-implementation
**Target:** Native macOS app (Swift/SwiftUI), distributed as `.dmg`

## 1. Overview

Clueless is a native macOS meeting assistant. During a meeting it captures system and microphone audio, transcribes it live, and shows a floating always-on-top overlay with a live transcript, AI-generated insight actions, auto-detected suggestion chips, and a free-form AI chat bar. After the meeting it produces a shareable summary.

### Scope

**In scope (v1):**
- Live system + mic audio capture and streaming transcription (Deepgram)
- Floating, movable, non-activating overlay window (transcript panel + insights card)
- Auto-detected suggestion chips (questions, keywords, topics)
- One-tap insight actions: What should I say next, Follow-up questions, Fact check, Who am I talking to, Recap
- AI chat bar with Cmd+Enter submit and Smart Mode toggle
- "Get Answer" global hotkey: answers based on current screen contents (screenshot + vision model)
- File upload context (PDF, docx, plain notes) referenced by all AI actions
- Meeting auto-end detection (calendar via EventKit, silence timeout) and manual controls
- Post-meeting summary (key takeaways, decisions, next steps) with Markdown export
- Local session persistence and crash recovery
- `.dmg` packaging, optionally signed/notarized

**Out of scope (v1):**
- CRM connectors (Salesforce, HubSpot) — explicitly deferred
- Embeddings/RAG for uploaded files (plain text extraction + prompt stuffing instead)
- Windows/Linux support
- UI snapshot tests

## 2. Technology choices

| Concern | Choice | Rationale |
|---|---|---|
| Platform | Swift + SwiftUI, macOS 14+ | Lightest RAM/CPU during meetings; first-class ScreenCaptureKit audio, NSPanel overlay, global hotkeys, screen capture |
| System audio | ScreenCaptureKit | No virtual-driver install; macOS 13+ API, stable on 14+ |
| Mic audio | AVAudioEngine | Standard |
| STT | Deepgram streaming WebSocket | ~150–300 ms partials, built for live captions, diarization included (~$0.46/hr) |
| Live LLM | Gemini 2.5 Flash-Lite (SSE streaming) | Fastest TTFT (~0.35 s), cheapest mainstream ($0.10/$0.40 per 1M tokens) |
| Summary LLM | Claude Opus 4.8 (`claude-opus-4-8`, SSE streaming) | Top-tier summary/writing quality ($5/$25 per 1M tokens) |
| LLM abstraction | Provider-agnostic Swift protocol | Swapping providers is a config change; Swift has no official Anthropic/Google SDK, so both providers are raw HTTP + SSE |
| API keys | User-supplied, stored in macOS Keychain | Entered once in Settings |
| File parsing | PDFKit (PDF), XML unzip (docx), plain read (txt/md) | No third-party parsing deps |
| Calendar | EventKit | Meeting start/end detection |

### Latency architecture (core product requirement)

- **Stream everything:** Deepgram partials render immediately; all LLM responses stream token-by-token into the UI.
- **Warm connections:** Deepgram WebSocket stays open for the whole session; LLM HTTP clients are reused (connection pooling).
- **Rolling context ready:** transcript buffer is kept pre-formatted so an action tap fires a request with zero preparation.
- **Fast model for live actions, big model only where latency is acceptable** (recap, post-meeting summary).
- **Cancellation:** an in-flight insight request is cancelled when a new action is tapped.

## 3. Architecture

Single app process, layered modules. UI layer depends on core layers; core layers are pure Swift with no UI imports. Layers are local Swift packages to enforce the boundary.

```
Clueless.app (SwiftUI)
├─ UI Layer
│  ├─ OverlayWindow — NSPanel: floating, non-activating, all-Spaces, draggable
│  │  ├─ TranscriptPanel — live scroll, partials gray/mutable, finals committed + speaker-tagged
│  │  ├─ InsightsCard — 5 action buttons, streamed answer area
│  │  ├─ SuggestionChips — tappable, auto-detected
│  │  └─ ChatBar — text input, Cmd+Enter, Smart Mode toggle
│  ├─ SettingsWindow — API keys, file uploads, hotkey config, session controls
│  └─ SummaryWindow — post-meeting summary, Markdown export
├─ Core Layers
│  ├─ AudioCaptureService
│  │  ├─ SystemAudioTap (ScreenCaptureKit)
│  │  └─ MicTap (AVAudioEngine)
│  ├─ TranscriptionService
│  │  └─ DeepgramStreamClient — WebSocket, partials + finals + diarization
│  ├─ LLMService — provider-agnostic protocol
│  │  ├─ GeminiProvider (Flash-Lite; text + vision; SSE)
│  │  └─ AnthropicProvider (Opus 4.8; SSE)
│  ├─ InsightEngine
│  │  ├─ TranscriptStore — rolling buffer, speaker-tagged turns
│  │  ├─ ChipDetector — local regex pass + periodic LLM extraction
│  │  └─ PromptBuilder — action → prompt template + context assembly
│  ├─ ContextStore — extracted text of uploaded files + participant info
│  ├─ ScreenSnapshotService — hotkey → screenshot → vision request
│  └─ SessionManager — start/end detection, EventKit, summary trigger, persistence
```

## 4. Data flow

### Live transcription

```
ScreenCaptureKit (system) ─┐
                           ├─► per-source 16 kHz PCM ─► Deepgram WS (one stream per source)
AVAudioEngine (mic) ───────┘
Deepgram partials (~300 ms) ─► TranscriptStore ─► TranscriptPanel (gray, mutable)
Deepgram finals ─► TranscriptStore (committed, speaker-tagged)
```

Two separate Deepgram streams (mic and system) so the speaker side is always known: mic = "Me", system = "Them". Deepgram diarization further splits multiple remote voices ("Them 1", "Them 2").

### Suggestion chips

- Every committed final → local regex pass (question marks, interrogative patterns) → instant question chips.
- Every ~15 s or 5 finals (whichever first) → one Flash-Lite call extracting questions/keywords/topics from the recent transcript as structured JSON → chips rendered below the insights card.
- Tapping a chip runs an "answer/explain this" action with the chip content.

### Insight actions

Each action = PromptBuilder template + rolling transcript window + uploaded-file context + participant info. Responses stream into the insights card.

| Action | Model | Context specifics |
|---|---|---|
| What should I say next | Flash-Lite | Last ~30 turns, weighted toward "Them" |
| Follow-up questions | Flash-Lite | Recent topic segment |
| Fact check | Flash-Lite | Recent transcript segment; the model identifies the latest factual claim(s) and assesses them |
| Who am I talking to | Flash-Lite | Calendar attendee names + uploaded files |
| Recap | Opus 4.8 | Full transcript so far |

### Chat bar

Free text + Cmd+Enter → Flash-Lite with rolling transcript context. **Smart Mode** toggle swaps the system prompt to a technical/coding persona (precise, code-block-friendly, no conversational filler).

### Get Answer hotkey

Default ⌘⇧Return (configurable). Captures the frontmost screen via ScreenCaptureKit → PNG → Flash-Lite vision request ("answer what is on screen; use the meeting transcript as context") → streams into the insights card. No typed input required.

### Session lifecycle

- **Start:** manual button, or prompt when an EventKit calendar event containing a video-call link begins.
- **End:** manual; calendar event end + 2 min grace; or >10 min audio silence → confirmation dialog.
- **On end:** full transcript → Opus 4.8 → summary (key takeaways, decisions, next steps, action items) → SummaryWindow → copy as Markdown or save `.md`.
- **Persistence:** transcript + summary saved under `~/Library/Application Support/Clueless/sessions/`. Transcript flushed to disk every 10 s; on relaunch after a crash the app offers "resume session".

## 5. Permissions

First-run onboarding walks through each grant:

| Permission | Used for | If denied |
|---|---|---|
| Screen Recording (TCC) | System audio capture, screen snapshots | Transcript limited to mic; Get Answer disabled; inline hint to grant |
| Microphone | Mic capture | System-audio-only transcription; inline hint |
| Calendar (EventKit) | Meeting start/end detection, attendee names | Manual start/end only |

Missing permissions degrade features gracefully with an inline "grant in System Settings" hint. Never crash on denial.

## 6. Error handling

- **Deepgram WS drop:** auto-reconnect with exponential backoff; banner "transcription reconnecting"; audio buffered up to 30 s during reconnect so no words are lost.
- **LLM request failure:** chip/card shows a short error + retry button. Timeouts: 15 s live actions, 60 s summary.
- **Rate limit (429):** honor `retry-after`; queue at most one pending action, drop older ones.
- **Missing API key:** dependent buttons disabled with "add key in Settings" tooltip.
- **Crash recovery:** 10 s transcript flush + resume-session offer (see lifecycle).

## 7. Testing

- **Unit:** ChipDetector regexes, PromptBuilder output, TranscriptStore buffer logic, provider request/response encoding against fixture JSON.
- **Integration:** DeepgramStreamClient against a mock WebSocket server fed recorded PCM fixtures; LLM providers against stubbed SSE responses.
- **Manual smoke script:** play a test meeting audio file → verify transcript, chips, each insight action, chat bar, hotkey, summary.

## 8. Packaging & distribution

- Pure Swift Package Manager project (no Xcode required — build machine has CLT only): executable target `Clueless` (UI + system services) + library target `CluelessCore` (pure logic, unit-tested).
- Build: `swift build -c release` → script assembles `Clueless.app` bundle (Info.plist with usage descriptions, ad-hoc codesign) → `hdiutil` → `Clueless.dmg`.
- Signing: Developer ID + notarization when an Apple Developer account is configured; otherwise unsigned dmg (right-click → Open for one-time Gatekeeper bypass). Flag-controlled in the build script.
- Makefile: `make build`, `make test`, `make dmg`.

## 9. Build order (phasing within the single build)

1. Project skeleton, layers, Settings + Keychain
2. Audio capture → Deepgram → live transcript in overlay
3. InsightEngine: actions, chips, chat bar (Gemini provider)
4. Screen-answer hotkey + Smart Mode
5. File context (ContextStore + parsers)
6. SessionManager: calendar detection, summary (Anthropic provider), persistence
7. Onboarding/permissions polish, error handling hardening
8. dmg packaging + full manual test pass

Thorough test-all pass at the end (per user direction) rather than shipping each phase.
