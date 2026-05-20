# Dyktando — Polish-focused dictation app for macOS

**Status:** Draft for review
**Date:** 2026-05-20
**Owner:** Bartek Zimny
**Target platform:** macOS 14+ on Apple Silicon (M1 and later)

---

## 1. Overview

Dyktando is a native macOS menu-bar app that gives Polish-speaking users Wispr-Flow-style global dictation with the freedom to pick and compare on-device speech-recognition engines. Users press a global hotkey, speak, and the transcription is pasted into whatever window has focus. Multiple models are downloadable side-by-side; a comparison mode runs the same recording through all enabled engines and lets the user select the best output.

### 1.1 Goals

- **System-wide dictation** in any focused application (native, Electron, Terminal, browser textareas).
- **Polish as a first-class language**, with auto-capitalization and sentence-end punctuation correction tuned for PL.
- **Four selectable engines** so the user can hear, in their own voice, which model is most accurate and which feels snappiest.
- **Comparison mode** to run one recording through all engines side-by-side and capture the user's preferred output for both insertion and aggregated stats.
- **Global hotkeys** with both push-to-talk and toggle semantics, fully rebindable.
- **Fully on-device** — no audio leaves the Mac.

### 1.2 Non-goals

- Cross-platform (Windows/Linux). Apple Silicon macOS only.
- Mac App Store distribution. Accessibility entitlement is incompatible with the App Sandbox.
- Real-time streaming transcription with token-by-token display. End-of-utterance batch result only.
- Speaker diarization, meeting transcription, file-based batch transcription. Strictly live dictation.
- Custom voice training or fine-tuning. Stock models only.

### 1.3 Success criteria

- End-to-end latency (release hotkey → text appears) under **400 ms median** for Parakeet TDT v3 on M2.
- Polish WER (read prompts, quiet room) within **1.5 pp** of the upstream model's reported WER for each engine.
- Cold-start to "ready to dictate" under **3 s** after launch.
- Zero network traffic during normal dictation (verifiable with Little Snitch).
- App fits in **< 200 MB** binary; model weights downloaded separately on demand.

---

## 2. Architecture

### 2.1 Process model

Single AppKit/SwiftUI process running as `LSUIElement` (menu-bar only, no Dock icon). Three internal subsystems run on dedicated dispatch queues:

| Subsystem | Queue | Responsibility |
|---|---|---|
| **HotkeyMonitor** | main | Listens for `KeyboardShortcuts` callbacks, manages PTT/toggle state machine |
| **AudioCapture** | `audio.capture` (QoS userInteractive) | `AVAudioEngine` tap, 16 kHz mono Float32, ring buffer |
| **TranscriptionRouter** | `transcription.route` (QoS userInitiated) | Dispatches buffer to selected engine(s), aggregates results |
| **TextInjector** | main | Clipboard save/restore + synthesized `⌘V` |

### 2.2 Module layout

```
DyktandoApp/
├── App/                       # AppDelegate, MenuBarController, lifecycle
├── Core/
│   ├── Audio/                 # AVAudioEngine wrapper, ring buffer, RMS meter
│   ├── Hotkeys/               # KeyboardShortcuts integration, PTT/toggle state
│   ├── Permissions/           # Mic + Accessibility checks, onboarding prompts
│   └── TextInjection/         # CGEvent paste, clipboard preservation
├── Engines/
│   ├── EngineProtocol.swift   # transcribe(buffer:) async -> Result
│   ├── WhisperKitEngine.swift # Wraps WhisperKit, exposes large-v3 / large-v3-turbo
│   ├── ParakeetEngine.swift   # FluidAudio bindings for Parakeet TDT v3
│   ├── AppleSpeechEngine.swift# SFSpeechRecognizer (pl-PL)
│   └── ModelRegistry.swift    # Available models, download state, disk paths
├── Postprocess/
│   ├── PolishCapitalizer.swift
│   ├── PunctuationHeuristic.swift
│   └── ReplacementRules.swift # "kropka" → "." etc.
├── UI/
│   ├── HUD/                   # Floating pill window (NSPanel, .floating level)
│   ├── Settings/              # 5-tab settings window
│   └── Comparison/            # Side-by-side comparison sheet
└── Persistence/
    ├── Preferences.swift      # @AppStorage wrappers
    └── ComparisonStats.swift  # JSON in Application Support
```

### 2.3 Data flow — single-engine dictation

```
Hotkey press
   └─► HotkeyMonitor.startCapture()
        └─► AudioCapture.start() ─► ring buffer (16 kHz mono)
              [user speaks]
Hotkey release (PTT) / second tap (toggle)
   └─► AudioCapture.stop() ─► finalized PCM buffer
        └─► TranscriptionRouter.route(buffer, engine: selected)
              └─► Engine.transcribe(buffer) async ─► raw text
                   └─► Postprocess pipeline ─► final text
                        └─► TextInjector.insert(text)
```

### 2.4 Data flow — comparison mode

```
Comparison hotkey (⌃⌥C) press → release
   └─► AudioCapture captures one utterance
        └─► TranscriptionRouter.routeAll(buffer)
              ├─► Parakeet.transcribe(buffer)     ┐
              ├─► WhisperKit.turbo.transcribe()   ├─ parallel (TaskGroup)
              ├─► WhisperKit.v3.transcribe()     │
              └─► AppleSpeech.transcribe()        ┘
                   ↓ all complete
              ComparisonWindow.show(results: [(engine, text, ms)])
                   ↓ user clicks one
              TextInjector.insert(chosen)
              ComparisonStats.record(chosen.engine)
```

---

## 3. Engine layer

### 3.1 Engines and models

| ID | Engine class | Framework | Model size on disk | Inference target | Notes |
|---|---|---|---|---|---|
| `parakeet-tdt-v3` | `ParakeetEngine` | FluidAudio (Swift) / parakeet-mlx | ~600 MB | Apple Neural Engine | Default. 25 EU languages incl. PL. Built-in VAD. |
| `whisper-large-v3-turbo` | `WhisperKitEngine` | WhisperKit (CoreML + MLX) | ~1.5 GB | ANE + GPU | 5–8× faster than v3, ≈ same WER. |
| `whisper-large-v3` | `WhisperKitEngine` | WhisperKit | ~3 GB | ANE + GPU | Max accuracy fallback. |
| `apple-speech-pl` | `AppleSpeechEngine` | `Speech.framework` | 0 (system) | system | Zero-download baseline. May require user to enable "Enhanced Dictation" in System Settings. |

### 3.2 EngineProtocol

```swift
protocol TranscriptionEngine {
    var id: EngineID { get }
    var displayName: String { get }
    var supportedLanguages: Set<Locale> { get }
    var isInstalled: Bool { get }

    func install(progress: @escaping (Double) -> Void) async throws
    func uninstall() throws

    func transcribe(
        buffer: AVAudioPCMBuffer,
        language: Locale
    ) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let language: Locale
    let inferenceMillis: Int
    let confidence: Double?       // nil if engine doesn't report
}
```

### 3.3 Model installation

- All engines except Apple Speech have a `ModelDownloader` that streams HF weights to `~/Library/Application Support/Dyktando/Models/<engineID>/`.
- Downloads resume on restart (HTTP `Range` headers).
- Sha256 verified against bundled manifest before activation.
- Concurrent downloads allowed (e.g., user can grab Parakeet and Whisper turbo at once).

---

## 4. Audio pipeline

- `AVAudioEngine` input node, format converted to **16 kHz, mono, Float32** via `AVAudioConverter`.
- Ring buffer sized for 60 seconds max utterance.
- VAD:
  - **Parakeet:** none required (model has silence-aware training).
  - **WhisperKit + Apple Speech:** lightweight WebRTC VAD wrapper (Swift port) to trim leading/trailing silence and detect early termination in toggle mode.
- Live RMS level published to `@Published var inputLevel: Float` for HUD meter.

---

## 5. Hotkeys and triggers

### 5.1 Defaults

| Action | Default shortcut | Mode |
|---|---|---|
| Push-to-talk dictation | `F5` (Fn) | Hold |
| Toggle dictation | `⌃⌥Space` | Tap to start, tap to stop |
| Switch active model | `⌃⌥M` | Cycle |
| Comparison mode | `⌃⌥C` | Hold (records while held) |
| Open Settings | `⌃⌥,` | One-shot |

### 5.2 Implementation

- [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) Swift Package.
- Each shortcut bound to a `KeyboardShortcuts.Name` constant.
- Push-to-talk semantics implemented via `.onKeyDown` / `.onKeyUp` handlers on the same `Name`.
- All shortcuts rebindable in Settings → Shortcuts tab (the library ships a recorder view).

---

## 6. Text injection

### 6.1 Strategy: Accessibility-driven paste

```
1. Read NSPasteboard.general into a snapshot (all types).
2. Write the transcription as a single .string item to NSPasteboard.
3. Synthesize ⌘V via CGEventCreateKeyboardEvent (keyDown + keyUp).
4. Wait 60 ms.
5. Restore the original pasteboard snapshot.
```

### 6.2 Permissions

- Requires **Accessibility** permission (granted per-app in System Settings → Privacy & Security → Accessibility).
- Onboarding includes a screen that opens System Settings to the exact pane with `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

### 6.3 Fallback

- If Accessibility is denied or revoked, app degrades to **clipboard-only mode**: transcription is placed on the pasteboard and the HUD shows "Copied — press ⌘V to paste". A persistent banner in the menu offers a one-click jump to enable Accessibility.

---

## 7. HUD

A small floating pill near the user's cursor:

```
States:
┌──────────────────┐
│  ●  idle (hidden)│
├──────────────────┤
│  ▮▮▮ listening… │  ← waveform from inputLevel
├──────────────────┤
│  ⏳ transkrybuję │
├──────────────────┤
│  ✓ "tekst..."    │  ← 800 ms preview, then hide
└──────────────────┘
```

- `NSPanel` with `.floating` level, `.canJoinAllSpaces`, click-through.
- Anchors near the active text caret if discoverable via Accessibility, otherwise near cursor.
- Toggleable in Settings → General.

---

## 8. Comparison mode

### 8.1 UX

1. User triggers `⌃⌥C` (hold-to-record) or activates "Compare" from the menu.
2. One audio capture is dispatched to **every installed and enabled** engine in parallel via `withTaskGroup`.
3. Results arrive incrementally; window shows each row as it completes with inference time.
4. Each row has a "Use this" button → text is injected at cursor.
5. The pick is recorded to `ComparisonStats`.

### 8.2 Stats and nudges

- After every comparison, the app stores `(timestamp, language, chosenEngineID, alternatives)`.
- After **10 comparisons in the same language**, if one engine wins **≥ 70 %** of picks, the app surfaces a non-modal banner: "Wybrałeś Parakeet 8/10 razy dla polskiego — ustawić jako domyślny?" with Set / Dismiss buttons.
- Stats viewable in Settings → Models (lifetime win counts per language).

---

## 9. Settings UI

Single window, segmented tabs:

| Tab | Contents |
|---|---|
| **Ogólne** | Launch at login, HUD on/off, menu-bar icon style, sound on start/stop |
| **Modele** | Per-engine: installed?, size, install/uninstall button, lifetime comparison win count. Toggle "include in comparison mode". |
| **Język** | Default language (PL), **Language mode** (Single / Multilingual auto-detect / **Mixed PL+EN code-switching**), list of additionally enabled languages |
| **Skróty** | The 5 default shortcuts, all rebindable, "Reset to defaults" button |
| **Audio** | Input device picker, live level meter, sample rate (read-only 16 kHz) |

---

## 10. Polish post-processing

Pipeline runs **after** engine output, **before** injection:

1. **Trim** leading/trailing whitespace.
2. **Capitalize** first character of each sentence (regex on `. ! ?` boundaries; respect existing capitals).
3. **Punctuation heuristic for Parakeet output** (Whisper already emits punctuation):
   - If output has no `. ! ?` and length > 6 words → append `.`.
   - Capitalize first character.
4. **Replacement rules** (user-editable list of pairs):
   - `"kropka"` → `"."`
   - `"przecinek"` → `","`
   - `"znak zapytania"` → `"?"`
   - `"nowa linia"` → `"\n"`
   - `"nowy akapit"` → `"\n\n"`
5. **Smart spacing** around punctuation (no space before `.`, single space after).

Rules are pure Swift functions, unit-tested with a corpus of ~50 Polish examples.

---

## 11. Permissions and onboarding

Sequential first-run flow:

1. **Welcome screen** — short description, "Continue".
2. **Microphone** — triggers `AVAudioApplication.requestRecordPermission`. Cannot continue without grant.
3. **Accessibility** — opens System Settings, polls `AXIsProcessTrusted()` every 500 ms, shows "Continue" once granted. Skippable with warning (degrades to clipboard mode).
4. **Pick first model** — list of 4 engines with size + recommendation. User downloads at least one (Apple Speech selectable as zero-MB option to skip).
5. **Test shortcut** — user holds `F5`, the onboarding screen shows the live waveform, then the transcription appears in a textbox on the same screen. Confirms the end-to-end loop before turning the app loose system-wide.

---

## 12. Distribution

- **Local DMG** built via `create-dmg`.
- **Ad-hoc signed** for personal use (no Apple Developer cert required initially).
- If shared more broadly later: Developer ID + notarization. Out of scope for MVP.
- Auto-update via [Sparkle](https://sparkle-project.org) — deferred to v0.2.

---

## 13. Testing strategy

| Layer | Tooling | Coverage |
|---|---|---|
| Pure logic (post-processing, model registry, stats) | XCTest | Unit tests with golden Polish corpus |
| Engine adapters | XCTest with bundled 3 s PL test clip | One transcription per engine, asserts non-empty + plausible content |
| Audio pipeline | XCTest with synthetic sine + silence buffers | Asserts ring buffer, VAD trim, level metering |
| Hotkeys | Manual via UI test on a CI runner with `KeyboardShortcuts` test helpers | PTT down/up, toggle, comparison |
| End-to-end | Manual checklist | Cold start → grant perms → dictate → text appears in TextEdit / Safari address bar / Terminal |

CI: GitHub Actions on `macos-14` runner. Unit + engine-adapter tests on every push.

---

## 14. Multilingual and code-switching

A common Polish dictation pattern is mid-sentence English: *"Trzeba zrobić deployment na production przed pull requestem"*. The app must handle this without splitting the recording or dropping the English terms.

### 14.1 Three language modes (Settings → Język)

| Mode | Behavior | Best engine |
|---|---|---|
| **Single language** | Force `language=pl` (or whatever default). English words get transcribed phonetically into Polish. Fastest, most accurate when speech is monolingual. | Parakeet, Whisper, Apple Speech |
| **Multilingual auto-detect** | Engine detects language per utterance. If you speak Polish, you get Polish. If you switch to English between utterances, the next utterance comes out English. No intra-utterance switching. | Parakeet (built-in auto-detect), Whisper (`language=None`) |
| **Mixed PL+EN (code-switching)** ★ | Engine left to figure out language per word. Best-effort intra-utterance switching. | **Whisper large-v3** — strongest code-switcher; Parakeet falls back to dominant-language detection |

★ Default mode for Polish users. Code-switching support is the explicit reason we keep Whisper large-v3 in the model lineup despite its higher latency.

### 14.2 Per-engine code-switching behavior

| Engine | Intra-utterance PL+EN | Notes |
|---|---|---|
| Whisper large-v3 | **Best** — preserves English terms in roman script with their English spelling, treats Polish words natively. Tends to lock onto dominant language for short clips. | Pass `language=None`, omit the language prompt. |
| Whisper large-v3-turbo | Good, slightly less robust than v3 on mixed audio | Same flag. |
| Parakeet TDT v3 | **Limited** — auto-detects one language per utterance from Granary training. Mid-utterance English usually transcribed but biased to the dominant language. | No code-switch flag; rely on the model's natural multilingual behavior. |
| Apple Speech (pl-PL) | **None** — locale is set at session start. English words become Polish phonetic approximations. | Excluded from Mixed mode. |

### 14.3 Implementation

- `LanguageMode` enum: `.single(Locale)`, `.multilingualAuto(Set<Locale>)`, `.mixed(primary: Locale, allowed: Set<Locale>)`.
- The router passes the mode to each engine's `transcribe(buffer:language:)`. Engines translate it into their native API:
  - WhisperKit: `decodingOptions.language = mode == .single ? code : nil`
  - Parakeet: no flag; mode informs only the post-processing.
- **Post-processing rule for Mixed mode:** disable the Polish-only replacement rules (`"kropka" → "."`) for tokens that look English (ASCII-only, found in a small bundled English word list of ~5k common terms). Prevents `"merge request kropka"` becoming `"merge request."` only if "kropka" was clearly the Polish punctuation marker — not part of an English code term.
- **Comparison mode + Mixed:** comparison mode forces every engine into its Mixed-equivalent mode so the user can see directly which engine handles their personal code-switching pattern best. This is a primary use case for the comparison feature.

### 14.4 Test coverage

Golden corpus includes 15 PL+EN code-switch samples (technical, business, conversational). Each engine adapter runs them in CI and asserts:

- Polish words are in Polish (UTF-8, diacritics preserved).
- Common English tech terms (`deployment`, `pull request`, `stack overflow`, `commit`, `merge`, `backend`) appear in English spelling.
- Punctuation isn't doubled or dropped at language boundaries.

## 15. Open questions

- **Streaming inference for Parakeet?** Out of scope for MVP, but FluidAudio supports streaming — worth a v0.2 spike if latency feels lacking.
- **Vocabulary boosting / custom prompts?** Skipping for MVP; Whisper has `initial_prompt` we could expose later for domain terms (medical, legal Polish).
- **Privacy of comparison stats?** Stored locally only; no telemetry. Confirm export/clear button location in Settings → Modele.

---

## 16. Out of scope (explicit)

- Real-time streaming transcript display
- Cloud models (OpenAI Whisper API, Deepgram, etc.)
- File transcription, meeting recorder, batch jobs
- iOS / iPadOS companion
- Windows / Linux
- Mac App Store
- Custom voice training / fine-tuning
- Speaker diarization
- Other Polish-specific models (Bielik-ASR if it materializes — revisit in v0.2)
