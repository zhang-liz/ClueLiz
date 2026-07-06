# ClueLiz

> Real-time meeting copilot for macOS — live transcription of both sides of a call, instant AI insights in a floating overlay, and a clean summary when the meeting ends.

[![Download](https://img.shields.io/badge/download-ClueLiz.dmg-blue)](https://github.com/zhang-liz/ClueLiz/releases/latest/download/ClueLiz.dmg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.10-orange)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

## About

ClueLiz sits in an always-on-top panel next to your meeting. It transcribes your microphone **and** the other participants' audio (via system-audio capture), and turns the live transcript into help you can actually use mid-call: what to say next, follow-up questions, fact checks, definitions of jargon the moment it comes up, and answers to anything on your screen — one hotkey away.

It is a native Swift app with no backend, no account, and no telemetry. Everything runs on your own API keys (Deepgram for transcription, Gemini for live insights, Anthropic for summaries), stored in the macOS Keychain, and all transcripts stay on your machine.

## Install

**[⬇ Download ClueLiz.dmg](https://github.com/zhang-liz/ClueLiz/releases/latest/download/ClueLiz.dmg)** — then:

1. Open the dmg and drag **ClueLiz** into **Applications**.
2. First launch only: the build is ad-hoc signed, so **right-click the app → Open → Open**.
3. Follow the onboarding to grant permissions and paste your API keys.

### Requirements

- macOS 14 (Sonoma) or later
- API keys (all have free or low-cost tiers):
  - [Deepgram](https://console.deepgram.com) — transcription
  - [Google Gemini](https://aistudio.google.com/apikey) — live insights
  - [Anthropic](https://platform.claude.com) — summaries

Permissions requested during onboarding: **Microphone** (your side of the call), **Screen Recording** (required by macOS to capture other participants' audio, and for Get Answer), and optionally **Calendar** (meeting start/end detection). Features degrade gracefully if a permission is denied — nothing blocks the app.

### Build from source

Xcode Command Line Tools (Swift 5.10+) are enough — no Xcode project.

```sh
git clone https://github.com/zhang-liz/ClueLiz.git
cd ClueLiz
make test   # run the unit tests
make app    # build dist/ClueLiz.app
make run    # build and launch
make dmg    # package dist/ClueLiz.dmg
```

To sign with a Developer ID instead of ad-hoc:

```sh
SIGN_ID="Developer ID Application: Your Name (TEAMID)" make dmg
```

## Features

- **Live two-sided transcript** — your mic is "Me", system audio is "Them"; multiple remote speakers are diarized ("Them", "Them 2", …). Reconnects automatically with backoff and buffers audio during network drops.
- **One-tap insight actions** — *What should I say next*, *Follow-up questions*, *Fact check*, *Who am I talking to*, *Recap*.
- **Suggestion chips** — questions, keywords, and topics detected from the conversation; tap one to expand it into an answer.
- **Auto-defined jargon** — acronyms and terms (e.g. "MCP") get short definitions as soon as they're mentioned, resolved in your configured meeting domain.
- **AI chat bar** — ask anything mid-meeting; toggle **Smart** mode for terse, code-first technical answers.
- **Get Answer (⌘⇧⏎)** — screenshots your screen and answers the most relevant question on it: an error message, a quiz question, a spreadsheet formula, a code snippet.
- **Context files** — drop in your resume, project docs, or notes (PDF, docx, txt, Markdown); every AI action uses them as ground truth about you.
- **Meeting lifecycle automation** — detects video-call events in your calendar and offers to start a session; prompts to wrap up when the event ends or after 10 minutes of silence.
- **Post-meeting summary** — key takeaways, decisions, next steps, and action items, streamed into a window you can copy or save as Markdown.
- **Crash recovery** — sessions persist to disk every 10 seconds; an unclean shutdown offers to resume where you left off.

## How it works

| Concern | Provider | Used for |
|---|---|---|
| Transcription | [Deepgram](https://deepgram.com) (`nova-3`, streaming WebSocket) | Live captions with interim results and speaker diarization |
| Live insights | [Google Gemini](https://ai.google.dev) | Insight actions, chat, chips, definitions, screen answers |
| Summaries | [Anthropic](https://www.anthropic.com) | Post-meeting summary and in-meeting recap |

All three run on your own API keys, entered once and stored in the macOS Keychain. There is no backend, no account, and no telemetry — the app talks only to those three APIs.

## Usage

| What | How |
|---|---|
| Start / end a session | Button in the overlay header (auto-prompt when a calendar meeting starts) |
| Live transcript | Top panel — finals are solid, in-progress speech is gray |
| Insight actions | One tap; the answer streams into the card below, with a Stop button |
| Suggestion chips | Tap a detected question/keyword/topic to explore it |
| AI chat | Type in the bottom bar; toggle **Smart** for technical answers |
| Context files | Settings → *Context files* → add PDFs, docx, txt, Markdown |
| Meeting domain | Settings → *Meeting domain* — how ambiguous terms and acronyms are interpreted |
| Overlay transparency | Slider in the header (30–100%) |
| Summary | Opens automatically when a session with transcript ends; copy or save as `.md` |

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧⏎ | Get Answer — answer whatever is on screen (global, works while other apps are focused) |
| ⏎ or ⌘⏎ | Send chat message |
| ⌘, | Settings |
| ⌘O | Bring the overlay to front |

Sessions and summaries are stored as JSON in `~/Library/Application Support/ClueLiz/sessions/`.

## Privacy & consent

- **What leaves your machine:** meeting audio goes to Deepgram; transcript excerpts, your context files, and (for Get Answer) screenshots go to Gemini; the full transcript goes to Anthropic when a summary is generated. Nothing is sent anywhere else.
- **What stays local:** session transcripts and summaries (plain JSON on disk), imported file text, and your settings. API keys live in the macOS Keychain.
- **Consent:** you are transcribing other people. Recording/transcription laws vary by jurisdiction (some require all-party consent) — tell your participants and check your local rules before using ClueLiz in real meetings.

## Troubleshooting

- **"Them" side is silent** — Screen Recording permission is missing or was granted mid-session; macOS may require relaunching the app after granting it.
- **"Add your … key in Settings"** — the action you tapped uses a provider whose key isn't set. Recap and summaries use Anthropic; everything else live uses Gemini.
- **Overlay disappeared** — ⌘O or menu bar → *Show Overlay*.
- **App won't open after download** — it's ad-hoc signed: right-click → Open → Open (first launch only).

## Development

```
Sources/
  ClueLizCore/      # pure logic: parsers, stores, prompt builder, LLM providers
  ClueLiz/          # macOS app: SwiftUI overlay/UI, audio capture, services
Tests/
  ClueLizCoreTests/ # swift-testing suites for everything in ClueLizCore
```

- `ClueLizCore` has no AppKit dependencies and is fully unit-tested (`make test`).
- App bundling is a plain script (`scripts/bundle.sh`); packaging is `scripts/make-dmg.sh`.
- Design docs live in [`docs/superpowers/specs`](docs/superpowers/specs/2026-07-05-meeting-assistant-design.md) and the build plan in [`docs/superpowers/plans`](docs/superpowers/plans/2026-07-05-meeting-assistant.md).

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. `make test` — all suites must pass.
2. Keep pure logic in `ClueLizCore` (with tests); keep AppKit/SwiftUI in the app target.
3. Match the existing code style — small files, doc comments on public types.

## License

[MIT](LICENSE) © Liz Zhang
