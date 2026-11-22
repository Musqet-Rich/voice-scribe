# Voice Scribe

macOS menu-bar app (SwiftPM, Swift 6.2 toolchain, Swift 5 language mode, macOS 15+) for local dictation and call transcription.

## Build
- `./run.sh` builds release, installs to `~/Applications/Voice Scribe.app`, signs, relaunches.
- Must sign with the "Voice Scribe Local Signing" identity (`scripts/make-signing-cert.sh`). Ad-hoc signing makes macOS drop the Accessibility grant on every rebuild and paste fails silently.
- First FluidAudio build takes 10+ minutes; incremental builds are seconds.

## Layout
- `Transcription/TranscriptionEngine.swift`: FluidAudio Parakeet (`AsrManager`), model kept warm.
- `Transcription/CallTranscriber.swift`: mic track → VAD → "Me"; system track → offline diarisation → "Speaker N".
- `Transcription/TextPolisher.swift`: Ollama / Apple Foundation Models for polish and summaries (settings via UserDefaults).
- `Audio/SystemAudioRecorder.swift`: Core Audio process tap + aggregate device for system audio.
- `Input/HotkeyManager.swift`: Carbon hotkeys for normal keys, NSEvent flagsChanged monitors for modifier-only keys (fn).

## Conventions
- Bundle ID `com.monomi.voice-scribe`: don't change it, TCC permissions and UserDefaults are keyed on it.
- User-facing text in British English.
- Data lives in `~/.voice-scribe/`.
