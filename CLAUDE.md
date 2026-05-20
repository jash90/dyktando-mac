# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Dyktando — a native macOS menu-bar dictation app (Polish-focused, on-device). Push-to-talk hotkey records audio, runs it through a selectable ASR engine, and pastes the transcription at the cursor. Apple Silicon, macOS 14+. Runs as `LSUIElement` (no Dock icon). v0.1 lives on `feature/implementation`.

## Build / test commands

The Xcode project is **generated** by `xcodegen` from `project.yml` — do not hand-edit `Dyktando.xcodeproj/`, it is in `.gitignore`. Regenerate after any source-file rename, target change, or dependency change.

```bash
make gen          # xcodegen → Dyktando.xcodeproj (must run after adding/removing files)
make build        # Debug build into ./build/
make test         # run the DyktandoTests bundle
make archive      # Release archive (ad-hoc signed)
make dmg          # archive + scripts/make-dmg.sh → build/Dyktando.dmg
make clean        # nuke build/ and the generated xcodeproj
```

Run a single test class/method (after `make gen`):

```bash
xcodebuild test \
  -project Dyktando.xcodeproj -scheme Dyktando \
  -destination 'platform=macOS' -derivedDataPath build \
  -only-testing:DyktandoTests/TranscriptionRouterTests
# Append /testMethodName for a single test.
```

CI (`.github/workflows/ci.yml`) runs `xcodegen generate` → Debug build → tests on `macos-15`. Push to `main`, `master`, or `feature/**` triggers it.

## Architecture — what to read first

End-to-end flow lives in `Dyktando/App/AppDelegate.swift` — start there. It wires every subsystem together:

```
HotkeyMonitor → AudioCapture → (samples + sampleRate) → TranscriptionRouter
                                                              ↓
                                                       TranscriptionEngine
                                                              ↓
                                                     PostprocessPipeline
                                                              ↓
                                                         TextInjector → ⌘V
```

Key boundaries:

- **`Dyktando/Core/Audio/AudioCapture.swift`** — `AVAudioEngine` input tap → `AVAudioConverter` → `AudioRingBuffer` (16 kHz mono Float32, 60 s capacity). **Gotcha (load-bearing):** the converter input-block must return `.noDataNow` after the single buffer it has on hand, **not** `.endOfStream` — returning end-of-stream puts `AVAudioConverter` in a terminal state and every subsequent tap silently produces zero output. See `db02a6f` and the inline comment in `handleTap`.
- **`Dyktando/Core/Hotkeys/HotkeyMonitor.swift`** — wraps `sindresorhus/KeyboardShortcuts`. Emits `HotkeyEvent` (push-to-talk down/up, toggle, comparison mode, switch model, open settings). Shortcut **names** (used by KeyboardShortcuts persistence) and defaults live in `ShortcutNames.swift` — change a name and you orphan user preferences.
- **`Dyktando/Engines/`** — engines conform to `TranscriptionEngine` (`EngineProtocol.swift`). `EngineRegistry` (`@MainActor` singleton) owns one instance per `EngineID`. `TranscriptionRouter.routeAll` fan-outs to every installed engine in parallel via `TaskGroup` for comparison mode; `route` runs one. The four engines:
  - `ParakeetEngine` — FluidAudio's Parakeet TDT v3. Default for PL. Model cache lives under FluidAudio's own dir (`AsrModels.defaultCacheDirectory(for: .v3)`), **not** under `AppPaths.support/Models`.
  - `WhisperKitEngine` — two variants (`largeV3Turbo`, `largeV3`) selected via the `Variant` enum; both share the same class. Model dir is `AppPaths.support/Models/<engineID>/`.
  - `AppleSpeechEngine` — `SFSpeechRecognizer` (pl-PL only). System-provided, always counted as installed once authorized; serves as fallback in `EngineRegistry.active(prefs:)`.
  - Both Whisper and Parakeet have an internal `TranscriptionResult` type — files alias `Dyktando.TranscriptionResult` to `EngineResult` to disambiguate.
- **`Dyktando/Postprocess/PostprocessPipeline.swift`** — `ReplacementRules` (dictation markers: `kropka` → `.`, etc.) → `PunctuationHeuristic` (sentence-end period) → `PolishCapitalizer` → smart-space cleanup. Order matters; everything passes through here before injection.
- **`Dyktando/Core/TextInjection/TextInjector.swift`** — snapshots `NSPasteboard.general`, writes new text, fires `CGEventPaste` (synthesized ⌘V), then restores the snapshot after **60 ms** (`restoreDelay`). Two modes: `accessibilityPaste` (full flow, requires Accessibility permission) and `clipboardOnly` (no ⌘V dispatch). `AppDelegate.currentInjector()` picks based on `PermissionsService.accessibility`.
- **`Dyktando/Persistence/Preferences.swift`** — `@MainActor` `ObservableObject` wrapping `@AppStorage`. SwiftUI `Settings` tabs (`Dyktando/UI/Settings/`) bind directly. Don't add new persistence layers — extend this.
- **`Dyktando/Persistence/LanguageModeCodec.swift`** — encodes/decodes `LanguageMode` (`single` / `multilingualAuto` / `mixed`) to/from a stringly-typed `@AppStorage` value. Keep `encode`/`decode` symmetric and covered by `LanguageModeCodecTests`.

UI is SwiftUI inside `NSWindowController`s for HUD / Settings / Onboarding / Comparison (`Dyktando/UI/`). All UI mutation must happen on `@MainActor`; engine callbacks already hop back via `await MainActor.run { … }` in `AppDelegate`.

## Conventions

- **No new files without `make gen`.** Adding a `.swift` file under `Dyktando/` or `DyktandoTests/` requires re-running `xcodegen generate` (or `make gen`) before it compiles — `project.yml` globs sources by path. If a fresh test class isn't discovered, you forgot this step.
- **Permissions** (`PermissionsService`): microphone (`AVCaptureDevice`), speech recognition (`SFSpeechRecognizer`), Accessibility (`AXIsProcessTrustedWithOptions`). When Accessibility is denied, fall back to `clipboardOnly` injection — never bypass it; that's what the onboarding flow nudges the user to fix.
- **Diagnostic logging**: prefer `NSLog` over `print` in the audio/hotkey paths so output reaches unbuffered stderr (capture for crash reports). See `5cc33e4`. Elsewhere `print` is fine.
- **Concurrency**: engines are `@unchecked Sendable` finals because the underlying libraries (WhisperKit, FluidAudio) hold mutable state but are used single-threaded from one `Task` at a time. Preserve that invariant — don't call `transcribe` concurrently on the same engine instance outside `TranscriptionRouter.routeAll` (which only calls each engine once per fan-out).

## Specs

Full design + implementation plan live in `docs/superpowers/specs/2026-05-20-dyktando-design.md` and `docs/superpowers/plans/2026-05-20-dyktando-implementation.md`. Read these before large architectural changes.
