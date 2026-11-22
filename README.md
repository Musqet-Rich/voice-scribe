# Voice Scribe

A native macOS menu-bar app for dictation and call transcription that runs entirely on your Mac. Hold a key, talk, let go, and the text appears wherever your cursor is. Record a call and get a transcript with speakers labelled and a summary.

No cloud, no account, no subscription. Speech recognition runs on the Neural Engine with Parakeet-family models via [FluidAudio](https://github.com/FluidInference/FluidAudio). Optional polish and summaries use a local LLM through [Ollama](https://ollama.com) or Apple Intelligence.

## Features

- **Hold to talk**: hold a key, speak, release, and the text is pasted at the cursor. Your clipboard is restored afterwards.
- **Any keys you like**: assign several keys per action in Settings, e.g. fn on the laptop and F19 on an external keyboard. Single modifier keys (fn, Right ⌥) work too.
- **Toggle dictation** for longer, hands-free passages.
- **Call transcripts**: records your mic and the Mac's audio output as separate tracks, so it works with Zoom, Meet, Teams and Slack without any integration. Produces a transcript labelled "Me" / "Speaker 1" / "Speaker 2", plus an optional summary with decisions and action items.
- **Microphone picker**: use a specific mic (e.g. a lapel receiver), with fallback to the system default when it's unplugged.
- **Corrections**: find/replace rules and custom vocabulary.
- **History** of every dictation.

## Requirements

- Apple Silicon Mac, macOS 15 or later
- Xcode 26 / Swift 6.2 toolchain
- Optional: [Ollama](https://ollama.com) for polish and summaries, or Apple Intelligence on macOS 26

## Setup

```bash
./scripts/make-signing-cert.sh   # one-off: stable local signing identity (asks for your password)
./run.sh                         # build, install to ~/Applications/Voice Scribe.app, launch
```

The signing identity matters: without it the app is ad-hoc signed, macOS forgets its Accessibility permission on every rebuild, and pasting silently stops working.

First launch:

1. Click the menu-bar mic and **Download Model** (Bark 3.0 Clean, about 410MB, one-off).
2. Grant **Microphone** and **Accessibility** permission (System Settings → Privacy & Security).
3. If you use fn: System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**.
4. On your first call recording, allow **System Audio Recording**.

## Default shortcuts

| Action | Default |
|---|---|
| Hold to talk | fn |
| Toggle dictation | F2 |
| Start/stop call recording | ⌃⌥⌘R |

Change them in Settings → Shortcuts.

## Speech models

| Model | Notes |
|---|---|
| Bark 3.0 Clean (default) | English. Drops fillers, false starts and repeats, ideal for dictation |
| Bark 3.0 | English, verbatim |
| Parakeet Ultra | 25 European languages |
| Parakeet v2 | English, highest recall |

## Local AI (optional)

Settings → AI (local):

- **Polish** runs after every dictation (punctuation, self-corrections, British spelling), so use a small, fast model, e.g. `ollama pull qwen3:4b`.
- **Summaries** run once per call, so a large model is fine.

## Data

```
~/.voice-scribe/
├── history.json
├── corrections.json         # {"heard": "wanted"}; read at launch
└── calls/<yyyy-MM-dd HHmm>/
    ├── mic.caf              # your side
    ├── system.caf           # their side
    └── transcript.md
```

Speech models are cached by FluidAudio under `~/Library/Application Support/FluidAudio/`.

## Tips

- Use headphones on calls. On speakers, your mic picks up the other side and it gets attributed to you.
- Corrections are applied as whole-word, case-insensitive replacements. A plain term mapped to itself (`"Odoo": "Odoo"`) fixes its capitalisation.
