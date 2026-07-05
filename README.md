# Clueless — Real-Time Meeting Assistant for macOS

Native macOS meeting copilot: live transcription of both sides of a call, a floating
always-on-top overlay with AI insight actions and suggestion chips, an AI chat bar,
a "Get Answer" screen hotkey, and a clean post-meeting summary.

## Requirements

- macOS 14 (Sonoma) or later
- API keys (entered once, stored in your Keychain):
  - [Deepgram](https://console.deepgram.com) — live transcription (free tier available)
  - [Google Gemini](https://aistudio.google.com/apikey) — live insights
  - [Anthropic](https://platform.claude.com) — post-meeting summaries

## Install

1. Open `Clueless.dmg`, drag **Clueless** to **Applications**.
2. First launch: the build is ad-hoc signed, so **right-click the app → Open → Open**
   (one time only).
3. Follow the onboarding: grant Microphone + Screen Recording (required for capturing
   the other participants' audio), optionally Calendar, and paste your API keys.

## Use

| Thing | How |
|---|---|
| Start/end a session | Button in the overlay header (auto-prompt when a calendar meeting starts) |
| Live transcript | Left in the overlay — "Me" is your mic, "Them" is system audio |
| Insight actions | One tap: What should I say next · Follow-ups · Fact check · Who am I talking to · Recap |
| Suggestion chips | Auto-detected questions/keywords/topics — tap to expand |
| AI chat | Type + ⌘⏎; toggle **Smart** for technical/coding answers |
| Get Answer (screen) | **⌘⇧⏎** anywhere — answers whatever is on your screen |
| Context files | Settings (⌘,) → add PDFs, docx, notes; referenced by all AI actions |
| Summary | Generated when the session ends — copy or save as Markdown |

Sessions and summaries persist in `~/Library/Application Support/Clueless/sessions/`.

## Build from source

Command Line Tools only — no Xcode required.

```sh
make test   # unit tests
make app    # dist/Clueless.app
make dmg    # dist/Clueless.dmg
```

To sign with a Developer ID instead of ad-hoc: `SIGN_ID="Developer ID Application: …" make dmg`.
