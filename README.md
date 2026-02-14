# Voice Scribe

A native macOS menubar app for local speech-to-text transcription, powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit).

## What It Does

- **Push-to-talk** (hold F1) or **toggle recording** (press F2) with global hotkeys
- Records audio from your microphone
- Transcribes locally using WhisperKit (no server, no internet needed after model download)
- Applies custom text corrections automatically
- Pastes the transcribed text at your cursor position
- Keeps a searchable history of all transcriptions

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3) — WhisperKit uses CoreML
- Xcode 15+

## Building

```bash
# Clone and open in Xcode
cd apps/voice-scribe-app
open Package.swift
```

In Xcode:
1. Select your signing team in the target settings
2. Build and Run (⌘R)

## First Launch

1. **Model download**: On first launch, you'll be prompted to download a WhisperKit model. The default `large-v3-turbo` is ~800MB and offers a good balance of speed and accuracy on M1 Max.
2. **Microphone access**: Grant microphone permission when prompted.
3. **Accessibility access**: Go to **System Settings → Privacy & Security → Accessibility** and add VoiceScribe. This is needed for the global hotkeys and simulated paste (⌘V).

## Usage

- **F1 (hold)**: Hold to record, release to transcribe and paste
- **F2 (press)**: Toggle recording on/off
- Click the menubar icon to access history, corrections, and settings

## Hotkeys

| Hotkey | Mode | Default |
|--------|------|---------|
| Hold-to-talk | Hold key to record, release to transcribe | F1 |
| Toggle | Press to start/stop recording | F2 |

Hotkeys are configurable in Settings (currently requires code change — UI picker coming soon).

## Corrections

Voice Scribe can automatically fix common transcription errors. Corrections are stored in `~/.voice-scribe/corrections.json` as a simple dictionary:

```json
{
    "monomi": "Monomi",
    "whisper kit": "WhisperKit"
}
```

You can manage corrections via the app UI or edit the JSON file directly.

## Data Storage

All data is stored locally in `~/.voice-scribe/`:

```
~/.voice-scribe/
├── models/           # Downloaded WhisperKit models
├── history.json      # Transcription history
└── corrections.json  # Text correction rules
```

## Architecture

```
Sources/VoiceScribe/
├── VoiceScribeApp.swift          # @main, MenuBarExtra
├── AppState.swift                # Central observable state
├── Audio/
│   ├── AudioRecorder.swift       # AVAudioEngine mic recording (16kHz mono WAV)
│   └── TonePlayer.swift          # Start/stop feedback tones
├── Transcription/
│   ├── TranscriptionEngine.swift # WhisperKit wrapper
│   └── CorrectionsManager.swift  # JSON corrections with regex replacement
├── Input/
│   ├── HotkeyManager.swift       # Global hotkeys via HotKey library
│   └── PasteManager.swift        # Clipboard + CGEvent ⌘V simulation
├── Views/
│   ├── MenuBarView.swift         # Main popover
│   ├── DownloadView.swift        # Model download UI
│   ├── HistoryView.swift         # Transcription history
│   ├── CorrectionsView.swift     # Corrections editor
│   └── SettingsView.swift        # App settings
└── Models/
    ├── Transcription.swift       # Transcription data model
    └── Correction.swift          # Correction data model
```
