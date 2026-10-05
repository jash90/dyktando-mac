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
make install      # archive → re-sign with Developer ID (+ entitlements) → /Applications → launch
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

- **`Dyktando/Core/Audio/AudioCapture.swift`** — `AVAudioEngine` input tap → `AVAudioConverter` → `AudioRingBuffer` (16 kHz mono Float32, 60 s capacity). **Gotcha (load-bearing):** the converter input-block must return `.noDataNow` after the single buffer it has on hand, **not** `.endOfStream` — returning end-of-stream puts `AVAudioConverter` in a terminal state and every subsequent tap silently produces zero output. See `db02a6f` and the inline comment in `handleTap`. **Input device:** a fresh `AVAudioEngine` is created on every `start()` (one long-lived engine stays pinned to whatever was the default input at launch), and the device chosen in Settings → Audio (`inputDeviceUID`, Core Audio UID via `AudioDevices.swift`) is set with `kAudioOutputUnitProperty_CurrentDevice` before the tap; unplugged/unknown UID → system default.
- **`Dyktando/Core/Hotkeys/HotkeyMonitor.swift`** — wraps `sindresorhus/KeyboardShortcuts`. Emits `HotkeyEvent` (push-to-talk down/up, toggle, comparison mode, switch model, open settings). Shortcut **names** (used by KeyboardShortcuts persistence) and defaults live in `ShortcutNames.swift` — change a name and you orphan user preferences. Modifier-only push-to-talk (right ⌘/⌥/⇧/⌃, fn) is **not** possible in KeyboardShortcuts — it lives in `ModifierKeyMonitor.swift` (NSEvent global+local `.flagsChanged`/`.keyDown` monitors, device-dependent masks to tell right from left; needs Accessibility). Pure logic in `ModifierPTTState` (tested): any other key/modifier while held → `.cancelCapture`, and `AppDelegate` discards that recording. Setting: `@AppStorage("modifierPushToTalk")`.
- **`Dyktando/Engines/`** — engines conform to `TranscriptionEngine` (`EngineProtocol.swift`). `EngineRegistry` (`@MainActor` singleton) owns one instance per `EngineID`; `active(prefs:)` returns the engine chosen in Settings → Models (`Preferences.defaultEngineID`) if installed, else Parakeet (`EngineRegistry.resolve`). Engines (v0.2):
  - `ParakeetEngine` — FluidAudio's Parakeet TDT v3, native CoreML. Default. Model cache lives under FluidAudio's own dir (`AsrModels.defaultCacheDirectory(for: .v3)`).
  - `MLXSidecarEngine` — Canary-1b-v2, Whisper large-v3-turbo, Whisper large-v3 (one class, `Variant` statics). They run in a local **Python MLX sidecar** (`sidecar/stt_server.py`, 127.0.0.1:7863) managed by the `MLXSidecar` actor: on first install the bundled `stt_server.py` + `pyproject.toml` + `uv.lock` are copied to `AppPaths.support/sidecar/src` and `uv sync` builds `AppPaths.support/sidecar/venv` (needs `uv`, looked up in Homebrew/`~/.local/bin`). The server starts on demand, all MLX work runs on one thread, it's terminated in `applicationWillTerminate`. Installed-ness = `installed-<model>` marker + venv. WhisperKit was dropped in `48f6d02` (prewarm hangs on ANE) — don't bring it back; Canary has no Swift implementation (FluidAudio 0.14 has none).
  - Sidecar resources are listed file-by-file in `project.yml` (never the `sidecar/` folder — a dev `.venv` there would be bundled). After changing Python deps: `cd sidecar && uv lock`, the app re-syncs when the bundled `uv.lock` differs.
  - Opt-in integration test installing all MLX models through app code: `TEST_RUNNER_DYKTANDO_MLX_INSTALL=1 make test`.
  - Engine files alias `Dyktando.TranscriptionResult` to `EngineResult` to disambiguate from library types.
- **`Dyktando/Postprocess/PostprocessPipeline.swift`** — `ReplacementRules` (dictation markers: `kropka` → `.`, etc.) → `PunctuationHeuristic` (sentence-end period) → `PolishCapitalizer` → smart-space cleanup. Order matters; everything passes through here before injection.
- **`Dyktando/Core/TextInjection/TextInjector.swift`** — snapshots `NSPasteboard.general`, writes new text, fires `CGEventPaste` (synthesized ⌘V), then restores the snapshot after **60 ms** (`restoreDelay`). Two modes: `accessibilityPaste` (full flow, requires Accessibility permission) and `clipboardOnly` (no ⌘V dispatch). `AppDelegate.pasteDecision()` picks: no Accessibility → `clipboardOnly` (+ one system prompt per launch); otherwise `FocusInspector` asks the frontmost app (AX, 0.25 s timeout, sets `AXManualAccessibility` for Electron) what is focused and `FocusClassifier` maps it to editable / notEditable / unknown — only **notEditable** (buttons, lists, Finder, no focus) skips ⌘V; unknown (e.g. Word returns -25204) still pastes so nothing regresses.
- **`Dyktando/Persistence/Preferences.swift`** — `@MainActor` `ObservableObject` wrapping `@AppStorage`. SwiftUI `Settings` tabs (`Dyktando/UI/Settings/`) bind directly. Don't add new persistence layers — extend this.
- **`Dyktando/Persistence/LanguageModeCodec.swift`** — encodes/decodes `LanguageMode` (`single` / `multilingualAuto` / `mixed`) to/from a stringly-typed `@AppStorage` value. Keep `encode`/`decode` symmetric and covered by `LanguageModeCodecTests`.

UI is SwiftUI inside `NSWindowController`s for HUD / Settings / Onboarding / Comparison (`Dyktando/UI/`). All UI mutation must happen on `@MainActor`; engine callbacks already hop back via `await MainActor.run { … }` in `AppDelegate`.

## Conventions

- **No new files without `make gen`.** Adding a `.swift` file under `Dyktando/` or `DyktandoTests/` requires re-running `xcodegen generate` (or `make gen`) before it compiles — `project.yml` globs sources by path. If a fresh test class isn't discovered, you forgot this step.
- **Permissions** (`PermissionsService`): microphone (`AVCaptureDevice`), speech recognition (`SFSpeechRecognizer`), Accessibility (`AXIsProcessTrustedWithOptions`). When Accessibility is denied, fall back to `clipboardOnly` injection — never bypass it; that's what the onboarding flow nudges the user to fix.
- **Signing & entitlements (load-bearing):** hardened runtime is on, so the app MUST carry `com.apple.security.device.audio-input` (`Dyktando/Dyktando.entitlements`) — without it macOS returns **all-zero audio without ever prompting** (regression in 0.2.0–0.2.2; guarded by `AudioDiagnosticsTests.test_app_isEntitledForMicrophone`, and the app shows `AudioDiagnostics.digitalSilenceMessage` for all-zero recordings). Install with `make install`, which signs with the Developer ID identity: ad-hoc signatures change every build, so TCC (Microphone, Accessibility) forgets the app after each update.
- **Diagnostic logging**: prefer `NSLog` over `print` in the audio/hotkey paths so output reaches unbuffered stderr (capture for crash reports). See `5cc33e4`. Elsewhere `print` is fine.
- **Concurrency**: engines are `@unchecked Sendable` finals because the underlying libraries (FluidAudio, the sidecar connection) hold mutable state but are used single-threaded from one `Task` at a time. Preserve that invariant — don't call `transcribe` concurrently on the same engine instance outside `TranscriptionRouter.routeAll` (which only calls each engine once per fan-out).

## Specs

Full design + implementation plan live in `docs/superpowers/specs/2026-05-20-dyktando-design.md` and `docs/superpowers/plans/2026-05-20-dyktando-implementation.md`. Read these before large architectural changes.
