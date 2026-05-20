# Dyktando

Polish-focused on-device dictation for macOS — Wispr-Flow-style global hotkey, four selectable ASR engines, side-by-side comparison.

> **Status:** v0.1 — feature-complete on `feature/implementation`. All M0–M10 milestones implemented.

## Features

- **Global hotkey dictation** — hold `F5` (configurable), speak Polish, text appears at the cursor
- **Four ASR engines**, switchable from Settings:
  - **Parakeet TDT v3** — fastest on Apple Silicon (~80 ms), built-in VAD, default for PL
  - **Whisper large-v3-turbo** — 5× faster than v3, near-identical accuracy
  - **Whisper large-v3** — max accuracy, strongest code-switching
  - **Apple SFSpeechRecognizer (pl-PL)** — zero-download baseline
- **Comparison mode** (`⌃⌥C`) — record once, see all engines side-by-side, click winner
- **Multilingual / code-switching** — keeps English terms in English (`deployment`, `pull request`)
- **Polish post-processing** — capitalization, sentence-end period, dictation markers (`kropka` → `.`)
- **Fully on-device** — no audio leaves your Mac, no telemetry, no cloud

## Install

### From DMG

1. Download `Dyktando.dmg` from [Releases](#) (or build with `make dmg`).
2. Drag `Dyktando.app` to `/Applications`.
3. Launch. Follow the first-run onboarding (microphone + Accessibility).

### From source

```bash
git clone <repo-url>
cd dyktando-mac
brew install xcodegen
make build
open build/Build/Products/Debug/Dyktando.app
```

Requires Xcode 26.5+ and macOS 14+.

## Usage

| Shortcut | Action |
|---|---|
| `F5` (hold) | Push-to-talk dictation |
| `⌃⌥Space` | Toggle dictation |
| `⌃⌥C` (hold) | Comparison mode (4 engines) |
| `⌃⌥M` | Switch active model |
| `⌃⌥,` | Open Settings |

All shortcuts rebindable in **Ustawienia → Skróty**.

### Dictation markers

While dictating, you can say these words to insert punctuation:

| Say | Insert |
|---|---|
| kropka | . |
| przecinek | , |
| znak zapytania | ? |
| wykrzyknik | ! |
| dwukropek | : |
| nowa linia | newline |
| nowy akapit | paragraph break |

## Privacy

100% on-device. Verify with Little Snitch or `lsof` — no network calls during dictation. No analytics, no telemetry, no cloud transcription. Models are downloaded once from Hugging Face / Argmax and cached in `~/Library/Application Support/Dyktando/Models/`.

## Architecture

- **Audio:** `AVAudioEngine` → 16 kHz mono Float32 ring buffer
- **Hotkeys:** [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts)
- **ASR:** [`argmaxinc/WhisperKit`](https://github.com/argmaxinc/WhisperKit) (Whisper) + [`FluidInference/FluidAudio`](https://github.com/FluidInference/FluidAudio) (Parakeet) + Apple `Speech.framework`
- **Text injection:** Accessibility ⌘V via `CGEvent`, with clipboard snapshot/restore
- **Build:** xcodegen → Xcode project → Makefile

See `docs/superpowers/specs/2026-05-20-dyktando-design.md` for full design.

## Build

```bash
make gen          # generate Dyktando.xcodeproj from project.yml
make build        # Debug build
make test         # run all 79 unit tests
make archive      # Release archive
make dmg          # produce Dyktando.dmg (uses create-dmg if installed, else hdiutil)
make clean
```

## License

MIT (TBD — set the LICENSE file).
