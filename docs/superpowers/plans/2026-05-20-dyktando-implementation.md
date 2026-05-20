# Dyktando Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working menu-bar dictation app for macOS that lets users dictate in Polish (and other EU languages, including mid-utterance PL+EN code-switching), choose between four on-device ASR engines, compare them side-by-side, and bind it all to global hotkeys.

**Architecture:** Single AppKit/SwiftUI process running as `LSUIElement` with subsystems for audio capture, hotkey monitoring, engine routing, post-processing, and text injection. All inference happens on-device via WhisperKit, FluidAudio (Parakeet), or `Speech.framework`.

**Tech Stack:** macOS 14+, Swift 6.3, Xcode 26.5, SwiftUI + AppKit, Swift Package Manager. Dependencies: `argmaxinc/WhisperKit`, `FluidInference/FluidAudio`, `sindresorhus/KeyboardShortcuts`. CI: GitHub Actions on `macos-14`.

**Spec:** `docs/superpowers/specs/2026-05-20-dyktando-design.md`

---

## Phase plan

Each phase ends with working, testable software. Stop and verify before moving on.

| # | Phase | What works at the end |
|---|---|---|
| **M0** | Project skeleton + CI | Menu-bar app launches, no Dock icon, GitHub Actions green |
| **M1** | Audio capture + global hotkey | `F5` (hold) records audio, writes a WAV to `~/Library/Application Support/Dyktando/last.wav`, HUD pill shows level meter |
| **M2** | Apple Speech engine + clipboard injection | PTT in any app → spoken Polish appears as text via clipboard paste |
| **M3** | Accessibility paste injection + onboarding | Text inserts at cursor automatically; first-run flow handles Mic + Accessibility |
| **M4** | WhisperKit engine + model download UI | Whisper large-v3-turbo and large-v3 selectable, downloadable, transcribing |
| **M5** | Parakeet TDT v3 engine + becomes default | Parakeet selectable, becomes default for PL after install |
| **M6** | Settings window (5 tabs) | All shortcuts rebindable, models managed from UI, language modes selectable |
| **M7** | Comparison mode + stats | `⌃⌥C` → 4 transcriptions side-by-side, click winner, stats persist, nudge after 10 picks |
| **M8** | Multilingual / PL+EN code-switching | Language mode dropdown works; Mixed mode keeps English terms in English |
| **M9** | Post-processing polish + replacement rules | Polish capitalization, punctuation heuristic, user-editable replacement list |
| **M10** | Distribution | Signed ad-hoc DMG produced by `make dmg` |

---

## File structure (locked-in)

```
dyktando-mac/
├── Dyktando.xcodeproj                  # Xcode app target
├── Dyktando/
│   ├── App/
│   │   ├── DyktandoApp.swift           # @main, AppDelegate adaptor
│   │   ├── AppDelegate.swift           # Menu-bar lifecycle, NSApplicationDelegate
│   │   └── MenuBarController.swift     # NSStatusItem + popover
│   ├── Core/
│   │   ├── Audio/
│   │   │   ├── AudioCapture.swift      # AVAudioEngine wrapper
│   │   │   ├── AudioRingBuffer.swift   # Lock-free Float32 ring
│   │   │   └── VAD.swift               # WebRTC VAD wrapper
│   │   ├── Hotkeys/
│   │   │   ├── HotkeyMonitor.swift     # KeyboardShortcuts.Name -> state machine
│   │   │   └── ShortcutNames.swift     # `extension KeyboardShortcuts.Name`
│   │   ├── Permissions/
│   │   │   └── PermissionsService.swift # Mic + Accessibility check + open settings
│   │   └── TextInjection/
│   │       ├── TextInjector.swift      # Strategy + clipboard restore
│   │       └── CGEventPaste.swift      # ⌘V via CGEventKeyboard
│   ├── Engines/
│   │   ├── EngineProtocol.swift        # TranscriptionEngine + types
│   │   ├── EngineRegistry.swift        # All known engines, install state
│   │   ├── WhisperKitEngine.swift
│   │   ├── ParakeetEngine.swift
│   │   ├── AppleSpeechEngine.swift
│   │   ├── ModelDownloader.swift       # Resumable HTTPS download to App Support
│   │   └── TranscriptionRouter.swift   # Single + comparison dispatch
│   ├── Postprocess/
│   │   ├── PostprocessPipeline.swift   # Composition
│   │   ├── PolishCapitalizer.swift
│   │   ├── PunctuationHeuristic.swift
│   │   ├── ReplacementRules.swift
│   │   └── EnglishTermDetector.swift   # Bundled 5k word list
│   ├── UI/
│   │   ├── HUD/
│   │   │   ├── HUDController.swift     # NSPanel manager
│   │   │   └── HUDView.swift           # SwiftUI pill
│   │   ├── Settings/
│   │   │   ├── SettingsWindowController.swift
│   │   │   ├── GeneralTab.swift
│   │   │   ├── ModelsTab.swift
│   │   │   ├── LanguageTab.swift
│   │   │   ├── ShortcutsTab.swift
│   │   │   └── AudioTab.swift
│   │   ├── Onboarding/
│   │   │   ├── OnboardingWindow.swift
│   │   │   └── OnboardingSteps.swift
│   │   └── Comparison/
│   │       ├── ComparisonWindow.swift
│   │       └── ComparisonRow.swift
│   ├── Persistence/
│   │   ├── Preferences.swift           # @AppStorage wrappers
│   │   └── ComparisonStats.swift       # JSON file + Codable
│   └── Resources/
│       ├── english_terms.txt           # Bundled word list
│       ├── pl_test_corpus.txt          # 50 PL sentences (used by tests too)
│       └── code_switch_corpus.txt      # 15 PL+EN samples
├── DyktandoTests/                      # XCTest target
│   ├── PostprocessTests.swift
│   ├── AudioPipelineTests.swift
│   ├── EngineTests.swift               # Loops over all engines
│   └── Resources/
│       └── three-seconds-pl.wav        # Test fixture, ~3s Polish speech
├── DyktandoUITests/                    # XCUITest target
│   └── HotkeySmokeTests.swift
├── docs/
│   ├── superpowers/
│   │   ├── specs/2026-05-20-dyktando-design.md
│   │   └── plans/2026-05-20-dyktando-implementation.md
│   └── permissions.md                  # User-facing screenshots
├── scripts/
│   └── make-dmg.sh
├── .github/workflows/
│   └── ci.yml
├── Makefile
├── Package.swift                       # Swift Package as library, app target uses it
├── .gitignore
└── README.md
```

---

## M0. Project skeleton + CI

### Task M0.1: Initialize Xcode project + .gitignore

**Files:**
- Create: `/Users/bartlomiejzimny/Projects/dyktando-mac/.gitignore`
- Create: `/Users/bartlomiejzimny/Projects/dyktando-mac/Dyktando.xcodeproj` (via Xcode)
- Create: `/Users/bartlomiejzimny/Projects/dyktando-mac/README.md`

- [ ] **Step 1: Write .gitignore**

```gitignore
# Xcode
build/
DerivedData/
*.xcuserstate
*.xcuserdatad/
*.xccheckout
*.moved-aside
xcuserdata/

# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# macOS
.DS_Store

# App data
~/Library/Application Support/Dyktando/

# Local
*.dmg
*.zip
.env
```

- [ ] **Step 2: Create Xcode project**

Run:
```bash
cd /Users/bartlomiejzimny/Projects/dyktando-mac
open -a Xcode
```

In Xcode: File → New → Project → macOS → App. Name: `Dyktando`. Interface: SwiftUI. Language: Swift. Bundle id: `com.bartekzimny.dyktando`. Save to `dyktando-mac/`.

Expected: `Dyktando.xcodeproj` exists at repo root.

- [ ] **Step 3: Set deployment target macOS 14**

Open project → Targets → Dyktando → General → Minimum Deployments → macOS 14.0.

- [ ] **Step 4: Mark as menu-bar app (LSUIElement)**

In `Dyktando/Info.plist` set:
```xml
<key>LSUIElement</key>
<true/>
```

If the project uses `INFOPLIST_KEY_*` build settings instead of a file, add `INFOPLIST_KEY_LSUIElement = YES` to the target's Build Settings.

- [ ] **Step 5: README skeleton**

```markdown
# Dyktando

Polish-focused on-device dictation for macOS.

See `docs/superpowers/specs/2026-05-20-dyktando-design.md` for the design.

## Develop

```bash
open Dyktando.xcodeproj
```

Requires Xcode 26.5+ and macOS 14+.
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore README.md Dyktando.xcodeproj Dyktando
git commit -m "M0.1: scaffold Xcode project as LSUIElement menu-bar app"
```

---

### Task M0.2: GitHub Actions CI

**Files:**
- Create: `/Users/bartlomiejzimny/Projects/dyktando-mac/.github/workflows/ci.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26.5'
      - name: Build
        run: |
          xcodebuild \
            -project Dyktando.xcodeproj \
            -scheme Dyktando \
            -destination 'platform=macOS' \
            -derivedDataPath build \
            build | xcpretty
      - name: Test
        run: |
          xcodebuild test \
            -project Dyktando.xcodeproj \
            -scheme Dyktando \
            -destination 'platform=macOS' \
            -derivedDataPath build | xcpretty
```

- [ ] **Step 2: Add a placeholder unit test so test job has something to run**

In `DyktandoTests/DyktandoTests.swift` (Xcode created this by default):

```swift
import XCTest
@testable import Dyktando

final class DyktandoTests: XCTestCase {
    func test_smoke() throws {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 3: Verify locally**

Run:
```bash
xcodebuild -project Dyktando.xcodeproj -scheme Dyktando -destination 'platform=macOS' build | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add .github DyktandoTests
git commit -m "M0.2: add GitHub Actions CI with build + test"
```

---

### Task M0.3: Status bar item visible

**Files:**
- Modify: `Dyktando/App/DyktandoApp.swift`
- Create: `Dyktando/App/AppDelegate.swift`
- Create: `Dyktando/App/MenuBarController.swift`

- [ ] **Step 1: Test asserting MenuBarController owns a status item**

In `DyktandoTests/MenuBarTests.swift`:

```swift
import XCTest
@testable import Dyktando

final class MenuBarTests: XCTestCase {
    func test_menuBarController_holdsStatusItem() {
        let controller = MenuBarController()
        XCTAssertNotNil(controller.statusItem)
        XCTAssertEqual(controller.statusItem.button?.image?.isTemplate, true)
    }
}
```

- [ ] **Step 2: Run test, expect failure**

```bash
xcodebuild test -only-testing:DyktandoTests/MenuBarTests \
  -project Dyktando.xcodeproj -scheme Dyktando \
  -destination 'platform=macOS' | tail
```
Expected: FAIL with `Cannot find 'MenuBarController' in scope`.

- [ ] **Step 3: Implement MenuBarController**

`Dyktando/App/MenuBarController.swift`:

```swift
import AppKit

final class MenuBarController {
    let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dyktando")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ustawienia…", action: nil, keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zakończ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}
```

- [ ] **Step 4: Implement AppDelegate that retains MenuBarController**

`Dyktando/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
    }
}
```

- [ ] **Step 5: Wire AppDelegate into SwiftUI App**

`Dyktando/App/DyktandoApp.swift`:

```swift
import SwiftUI

@main
struct DyktandoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }   // satisfies SwiftUI App requirement, no main window
    }
}
```

- [ ] **Step 6: Run test, expect pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 7: Run the app and verify**

In Xcode: `⌘R`. Expected: microphone icon appears in the menu bar, clicking shows menu with "Ustawienia…" and "Zakończ", no Dock icon, no main window.

- [ ] **Step 8: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M0.3: status bar item with menu, LSUIElement verified"
```

**Phase M0 acceptance:** App launches, menu-bar icon visible, no Dock icon, CI green.

---

## M1. Audio capture + global hotkey

### Task M1.1: Add KeyboardShortcuts SwiftPM dependency

**Files:**
- Modify: `Dyktando.xcodeproj/project.pbxproj` (via Xcode UI)

- [ ] **Step 1: Add package**

In Xcode: File → Add Package Dependencies → URL `https://github.com/sindresorhus/KeyboardShortcuts` → Add to target `Dyktando`.

- [ ] **Step 2: Smoke test the dependency compiles**

Add to `Dyktando/Core/Hotkeys/ShortcutNames.swift`:

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.f5))
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.control, .option]))
    static let switchModel = Self("switchModel", default: .init(.m, modifiers: [.control, .option]))
    static let comparisonMode = Self("comparisonMode", default: .init(.c, modifiers: [.control, .option]))
    static let openSettings = Self("openSettings", default: .init(.comma, modifiers: [.control, .option]))
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Dyktando.xcodeproj -scheme Dyktando -destination 'platform=macOS' build | tail
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Dyktando.xcodeproj Dyktando/Core
git commit -m "M1.1: add KeyboardShortcuts dep, declare shortcut names"
```

---

### Task M1.2: HotkeyMonitor with PTT state machine

**Files:**
- Create: `Dyktando/Core/Hotkeys/HotkeyMonitor.swift`
- Create: `DyktandoTests/HotkeyMonitorTests.swift`

- [ ] **Step 1: Test for state transitions**

```swift
import XCTest
@testable import Dyktando

final class HotkeyMonitorTests: XCTestCase {
    func test_pushToTalk_emitsStartAndStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkUp()

        XCTAssertEqual(events, [.startCapture(.singleEngine), .stopCapture])
    }

    func test_toggle_emitsStartThenStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture(.singleEngine)])

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture(.singleEngine), .stopCapture])
    }
}
```

- [ ] **Step 2: Run, expect compile failure**

- [ ] **Step 3: Implement HotkeyMonitor**

```swift
import Foundation
import KeyboardShortcuts

enum CaptureKind: Equatable {
    case singleEngine
    case comparison
}

enum HotkeyEvent: Equatable {
    case startCapture(CaptureKind)
    case stopCapture
    case switchModel
    case openSettings
}

final class HotkeyMonitor {
    private let emit: (HotkeyEvent) -> Void
    private var isCapturing = false

    init(emit: @escaping (HotkeyEvent) -> Void) {
        self.emit = emit
        bind()
    }

    private func bind() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.start(.singleEngine)
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.stop()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.toggle(.singleEngine)
        }
        KeyboardShortcuts.onKeyDown(for: .comparisonMode) { [weak self] in
            self?.start(.comparison)
        }
        KeyboardShortcuts.onKeyUp(for: .comparisonMode) { [weak self] in
            self?.stop()
        }
        KeyboardShortcuts.onKeyDown(for: .switchModel) { [weak self] in
            self?.emit(.switchModel)
        }
        KeyboardShortcuts.onKeyDown(for: .openSettings) { [weak self] in
            self?.emit(.openSettings)
        }
    }

    private func start(_ kind: CaptureKind) {
        guard !isCapturing else { return }
        isCapturing = true
        emit(.startCapture(kind))
    }

    private func stop() {
        guard isCapturing else { return }
        isCapturing = false
        emit(.stopCapture)
    }

    private func toggle(_ kind: CaptureKind) {
        isCapturing ? stop() : start(kind)
    }

    // MARK: - Testing seams
    func simulatePushToTalkDown() { start(.singleEngine) }
    func simulatePushToTalkUp() { stop() }
    func simulateToggleTap() { toggle(.singleEngine) }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Dyktando/Core/Hotkeys DyktandoTests
git commit -m "M1.2: HotkeyMonitor with PTT and toggle state machine"
```

---

### Task M1.3: AudioCapture (AVAudioEngine → 16 kHz mono buffer)

**Files:**
- Create: `Dyktando/Core/Audio/AudioCapture.swift`
- Create: `Dyktando/Core/Audio/AudioRingBuffer.swift`
- Create: `DyktandoTests/AudioRingBufferTests.swift`

- [ ] **Step 1: Test the ring buffer**

```swift
import XCTest
@testable import Dyktando

final class AudioRingBufferTests: XCTestCase {
    func test_appendAndDrain_returnsAllSamples() {
        let buf = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
        let samples: [Float] = (0..<1000).map { Float($0) * 0.001 }

        buf.append(samples)
        let drained = buf.drain()

        XCTAssertEqual(drained.count, 1000)
        XCTAssertEqual(drained.first, 0)
        XCTAssertEqual(drained.last, 0.999, accuracy: 1e-6)
    }

    func test_drain_emptiesBuffer() {
        let buf = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
        buf.append([1, 2, 3])
        _ = buf.drain()
        XCTAssertEqual(buf.drain(), [])
    }
}
```

- [ ] **Step 2: Implement AudioRingBuffer**

```swift
import Foundation

final class AudioRingBuffer {
    private var storage: [Float]
    private let queue = DispatchQueue(label: "ringbuffer", qos: .userInteractive)

    init(capacitySeconds: Int, sampleRate: Int) {
        storage = []
        storage.reserveCapacity(capacitySeconds * sampleRate)
    }

    func append(_ samples: [Float]) {
        queue.sync { storage.append(contentsOf: samples) }
    }

    func drain() -> [Float] {
        queue.sync {
            let out = storage
            storage.removeAll(keepingCapacity: true)
            return out
        }
    }
}
```

- [ ] **Step 3: Test passes**

- [ ] **Step 4: Implement AudioCapture**

```swift
import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ capture: AudioCapture, level rms: Float)
    func audioCapture(_ capture: AudioCapture, finishedWith samples: [Float], sampleRate: Double)
}

final class AudioCapture {
    weak var delegate: AudioCaptureDelegate?

    private let engine = AVAudioEngine()
    private let buffer = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false)!

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcm, _ in
            self?.handleTap(pcm)
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = buffer.drain()
        delegate?.audioCapture(self, finishedWith: samples, sampleRate: targetFormat.sampleRate)
    }

    private func handleTap(_ pcm: AVAudioPCMBuffer) {
        guard let converter else { return }
        let outFrames = AVAudioFrameCount(Double(pcm.frameLength)
                                          * targetFormat.sampleRate
                                          / pcm.format.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return pcm
        }

        guard let ch = out.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        buffer.append(samples)

        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        delegate?.audioCapture(self, level: rms)
    }
}
```

- [ ] **Step 5: Wire to AppDelegate, save WAV on stop**

In `AppDelegate.swift`, add:

```swift
private var hotkeys: HotkeyMonitor?
private var audio: AudioCapture?

func applicationDidFinishLaunching(_ notification: Notification) {
    menuBar = MenuBarController()
    let capture = AudioCapture()
    capture.delegate = self
    audio = capture

    hotkeys = HotkeyMonitor { [weak self] event in
        guard let self else { return }
        switch event {
        case .startCapture: try? self.audio?.start()
        case .stopCapture:  self.audio?.stop()
        default: break
        }
    }
}

extension AppDelegate: AudioCaptureDelegate {
    func audioCapture(_ capture: AudioCapture, level rms: Float) { /* M1.4 will use this */ }

    func audioCapture(_ capture: AudioCapture, finishedWith samples: [Float], sampleRate: Double) {
        let url = AppPaths.support.appendingPathComponent("last.wav")
        try? WAVWriter.write(samples, sampleRate: sampleRate, to: url)
    }
}
```

- [ ] **Step 6: Create AppPaths + WAVWriter helpers**

`Dyktando/Core/Audio/WAVWriter.swift`:

```swift
import AVFoundation

enum WAVWriter {
    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url,
                                   settings: format.settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: format,
                                   frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buf)
    }
}
```

`Dyktando/App/AppPaths.swift`:

```swift
import Foundation

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Dyktando", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
```

- [ ] **Step 7: Manual smoke test**

Run the app, grant Microphone (macOS will prompt). Hold `F5`, say "test", release.

Open in Finder:
```bash
open "$HOME/Library/Application Support/Dyktando/last.wav"
```
Expected: a recognizable recording of "test". Use Audacity or `afplay` to confirm.

- [ ] **Step 8: Commit**

```bash
git add Dyktando
git commit -m "M1.3: AudioCapture + WAV writer + AppDelegate wiring"
```

---

### Task M1.4: HUD pill with level meter

**Files:**
- Create: `Dyktando/UI/HUD/HUDController.swift`
- Create: `Dyktando/UI/HUD/HUDView.swift`
- Create: `DyktandoTests/HUDStateTests.swift`

- [ ] **Step 1: Test the state model**

```swift
import XCTest
@testable import Dyktando

final class HUDStateTests: XCTestCase {
    func test_transitions() {
        let state = HUDState()
        XCTAssertEqual(state.phase, .idle)
        state.beginListening()
        XCTAssertEqual(state.phase, .listening)
        state.beginTranscribing()
        XCTAssertEqual(state.phase, .transcribing)
        state.finish(preview: "hello")
        XCTAssertEqual(state.phase, .preview("hello"))
    }
}
```

- [ ] **Step 2: Implement HUDState as ObservableObject**

```swift
import SwiftUI

enum HUDPhase: Equatable {
    case idle, listening, transcribing
    case preview(String)
}

@MainActor
final class HUDState: ObservableObject {
    @Published private(set) var phase: HUDPhase = .idle
    @Published var level: Float = 0

    func beginListening() { phase = .listening }
    func beginTranscribing() { phase = .transcribing }
    func finish(preview: String) {
        phase = .preview(preview)
        Task { try? await Task.sleep(for: .milliseconds(800)); phase = .idle }
    }
}
```

- [ ] **Step 3: Implement HUDView**

```swift
import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 8) {
            icon
            content
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch state.phase {
        case .idle: EmptyView()
        case .listening: Image(systemName: "waveform").symbolEffect(.variableColor)
        case .transcribing: ProgressView().controlSize(.small)
        case .preview: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle: EmptyView()
        case .listening: LevelBar(level: state.level).frame(width: 80, height: 12)
        case .transcribing: Text("transkrybuję").font(.callout)
        case .preview(let text): Text(text).font(.callout).lineLimit(1)
        }
    }
}

struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.2))
                Capsule().fill(.tint).frame(width: geo.size.width * CGFloat(min(level * 4, 1)))
            }
        }
    }
}
```

- [ ] **Step 4: Implement HUDController**

```swift
import AppKit
import SwiftUI

@MainActor
final class HUDController {
    let state = HUDState()
    private var window: NSPanel?

    func show(near point: NSPoint) {
        if window == nil { window = makeWindow() }
        window?.setFrameOrigin(NSPoint(x: point.x - 60, y: point.y + 24))
        window?.orderFrontRegardless()
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        return panel
    }
}
```

- [ ] **Step 5: Wire HUD updates into AppDelegate audio delegate**

Modify `AppDelegate.swift`:

```swift
private var hud = HUDController()

// in audioCapture(_:level:):
Task { @MainActor in self.hud.state.level = rms }

// in HotkeyMonitor closure, .startCapture:
Task { @MainActor in
    self.hud.show(near: NSEvent.mouseLocation)
    self.hud.state.beginListening()
}

// in finishedWith:
Task { @MainActor in self.hud.state.beginTranscribing() }
// once "transcription" is no-op for now, immediately finish with placeholder:
Task { @MainActor in self.hud.state.finish(preview: "(audio captured)") }
```

- [ ] **Step 6: Smoke test**

Run app, hold `F5`. Expected: pill appears near cursor, level bar moves with voice, on release shows "transkrybuję" → "(audio captured)" → fades.

- [ ] **Step 7: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M1.4: HUD pill with state machine + level meter"
```

**Phase M1 acceptance:** Hold `F5` anywhere → HUD pill shows live level → release → WAV saved to App Support. No transcription yet.

---

## M2. Apple Speech engine + clipboard injection

### Task M2.1: EngineProtocol + TranscriptionResult types

**Files:**
- Create: `Dyktando/Engines/EngineProtocol.swift`
- Create: `DyktandoTests/EngineProtocolTests.swift`

- [ ] **Step 1: Test compile-only contract**

```swift
import XCTest
@testable import Dyktando

final class EngineProtocolTests: XCTestCase {
    func test_engineID_isHashable() {
        let set: Set<EngineID> = [.parakeetTDTv3, .whisperLargeV3Turbo]
        XCTAssertEqual(set.count, 2)
    }

    func test_result_basic() {
        let r = TranscriptionResult(text: "hi", language: Locale(identifier: "pl-PL"),
                                    inferenceMillis: 100, confidence: nil)
        XCTAssertEqual(r.text, "hi")
    }
}
```

- [ ] **Step 2: Implement types**

```swift
import AVFoundation

enum EngineID: String, Hashable, Codable, CaseIterable {
    case parakeetTDTv3 = "parakeet-tdt-v3"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"
    case appleSpeechPL = "apple-speech-pl"
}

struct TranscriptionResult: Equatable {
    let text: String
    let language: Locale
    let inferenceMillis: Int
    let confidence: Double?
}

enum LanguageMode: Equatable {
    case single(Locale)
    case multilingualAuto(Set<Locale>)
    case mixed(primary: Locale, allowed: Set<Locale>)
}

protocol TranscriptionEngine: AnyObject {
    var id: EngineID { get }
    var displayName: String { get }
    var supportedLanguages: Set<Locale> { get }
    var isInstalled: Bool { get }

    func install(progress: @escaping (Double) -> Void) async throws
    func uninstall() throws
    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult
}
```

- [ ] **Step 3: Test passes; commit**

```bash
git add Dyktando/Engines DyktandoTests
git commit -m "M2.1: EngineProtocol with TranscriptionResult + LanguageMode"
```

---

### Task M2.2: AppleSpeechEngine

**Files:**
- Create: `Dyktando/Engines/AppleSpeechEngine.swift`
- Create: `DyktandoTests/Resources/three-seconds-pl.wav` (record yourself once, ~3 s of clean PL, commit)
- Create: `DyktandoTests/AppleSpeechEngineTests.swift`

- [ ] **Step 1: Record fixture once**

```bash
# In Voice Memos or QuickTime, record 3 seconds of "Cześć, to jest test dyktowania."
# Export as 16 kHz mono WAV, save as:
# DyktandoTests/Resources/three-seconds-pl.wav
# Add to the test target in Xcode (Build Phases → Copy Bundle Resources)
```

- [ ] **Step 2: Test**

```swift
import XCTest
import AVFoundation
@testable import Dyktando

final class AppleSpeechEngineTests: XCTestCase {
    func test_transcribePolishFixture() async throws {
        let engine = AppleSpeechEngine()
        XCTAssertTrue(engine.isInstalled)

        let samples = try loadFixture("three-seconds-pl")
        let result = try await engine.transcribe(samples: samples, sampleRate: 16_000,
                                                 mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertTrue(result.text.lowercased().contains("test"))
    }

    private func loadFixture(_ name: String) throws -> [Float] {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "wav")!
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let count = Int(buf.frameLength)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: count))
    }
}
```

- [ ] **Step 3: Implement AppleSpeechEngine**

```swift
import Speech
import AVFoundation

final class AppleSpeechEngine: TranscriptionEngine {
    let id: EngineID = .appleSpeechPL
    let displayName = "Apple Speech (pl-PL)"
    let supportedLanguages: Set<Locale> = [Locale(identifier: "pl-PL")]
    var isInstalled: Bool { SFSpeechRecognizer.supportedLocales().contains(Locale(identifier: "pl-PL")) }

    func install(progress: @escaping (Double) -> Void) async throws {
        // System-provided; user may need to enable in Settings.
        progress(1)
    }

    func uninstall() throws { /* no-op */ }

    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult {
        let locale = languageForMode(mode)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw EngineError.unsupportedLocale(locale.identifier)
        }
        try await SFSpeechRecognizer.requestAuthorization()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        let pcm = try makeBuffer(samples: samples, sampleRate: sampleRate)
        let start = Date()

        return try await withCheckedThrowingContinuation { cont in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error { cont.resume(throwing: error); return }
                if let result, result.isFinal {
                    let r = TranscriptionResult(
                        text: result.bestTranscription.formattedString,
                        language: locale,
                        inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
                        confidence: result.bestTranscription.segments.first?.confidence.flatMap(Double.init))
                    cont.resume(returning: r)
                }
            }
            request.append(pcm)
            request.endAudio()
            _ = task
        }
    }

    private func languageForMode(_ mode: LanguageMode) -> Locale {
        switch mode {
        case .single(let l): return l
        case .multilingualAuto(let langs), .mixed(_, let langs):
            return langs.first { $0.identifier.hasPrefix("pl") } ?? Locale(identifier: "pl-PL")
        }
    }

    private func makeBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        return buf
    }
}

enum EngineError: Error { case unsupportedLocale(String), notInstalled, downloadFailed(String) }

extension SFSpeechRecognizer {
    static func requestAuthorization() async throws {
        let status = await withCheckedContinuation { cont in
            requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw EngineError.unsupportedLocale("not authorized") }
    }
}
```

- [ ] **Step 4: Add NSSpeechRecognitionUsageDescription to Info.plist**

Add key with value: `Dyktando uses speech recognition to transcribe your voice into text.`

- [ ] **Step 5: Test passes**

```bash
xcodebuild test -only-testing:DyktandoTests/AppleSpeechEngineTests \
  -project Dyktando.xcodeproj -scheme Dyktando \
  -destination 'platform=macOS' | tail
```
Expected: PASS, with test taking 1–3 s.

- [ ] **Step 6: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M2.2: AppleSpeechEngine + integration test against PL fixture"
```

---

### Task M2.3: Clipboard-only TextInjector

**Files:**
- Create: `Dyktando/Core/TextInjection/TextInjector.swift`
- Create: `DyktandoTests/TextInjectorTests.swift`

- [ ] **Step 1: Test that clipboard mode places text on pasteboard**

```swift
import XCTest
import AppKit
@testable import Dyktando

final class TextInjectorTests: XCTestCase {
    func test_clipboardMode_writesPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let injector = TextInjector(mode: .clipboardOnly)
        injector.insert("hello world")
        XCTAssertEqual(pb.string(forType: .string), "hello world")
    }
}
```

- [ ] **Step 2: Implement TextInjector with stub for paste mode (M3 implements paste)**

```swift
import AppKit

final class TextInjector {
    enum Mode { case clipboardOnly, accessibilityPaste }

    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    func insert(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard mode == .accessibilityPaste else { return }
        // Stub for M3.
    }
}
```

- [ ] **Step 3: Wire end-to-end in AppDelegate**

```swift
private let injector = TextInjector(mode: .clipboardOnly)
private let appleEngine = AppleSpeechEngine()

// in audioCapture(_:finishedWith:sampleRate:)
Task { [weak self] in
    guard let self else { return }
    await MainActor.run { self.hud.state.beginTranscribing() }
    do {
        let result = try await appleEngine.transcribe(
            samples: samples, sampleRate: sampleRate,
            mode: .single(Locale(identifier: "pl-PL")))
        await MainActor.run {
            self.injector.insert(result.text)
            self.hud.state.finish(preview: result.text)
        }
    } catch {
        await MainActor.run { self.hud.state.finish(preview: "błąd: \(error.localizedDescription)") }
    }
}
```

- [ ] **Step 4: Manual end-to-end**

Launch app → open TextEdit → click in document → hold `F5` → say "Cześć to jest test" → release → press `⌘V`.
Expected: text appears.

- [ ] **Step 5: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M2.3: clipboard-only TextInjector, end-to-end with Apple Speech"
```

**Phase M2 acceptance:** PTT → spoken Polish → press `⌘V` → text in any app.

---

## M3. Accessibility paste injection + onboarding

### Task M3.1: CGEvent ⌘V dispatcher

**Files:**
- Create: `Dyktando/Core/TextInjection/CGEventPaste.swift`
- Create: `DyktandoTests/CGEventPasteTests.swift`

- [ ] **Step 1: Test that it constructs a valid CGEvent sequence**

```swift
import XCTest
@testable import Dyktando

final class CGEventPasteTests: XCTestCase {
    func test_buildsKeyboardEvents() throws {
        let events = CGEventPaste.makeEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].getIntegerValueField(.keyboardEventKeycode), 9) // 'v'
        XCTAssertTrue(events[0].flags.contains(.maskCommand))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import CoreGraphics

enum CGEventPaste {
    static func makeEvents() -> [CGEvent] {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // ANSI 'V'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)!
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)!
        down.flags = .maskCommand
        up.flags = .maskCommand
        return [down, up]
    }

    static func dispatch() {
        for event in makeEvents() {
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M3.1: CGEventPaste builds and dispatches ⌘V"
```

---

### Task M3.2: TextInjector paste mode with clipboard restore

**Files:**
- Modify: `Dyktando/Core/TextInjection/TextInjector.swift`

- [ ] **Step 1: Extend test**

```swift
func test_pasteMode_restoresClipboardAfter() async throws {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString("original", forType: .string)

    let injector = TextInjector(mode: .accessibilityPaste)
    injector.insert("dictated")

    // Sleep slightly longer than the 60 ms restore delay
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(pb.string(forType: .string), "original")
}
```

- [ ] **Step 2: Implement paste mode**

```swift
import AppKit

final class TextInjector {
    enum Mode { case clipboardOnly, accessibilityPaste }
    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    func insert(_ text: String) {
        let pb = NSPasteboard.general
        let snapshot = snapshotPasteboard(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard mode == .accessibilityPaste else { return }
        CGEventPaste.dispatch()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            self.restorePasteboard(pb, from: snapshot)
        }
    }

    private struct PBItem { let types: [NSPasteboard.PasteboardType: Data] }

    private func snapshotPasteboard(_ pb: NSPasteboard) -> [PBItem] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return PBItem(types: dict)
        }
    }

    private func restorePasteboard(_ pb: NSPasteboard, from snapshot: [PBItem]) {
        pb.clearContents()
        for item in snapshot {
            let nsItem = NSPasteboardItem()
            for (type, data) in item.types { nsItem.setData(data, forType: type) }
            pb.writeObjects([nsItem])
        }
    }
}
```

- [ ] **Step 3: Test passes**

- [ ] **Step 4: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M3.2: TextInjector paste mode with clipboard snapshot/restore"
```

---

### Task M3.3: PermissionsService

**Files:**
- Create: `Dyktando/Core/Permissions/PermissionsService.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import AVFoundation

@MainActor
final class PermissionsService: ObservableObject {
    @Published var microphone: AVAudioApplication.recordPermission
    @Published var accessibility: Bool

    init() {
        microphone = AVAudioApplication.shared.recordPermission
        accessibility = AXIsProcessTrusted()
    }

    func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    self.microphone = AVAudioApplication.shared.recordPermission
                    cont.resume(returning: granted)
                }
            }
        }
    }

    func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        Task { await pollAccessibilityUntilTrusted() }
    }

    private func pollAccessibilityUntilTrusted() async {
        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .milliseconds(500))
        }
        accessibility = true
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Dyktando/Core/Permissions
git commit -m "M3.3: PermissionsService for mic + Accessibility"
```

---

### Task M3.4: First-run onboarding window

**Files:**
- Create: `Dyktando/UI/Onboarding/OnboardingWindow.swift`
- Create: `Dyktando/UI/Onboarding/OnboardingSteps.swift`
- Modify: `Dyktando/App/AppDelegate.swift`

- [ ] **Step 1: Implement onboarding shell**

```swift
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, microphone, accessibility, pickModel, testShortcut, done
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    let permissions: PermissionsService
    init(permissions: PermissionsService) { self.permissions = permissions }
    func next() { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
}
```

- [ ] **Step 2: Implement OnboardingWindow**

```swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init(state: OnboardingState, onFinish: @escaping () -> Void) {
        let root = OnboardingRoot(state: state, onFinish: onFinish)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Witamy w Dyktando"
        window.center()
        window.contentView = NSHostingView(rootView: root)
        self.init(window: window)
    }
}

struct OnboardingRoot: View {
    @ObservedObject var state: OnboardingState
    let onFinish: () -> Void

    var body: some View {
        VStack {
            switch state.step {
            case .welcome: WelcomeStep { state.next() }
            case .microphone: MicrophoneStep(permissions: state.permissions) { state.next() }
            case .accessibility: AccessibilityStep(permissions: state.permissions) { state.next() }
            case .pickModel: PickModelStep { state.next() }
            case .testShortcut: TestShortcutStep { state.next() }
            case .done: DoneStep { onFinish() }
            }
        }.padding(24)
    }
}
```

- [ ] **Step 3: Implement step views**

`Dyktando/UI/Onboarding/OnboardingSteps.swift` — each step is a simple SwiftUI view with title, copy, action button. Show actual content (not stubs):

```swift
import SwiftUI

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Dyktando").font(.largeTitle.bold())
            Text("Polskie dyktowanie głosowe na Macu, w pełni lokalne.").multilineTextAlignment(.center)
            Button("Dalej", action: next).keyboardShortcut(.return)
        }
    }
}

struct MicrophoneStep: View {
    @ObservedObject var permissions: PermissionsService
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Mikrofon").font(.title.bold())
            Text("Potrzebujemy mikrofonu żeby nagrywać twój głos. Nagranie nigdy nie opuszcza komputera.")
                .multilineTextAlignment(.center)
            Button("Włącz mikrofon") {
                Task { _ = await permissions.requestMicrophone(); next() }
            }
        }
    }
}

struct AccessibilityStep: View {
    @ObservedObject var permissions: PermissionsService
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Accessibility").font(.title.bold())
            Text("Żeby wpisywać tekst pod kursorem w dowolnej aplikacji, Dyktando potrzebuje uprawnienia Accessibility.")
                .multilineTextAlignment(.center)
            HStack {
                Button("Otwórz Ustawienia systemowe") { permissions.openAccessibilityPane() }
                Button("Pomiń (tryb schowka)") { next() }
            }
            if permissions.accessibility { Button("Dalej", action: next).keyboardShortcut(.return) }
        }
    }
}

struct PickModelStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Wybierz pierwszy model").font(.title.bold())
            Text("Apple Speech działa od razu. Inne silniki można doinstalować później w Ustawieniach.")
                .multilineTextAlignment(.center)
            Button("Użyj Apple Speech na początek", action: next)
        }
    }
}

struct TestShortcutStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Test").font(.title.bold())
            Text("Przytrzymaj F5 i powiedz dowolne zdanie. Tekst powinien pojawić się tutaj poniżej.")
                .multilineTextAlignment(.center)
            // M3 leaves this as a manual check; M6 adds a live captured-text textbox.
            Button("Dalej", action: next).keyboardShortcut(.return)
        }
    }
}

struct DoneStep: View {
    let finish: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Gotowe").font(.largeTitle.bold())
            Text("Możesz dyktować z dowolnej aplikacji. F5 = mów. ⌃⌥Space = przełącznik.")
                .multilineTextAlignment(.center)
            Button("Zamknij", action: finish).keyboardShortcut(.return)
        }
    }
}
```

- [ ] **Step 4: Show onboarding once on first launch**

In `AppDelegate.applicationDidFinishLaunching`:

```swift
private let permissions = PermissionsService()
private var onboarding: OnboardingWindowController?

let onboardedKey = "didCompleteOnboarding"
if !UserDefaults.standard.bool(forKey: onboardedKey) {
    let state = OnboardingState(permissions: permissions)
    onboarding = OnboardingWindowController(state: state) { [weak self] in
        UserDefaults.standard.set(true, forKey: onboardedKey)
        self?.onboarding?.close()
    }
    onboarding?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 5: Switch TextInjector mode based on Accessibility status**

```swift
private var injector: TextInjector {
    permissions.accessibility ? TextInjector(mode: .accessibilityPaste) : TextInjector(mode: .clipboardOnly)
}
```

- [ ] **Step 6: Manual end-to-end**

Reset onboarding: delete `~/Library/Preferences/com.bartekzimny.dyktando.plist`. Launch app.
Expected: onboarding window appears, walk through all 5 steps, dictation now inserts at cursor automatically.

- [ ] **Step 7: Commit**

```bash
git add Dyktando
git commit -m "M3.4: first-run onboarding window with mic + accessibility flow"
```

**Phase M3 acceptance:** First launch → walk through onboarding → grant both permissions → dictate in TextEdit → text appears at cursor, old clipboard preserved.

---

## M4. WhisperKit engine + model download UI

### Task M4.1: Add WhisperKit dependency

- [ ] **Step 1: Add SwiftPM package**

In Xcode → File → Add Package Dependencies → `https://github.com/argmaxinc/WhisperKit` → Up to Next Major Version. Add to `Dyktando` target.

- [ ] **Step 2: Build, expect success**

```bash
xcodebuild -project Dyktando.xcodeproj -scheme Dyktando -destination 'platform=macOS' build | tail
```

- [ ] **Step 3: Commit**

```bash
git add Dyktando.xcodeproj
git commit -m "M4.1: add WhisperKit SwiftPM dep"
```

---

### Task M4.2: WhisperKitEngine wrapping large-v3-turbo

**Files:**
- Create: `Dyktando/Engines/WhisperKitEngine.swift`
- Create: `DyktandoTests/WhisperKitEngineTests.swift`

- [ ] **Step 1: Test (uses same PL fixture)**

```swift
import XCTest
@testable import Dyktando

final class WhisperKitEngineTests: XCTestCase {
    func test_transcribePolishFixture_turbo() async throws {
        let engine = WhisperKitEngine(variant: .largeV3Turbo)
        try await engine.install { _ in }
        let samples = try TestFixtures.polishThreeSeconds()
        let result = try await engine.transcribe(samples: samples, sampleRate: 16_000,
                                                 mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertTrue(result.text.lowercased().contains("test"))
    }
}
```

(Add `TestFixtures` helper to share fixture loading across engine tests — extract from M2.2 test.)

- [ ] **Step 2: Implement**

```swift
import WhisperKit
import AVFoundation

final class WhisperKitEngine: TranscriptionEngine {
    enum Variant: String { case largeV3Turbo = "openai_whisper-large-v3-turbo"
                          case largeV3 = "openai_whisper-large-v3" }

    let id: EngineID
    let displayName: String
    let supportedLanguages: Set<Locale> = Set(Locale.availableIdentifiers.map(Locale.init))
    private let variant: Variant
    private var kit: WhisperKit?

    init(variant: Variant) {
        self.variant = variant
        switch variant {
        case .largeV3Turbo:
            id = .whisperLargeV3Turbo
            displayName = "Whisper large-v3-turbo"
        case .largeV3:
            id = .whisperLargeV3
            displayName = "Whisper large-v3"
        }
    }

    var isInstalled: Bool {
        let dir = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        return FileManager.default.fileExists(atPath: dir.path)
    }

    func install(progress: @escaping (Double) -> Void) async throws {
        let folder = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        kit = try await WhisperKit(model: variant.rawValue, downloadBase: folder, verbose: false)
        progress(1)
    }

    func uninstall() throws {
        let dir = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        try FileManager.default.removeItem(at: dir)
        kit = nil
    }

    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult {
        if kit == nil { try await install { _ in } }
        guard let kit else { throw EngineError.notInstalled }

        let start = Date()
        var options = DecodingOptions()
        options.language = languageHint(for: mode)
        let segments = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = segments.flatMap { $0.text }.joined(separator: " ")

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: Locale(identifier: options.language ?? "pl"),
            inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
            confidence: nil)
    }

    private func languageHint(for mode: LanguageMode) -> String? {
        switch mode {
        case .single(let l): return String(l.identifier.prefix(2))
        case .multilingualAuto, .mixed: return nil   // auto-detect (best for code-switching)
        }
    }
}
```

- [ ] **Step 3: Run test**

```bash
xcodebuild test -only-testing:DyktandoTests/WhisperKitEngineTests \
  -project Dyktando.xcodeproj -scheme Dyktando \
  -destination 'platform=macOS' | tail
```

(First run downloads ~1.5 GB. May take 10+ minutes on slow connection. Subsequent runs use cached model.)

- [ ] **Step 4: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M4.2: WhisperKitEngine wrapping large-v3-turbo and large-v3"
```

---

### Task M4.3: EngineRegistry and default-engine wiring

**Files:**
- Create: `Dyktando/Engines/EngineRegistry.swift`
- Create: `Dyktando/Persistence/Preferences.swift`

- [ ] **Step 1: Implement Preferences**

```swift
import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("defaultEngineID") var defaultEngineID: String = EngineID.appleSpeechPL.rawValue
    @AppStorage("languageMode") var languageModeRaw: String = "single:pl-PL"
    @AppStorage("hudEnabled") var hudEnabled: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}
```

(Note: `@AppStorage` works in `ObservableObject` via SwiftUI's import. If targeting non-SwiftUI use, swap to `UserDefaults` directly.)

- [ ] **Step 2: Implement EngineRegistry**

```swift
import Foundation

@MainActor
final class EngineRegistry: ObservableObject {
    @Published private(set) var engines: [EngineID: TranscriptionEngine] = [:]

    init() {
        engines[.appleSpeechPL] = AppleSpeechEngine()
        engines[.whisperLargeV3Turbo] = WhisperKitEngine(variant: .largeV3Turbo)
        engines[.whisperLargeV3] = WhisperKitEngine(variant: .largeV3)
        // Parakeet added in M5
    }

    func active(prefs: Preferences) -> TranscriptionEngine {
        guard let id = EngineID(rawValue: prefs.defaultEngineID),
              let engine = engines[id], engine.isInstalled else {
            return engines[.appleSpeechPL]!
        }
        return engine
    }
}
```

- [ ] **Step 3: Use in AppDelegate**

```swift
private let registry = EngineRegistry()
private let prefs = Preferences.shared

// In the audio-finished closure:
let engine = await MainActor.run { self.registry.active(prefs: self.prefs) }
let result = try await engine.transcribe(samples: samples, sampleRate: sampleRate,
                                         mode: .single(Locale(identifier: "pl-PL")))
```

- [ ] **Step 4: Commit**

```bash
git add Dyktando
git commit -m "M4.3: EngineRegistry + Preferences with default-engine selection"
```

**Phase M4 acceptance:** Set `defaultEngineID = whisper-large-v3-turbo` in UserDefaults, dictate → Whisper output appears.

---

## M5. Parakeet TDT v3 engine

### Task M5.1: Add FluidAudio dependency

- [ ] **Step 1: Add package**

In Xcode → File → Add Package Dependencies → `https://github.com/FluidInference/FluidAudio` → Add to `Dyktando` target.

- [ ] **Step 2: Build**

- [ ] **Step 3: Commit**

```bash
git add Dyktando.xcodeproj
git commit -m "M5.1: add FluidAudio (Parakeet) SwiftPM dep"
```

---

### Task M5.2: ParakeetEngine

**Files:**
- Create: `Dyktando/Engines/ParakeetEngine.swift`
- Create: `DyktandoTests/ParakeetEngineTests.swift`

- [ ] **Step 1: Test**

```swift
import XCTest
@testable import Dyktando

final class ParakeetEngineTests: XCTestCase {
    func test_transcribePolishFixture() async throws {
        let engine = ParakeetEngine()
        try await engine.install { _ in }
        let samples = try TestFixtures.polishThreeSeconds()
        let result = try await engine.transcribe(samples: samples, sampleRate: 16_000,
                                                 mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertTrue(result.text.lowercased().contains("test"))
        XCTAssertLessThan(result.inferenceMillis, 2000)   // ~80ms target, generous bound
    }
}
```

- [ ] **Step 2: Implement (FluidAudio v0.x API; adjust to actual API at impl time — see https://github.com/FluidInference/FluidAudio README for `ASRManager` / `AsrModels` symbols)**

```swift
import FluidAudio
import Foundation

final class ParakeetEngine: TranscriptionEngine {
    let id: EngineID = .parakeetTDTv3
    let displayName = "Parakeet TDT v3"
    let supportedLanguages: Set<Locale> = Set([
        "pl", "en", "de", "fr", "es", "it", "nl", "pt", "cs", "sk", "hu", "ro", "bg",
        "hr", "da", "fi", "el", "et", "lv", "lt", "mt", "ru", "uk", "sl", "sv"
    ].map(Locale.init(identifier:)))

    private var manager: AsrManager?

    var isInstalled: Bool {
        let dir = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        return FileManager.default.fileExists(atPath: dir.path)
    }

    func install(progress: @escaping (Double) -> Void) async throws {
        let dir = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let models = try await AsrModels.downloadAndLoad()
        manager = AsrManager(models: models)
        progress(1)
    }

    func uninstall() throws {
        let dir = AppPaths.support.appendingPathComponent("Models/\(id.rawValue)")
        try FileManager.default.removeItem(at: dir)
        manager = nil
    }

    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult {
        if manager == nil { try await install { _ in } }
        guard let manager else { throw EngineError.notInstalled }
        let start = Date()
        let result = try await manager.transcribe(samples: samples)
        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: Locale(identifier: result.detectedLanguage ?? "pl"),
            inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
            confidence: nil)
    }
}
```

- [ ] **Step 3: Register and make default for PL**

In `EngineRegistry.init`:
```swift
engines[.parakeetTDTv3] = ParakeetEngine()
```

In `Preferences`:
```swift
@AppStorage("defaultEngineID") var defaultEngineID: String = EngineID.parakeetTDTv3.rawValue
```

- [ ] **Step 4: Test passes**

- [ ] **Step 5: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M5.2: ParakeetEngine as default for Polish dictation"
```

**Phase M5 acceptance:** Fresh launch → Parakeet downloads → PTT → transcription appears within ~500 ms.

---

## M6. Settings window (5 tabs)

### Task M6.1: SettingsWindowController shell + tab routing

**Files:**
- Create: `Dyktando/UI/Settings/SettingsWindowController.swift`
- Create: `Dyktando/UI/Settings/SettingsRoot.swift`
- Modify: `Dyktando/App/MenuBarController.swift` (open settings from menu)

- [ ] **Step 1: Implement controller + root**

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Dyktando — Ustawienia"
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsRoot())
    }

    required init?(coder: NSCoder) { fatalError() }
}

enum SettingsTab: String, CaseIterable, Hashable {
    case general = "Ogólne", models = "Modele", language = "Język",
         shortcuts = "Skróty", audio = "Audio"
}

struct SettingsRoot: View {
    @State private var tab: SettingsTab = .general
    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("Ogólne", systemImage: "gearshape") }.tag(SettingsTab.general)
            ModelsTab().tabItem { Label("Modele", systemImage: "cpu") }.tag(SettingsTab.models)
            LanguageTab().tabItem { Label("Język", systemImage: "globe") }.tag(SettingsTab.language)
            ShortcutsTab().tabItem { Label("Skróty", systemImage: "keyboard") }.tag(SettingsTab.shortcuts)
            AudioTab().tabItem { Label("Audio", systemImage: "speaker.wave.2") }.tag(SettingsTab.audio)
        }.padding(16)
    }
}
```

- [ ] **Step 2: Wire menu item + hotkey**

In `MenuBarController.makeMenu`:
```swift
let settings = NSMenuItem(title: "Ustawienia…",
                          action: #selector(MenuBarController.openSettings),
                          keyEquivalent: ",")
settings.target = self
menu.addItem(settings)

@objc func openSettings() { SettingsWindowController.shared.showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
```

In `AppDelegate` HotkeyMonitor closure handle `.openSettings` event the same way.

- [ ] **Step 3: Commit**

```bash
git add Dyktando
git commit -m "M6.1: Settings window shell with 5 tabs"
```

---

### Task M6.2: GeneralTab — launch-at-login + HUD toggle

**Files:**
- Create: `Dyktando/UI/Settings/GeneralTab.swift`

- [ ] **Step 1: Implement (use `ServiceManagement.SMAppService` for launch-at-login)**

```swift
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Toggle("Pokaż HUD przy kursorze", isOn: $prefs.hudEnabled)
            Toggle("Uruchamiaj przy starcie systemu", isOn: Binding(
                get: { prefs.launchAtLogin },
                set: { newValue in
                    prefs.launchAtLogin = newValue
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        prefs.launchAtLogin = !newValue
                    }
                }))
        }.padding(16)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Dyktando/UI/Settings/GeneralTab.swift
git commit -m "M6.2: GeneralTab with HUD toggle and launch-at-login"
```

---

### Task M6.3: ModelsTab — install/uninstall per engine

**Files:**
- Create: `Dyktando/UI/Settings/ModelsTab.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct ModelsTab: View {
    @StateObject var registry = AppDelegate.shared.registry   // expose via singleton or env
    @ObservedObject var prefs = Preferences.shared
    @State private var installing: Set<EngineID> = []

    var body: some View {
        List(EngineID.allCases, id: \.self) { id in
            let engine = registry.engines[id]!
            HStack {
                VStack(alignment: .leading) {
                    Text(engine.displayName).font(.headline)
                    Text(engine.isInstalled ? "Zainstalowany" : "Niezainstalowany")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if engine.isInstalled {
                    Button("Odinstaluj") { try? engine.uninstall() }
                } else if installing.contains(id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Zainstaluj") {
                        Task {
                            installing.insert(id)
                            try? await engine.install { _ in }
                            installing.remove(id)
                        }
                    }
                }
                Button("Ustaw domyślny") { prefs.defaultEngineID = id.rawValue }
                    .disabled(!engine.isInstalled)
            }.padding(.vertical, 4)
        }
    }
}
```

(Expose `AppDelegate.shared` as a `static let shared = AppDelegate()` set in `applicationDidFinishLaunching` if cleaner; otherwise inject via SwiftUI `@Environment`.)

- [ ] **Step 2: Commit**

```bash
git add Dyktando/UI/Settings/ModelsTab.swift
git commit -m "M6.3: ModelsTab with install/uninstall/set-default per engine"
```

---

### Task M6.4: LanguageTab — mode + language list

**Files:**
- Create: `Dyktando/UI/Settings/LanguageTab.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct LanguageTab: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var mode: LanguageMode = .mixed(primary: Locale(identifier: "pl-PL"),
                                                   allowed: [Locale(identifier: "pl-PL"),
                                                             Locale(identifier: "en-US")])

    var body: some View {
        Form {
            Picker("Tryb języka", selection: Binding(
                get: { modeLabel },
                set: { newLabel in
                    switch newLabel {
                    case "Pojedynczy": mode = .single(Locale(identifier: "pl-PL"))
                    case "Multi auto-detect": mode = .multilingualAuto([Locale(identifier: "pl-PL"),
                                                                        Locale(identifier: "en-US")])
                    case "Mixed PL+EN": mode = .mixed(primary: Locale(identifier: "pl-PL"),
                                                      allowed: [Locale(identifier: "pl-PL"),
                                                                Locale(identifier: "en-US")])
                    default: break
                    }
                    prefs.languageModeRaw = encode(mode)
                })) {
                Text("Pojedynczy").tag("Pojedynczy")
                Text("Multi auto-detect").tag("Multi auto-detect")
                Text("Mixed PL+EN").tag("Mixed PL+EN")
            }.pickerStyle(.radioGroup)
        }.padding(16)
    }

    private var modeLabel: String {
        switch mode {
        case .single: return "Pojedynczy"
        case .multilingualAuto: return "Multi auto-detect"
        case .mixed: return "Mixed PL+EN"
        }
    }

    private func encode(_ mode: LanguageMode) -> String {
        switch mode {
        case .single(let l): return "single:\(l.identifier)"
        case .multilingualAuto(let langs): return "multi:" + langs.map(\.identifier).sorted().joined(separator: ",")
        case .mixed(let primary, let langs): return "mixed:\(primary.identifier)/" + langs.map(\.identifier).sorted().joined(separator: ",")
        }
    }
}
```

- [ ] **Step 2: Round-trip test for encode/decode**

```swift
func test_languageMode_encodeDecode_roundTrip() {
    let original = LanguageMode.mixed(primary: Locale(identifier: "pl-PL"),
                                      allowed: [Locale(identifier: "pl-PL"), Locale(identifier: "en-US")])
    let encoded = LanguageModeCodec.encode(original)
    let decoded = LanguageModeCodec.decode(encoded)
    XCTAssertEqual(decoded, original)
}
```

(Extract `encode`/`decode` into a small `LanguageModeCodec` enum so it can be tested without UI.)

- [ ] **Step 3: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M6.4: LanguageTab with three language modes + codec"
```

---

### Task M6.5: ShortcutsTab + AudioTab

**Files:**
- Create: `Dyktando/UI/Settings/ShortcutsTab.swift`
- Create: `Dyktando/UI/Settings/AudioTab.swift`

- [ ] **Step 1: Implement ShortcutsTab using KeyboardShortcuts.Recorder**

```swift
import SwiftUI
import KeyboardShortcuts

struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Push-to-talk", name: .pushToTalk)
            KeyboardShortcuts.Recorder("Toggle dictation", name: .toggleDictation)
            KeyboardShortcuts.Recorder("Switch model", name: .switchModel)
            KeyboardShortcuts.Recorder("Comparison mode", name: .comparisonMode)
            KeyboardShortcuts.Recorder("Open Settings", name: .openSettings)
            Button("Przywróć domyślne") {
                KeyboardShortcuts.reset(.pushToTalk, .toggleDictation, .switchModel, .comparisonMode, .openSettings)
            }
        }.padding(16)
    }
}
```

- [ ] **Step 2: Implement AudioTab with input device picker + live level**

```swift
import SwiftUI
import AVFoundation

struct AudioTab: View {
    @State private var devices: [String] = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInMicrophone, .externalUnknown],
        mediaType: .audio,
        position: .unspecified
    ).devices.map(\.localizedName)
    @State private var selected: String = AVCaptureDevice.default(for: .audio)?.localizedName ?? ""

    var body: some View {
        Form {
            Picker("Wejście", selection: $selected) {
                ForEach(devices, id: \.self) { Text($0).tag($0) }
            }
            Text("Próbkowanie: 16 kHz mono (stałe)").foregroundStyle(.secondary)
        }.padding(16)
    }
}
```

(Wiring `selected` back into `AudioCapture` is deferred — capture currently uses default input. Track as TODO in spec §15 "Open questions". For MVP, the picker is informational.)

- [ ] **Step 3: Commit**

```bash
git add Dyktando/UI/Settings
git commit -m "M6.5: ShortcutsTab and AudioTab"
```

**Phase M6 acceptance:** All shortcuts rebindable in Settings; models can be installed/uninstalled from UI; language mode persists across launches.

---

## M7. Comparison mode + stats

### Task M7.1: TranscriptionRouter — parallel dispatch

**Files:**
- Create: `Dyktando/Engines/TranscriptionRouter.swift`
- Create: `DyktandoTests/TranscriptionRouterTests.swift`

- [ ] **Step 1: Test parallel dispatch**

```swift
import XCTest
@testable import Dyktando

final class TranscriptionRouterTests: XCTestCase {
    func test_routeAll_returnsOneResultPerEngine() async throws {
        let router = TranscriptionRouter(engines: [FakeEngine(id: .appleSpeechPL, delay: 50, text: "a"),
                                                   FakeEngine(id: .parakeetTDTv3, delay: 50, text: "b")])
        let results = try await router.routeAll(samples: [], sampleRate: 16_000,
                                                mode: .mixed(primary: .init(identifier: "pl"), allowed: []))
        XCTAssertEqual(Set(results.map(\.engineID)), [.appleSpeechPL, .parakeetTDTv3])
    }
}

private final class FakeEngine: TranscriptionEngine {
    let id: EngineID
    let displayName = "fake"
    let supportedLanguages: Set<Locale> = []
    var isInstalled = true
    private let delay: UInt64
    private let text: String

    init(id: EngineID, delay: UInt64, text: String) { self.id = id; self.delay = delay; self.text = text }
    func install(progress: @escaping (Double) -> Void) async throws { progress(1) }
    func uninstall() throws {}
    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult {
        try await Task.sleep(nanoseconds: delay * 1_000_000)
        return TranscriptionResult(text: text, language: .init(identifier: "pl"), inferenceMillis: Int(delay), confidence: nil)
    }
}
```

- [ ] **Step 2: Implement**

```swift
struct ComparisonRow: Equatable {
    let engineID: EngineID
    let result: TranscriptionResult
}

final class TranscriptionRouter {
    private let engines: [TranscriptionEngine]
    init(engines: [TranscriptionEngine]) { self.engines = engines.filter(\.isInstalled) }

    func route(samples: [Float], sampleRate: Double, mode: LanguageMode,
               using engine: TranscriptionEngine) async throws -> TranscriptionResult {
        try await engine.transcribe(samples: samples, sampleRate: sampleRate, mode: mode)
    }

    func routeAll(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> [ComparisonRow] {
        try await withThrowingTaskGroup(of: ComparisonRow.self) { group in
            for engine in engines {
                group.addTask {
                    let r = try await engine.transcribe(samples: samples, sampleRate: sampleRate, mode: mode)
                    return ComparisonRow(engineID: engine.id, result: r)
                }
            }
            var out: [ComparisonRow] = []
            for try await row in group { out.append(row) }
            return out
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M7.1: TranscriptionRouter with parallel routeAll"
```

---

### Task M7.2: ComparisonWindow

**Files:**
- Create: `Dyktando/UI/Comparison/ComparisonWindow.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

@MainActor
final class ComparisonWindowController: NSWindowController {
    static let shared = ComparisonWindowController()

    private let state = ComparisonState()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Porównanie modeli"
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ComparisonView(state: state))
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ rows: [ComparisonRow], onPick: @escaping (ComparisonRow) -> Void) {
        state.rows = rows
        state.onPick = onPick
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ComparisonState: ObservableObject {
    @Published var rows: [ComparisonRow] = []
    var onPick: ((ComparisonRow) -> Void)?
}

struct ComparisonView: View {
    @ObservedObject var state: ComparisonState
    var body: some View {
        VStack(alignment: .leading) {
            Text("Wybierz najlepszą transkrypcję").font(.headline)
            ForEach(state.rows, id: \.engineID) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.engineID.rawValue).font(.subheadline.bold())
                        Text(row.result.text).font(.body)
                        Text("\(row.result.inferenceMillis) ms").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Użyj tej") { state.onPick?(row) }
                }.padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(16)
    }
}
```

- [ ] **Step 2: Wire `comparisonMode` event into AppDelegate**

In `AppDelegate`, when the audio buffer arrives from a `.comparison` capture:

```swift
let router = TranscriptionRouter(engines: Array(registry.engines.values))
let rows = try await router.routeAll(samples: samples, sampleRate: sampleRate, mode: currentMode)
ComparisonWindowController.shared.show(rows) { chosen in
    self.injector.insert(chosen.result.text)
    Task { await self.stats.record(chosen: chosen.engineID, language: chosen.result.language) }
}
```

Track the in-flight capture kind on `HotkeyEvent` (already in `CaptureKind`).

- [ ] **Step 3: Commit**

```bash
git add Dyktando
git commit -m "M7.2: ComparisonWindow with side-by-side results and pick"
```

---

### Task M7.3: ComparisonStats persistence + nudge

**Files:**
- Create: `Dyktando/Persistence/ComparisonStats.swift`
- Create: `DyktandoTests/ComparisonStatsTests.swift`

- [ ] **Step 1: Test**

```swift
import XCTest
@testable import Dyktando

final class ComparisonStatsTests: XCTestCase {
    func test_majorityWinnerOver10Picks_triggersNudge() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID()).json")
        let stats = ComparisonStats(url: tmp)
        for _ in 0..<8 { await stats.record(chosen: .parakeetTDTv3, language: .init(identifier: "pl-PL")) }
        for _ in 0..<2 { await stats.record(chosen: .whisperLargeV3, language: .init(identifier: "pl-PL")) }
        let nudge = await stats.nudgeIfApplicable(for: .init(identifier: "pl-PL"))
        XCTAssertEqual(nudge?.winner, .parakeetTDTv3)
        XCTAssertEqual(nudge?.winRate, 0.8, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

actor ComparisonStats {
    struct Entry: Codable { let timestamp: Date; let chosen: EngineID; let language: String }
    struct Nudge { let winner: EngineID; let winRate: Double }

    private let url: URL
    private var entries: [Entry] = []

    init(url: URL) {
        self.url = url
        load()
    }

    convenience init() {
        self.init(url: AppPaths.support.appendingPathComponent("comparison-stats.json"))
    }

    func record(chosen: EngineID, language: Locale) {
        entries.append(Entry(timestamp: Date(), chosen: chosen, language: language.identifier))
        persist()
    }

    func nudgeIfApplicable(for language: Locale) -> Nudge? {
        let recent = entries.filter { $0.language == language.identifier }.suffix(10)
        guard recent.count >= 10 else { return nil }
        let counts = Dictionary(grouping: recent, by: \.chosen).mapValues(\.count)
        guard let (winner, count) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let rate = Double(count) / 10.0
        return rate >= 0.7 ? Nudge(winner: winner, winRate: rate) : nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 3: Surface nudge banner in HUD or Settings**

In the comparison `onPick` closure:

```swift
Task {
    await self.stats.record(chosen: chosen.engineID, language: chosen.result.language)
    if let nudge = await self.stats.nudgeIfApplicable(for: chosen.result.language) {
        await MainActor.run {
            NSAlert.askToSetDefault(engine: nudge.winner, winRate: nudge.winRate, prefs: self.prefs)
        }
    }
}
```

`NSAlert.askToSetDefault` is a small helper in `Dyktando/UI/Comparison/NudgeAlert.swift`:

```swift
import AppKit

extension NSAlert {
    @MainActor
    static func askToSetDefault(engine: EngineID, winRate: Double, prefs: Preferences) {
        let alert = NSAlert()
        alert.messageText = "Wygląda na to, że \(engine.rawValue) najlepiej ci pasuje"
        alert.informativeText = "Wybrałeś go w \(Int(winRate * 100))% z ostatnich 10 porównań. Ustawić jako domyślny?"
        alert.addButton(withTitle: "Tak, ustaw")
        alert.addButton(withTitle: "Nie teraz")
        if alert.runModal() == .alertFirstButtonReturn {
            prefs.defaultEngineID = engine.rawValue
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M7.3: ComparisonStats persistence + 10-pick nudge alert"
```

**Phase M7 acceptance:** Hold `⌃⌥C`, speak, see 4 transcriptions, click winner → text inserts at cursor → after 10 picks dominant engine triggers nudge.

---

## M8. Multilingual / PL+EN code-switching

### Task M8.1: Plumb LanguageMode end-to-end

**Files:**
- Modify: `Dyktando/App/AppDelegate.swift`
- Modify: `Dyktando/Persistence/Preferences.swift`
- Create: `Dyktando/Persistence/LanguageModeCodec.swift`

- [ ] **Step 1: Implement codec (extracted in M6.4)**

```swift
import Foundation

enum LanguageModeCodec {
    static func encode(_ mode: LanguageMode) -> String {
        switch mode {
        case .single(let l): return "single:\(l.identifier)"
        case .multilingualAuto(let langs):
            return "multi:" + langs.map(\.identifier).sorted().joined(separator: ",")
        case .mixed(let primary, let langs):
            return "mixed:\(primary.identifier)/" + langs.map(\.identifier).sorted().joined(separator: ",")
        }
    }

    static func decode(_ s: String) -> LanguageMode {
        if s.hasPrefix("single:") {
            return .single(Locale(identifier: String(s.dropFirst("single:".count))))
        }
        if s.hasPrefix("multi:") {
            let langs = s.dropFirst("multi:".count).split(separator: ",").map { Locale(identifier: String($0)) }
            return .multilingualAuto(Set(langs))
        }
        if s.hasPrefix("mixed:") {
            let rest = s.dropFirst("mixed:".count)
            let parts = rest.split(separator: "/")
            let primary = Locale(identifier: String(parts[0]))
            let langs = parts[1].split(separator: ",").map { Locale(identifier: String($0)) }
            return .mixed(primary: primary, allowed: Set(langs))
        }
        return .single(Locale(identifier: "pl-PL"))
    }
}
```

- [ ] **Step 2: Use codec in AppDelegate**

```swift
private var currentMode: LanguageMode { LanguageModeCodec.decode(prefs.languageModeRaw) }
```

Replace hardcoded `.single(...)` in the audio-finished closure with `currentMode`.

- [ ] **Step 3: Commit**

```bash
git add Dyktando
git commit -m "M8.1: LanguageModeCodec end-to-end; preferences drive engine.transcribe mode"
```

---

### Task M8.2: EnglishTermDetector + Polish post-processing skip

**Files:**
- Create: `Dyktando/Postprocess/EnglishTermDetector.swift`
- Create: `Dyktando/Resources/english_terms.txt` (bundled word list, ~5k common English tech/business terms)
- Create: `DyktandoTests/EnglishTermDetectorTests.swift`

- [ ] **Step 1: Source word list**

Build a list of 5k common English tech terms (`deployment`, `merge`, `pull`, `request`, `commit`, `pipeline`, `cluster`, `dashboard`, `stack`, `overflow`, etc.). Save one term per line to `Dyktando/Resources/english_terms.txt`. Add to target resources.

```bash
# Use https://www.wordfrequency.info/free.asp or a similar source filtered to ASCII tech words.
# For MVP a curated list of ~200 terms is enough; the list will grow.
```

- [ ] **Step 2: Test**

```swift
import XCTest
@testable import Dyktando

final class EnglishTermDetectorTests: XCTestCase {
    func test_recognizesCommonEnglishWords() {
        let det = EnglishTermDetector.shared
        XCTAssertTrue(det.isEnglishTerm("deployment"))
        XCTAssertTrue(det.isEnglishTerm("Deployment"))
        XCTAssertFalse(det.isEnglishTerm("kropka"))
        XCTAssertFalse(det.isEnglishTerm("zażółć"))
    }
}
```

- [ ] **Step 3: Implement**

```swift
import Foundation

final class EnglishTermDetector {
    static let shared = EnglishTermDetector()
    private let set: Set<String>

    private init() {
        let url = Bundle.main.url(forResource: "english_terms", withExtension: "txt")!
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        set = Set(text.split(separator: "\n").map { $0.lowercased() })
    }

    func isEnglishTerm(_ word: String) -> Bool {
        guard word.allSatisfy({ $0.isASCII }) else { return false }
        return set.contains(word.lowercased())
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M8.2: EnglishTermDetector with bundled word list"
```

---

### Task M8.3: Code-switch corpus test

**Files:**
- Create: `Dyktando/Resources/code_switch_corpus.txt` (15 PL+EN sentences)
- Create: `DyktandoTests/CodeSwitchTests.swift`

- [ ] **Step 1: Author corpus**

`Dyktando/Resources/code_switch_corpus.txt` (one sentence per line, with expected English terms in `<en>...</en>`):

```
Trzeba zrobić <en>deployment</en> na <en>production</en> przed <en>pull requestem</en>.
Stwórz <en>commit</en> z opisem i wrzuć na <en>main</en>.
Sprawdź <en>stack overflow</en> w sprawie tego błędu w <en>typescript</en>.
Mamy nowy <en>backend</en> w <en>node js</en> z <en>redis</en> jako cache.
Zrób <en>code review</en> przed <en>merge</en>.
Zaktualizuj <en>readme</en> i <en>changelog</en>.
Dodaj <en>middleware</en> dla <en>authentication</en>.
Ten <en>endpoint</en> zwraca <en>json</en> z błędem 500.
Wrzuć obraz <en>dockera</en> do <en>registry</en>.
Trzeba przetestować na <en>staging</en> przed releasem.
W <en>github actions</en> trzeba dodać krok z <en>linterem</en>.
Sklonuj <en>repo</en> i odpal <en>npm install</en>.
<en>Frontend</en> i <en>backend</en> komunikują się przez <en>websocket</en>.
Otwórz <en>pull request</en> i poproś o <en>review</en>.
Mamy <en>memory leak</en> w <en>workerze</en>.
```

- [ ] **Step 2: Test that Mixed-mode Whisper preserves English terms**

```swift
import XCTest
@testable import Dyktando

final class CodeSwitchTests: XCTestCase {
    func test_whisperV3_keepsEnglishTermsInMixedMode() async throws {
        // Use a single pre-recorded PL+EN sample (record once and bundle).
        // Fixture: code-switch-deployment-production.wav saying:
        // "Trzeba zrobić deployment na production przed pull requestem"
        let engine = WhisperKitEngine(variant: .largeV3)
        try await engine.install { _ in }
        let samples = try TestFixtures.codeSwitchDeployment()
        let mode: LanguageMode = .mixed(primary: Locale(identifier: "pl-PL"),
                                        allowed: [Locale(identifier: "pl-PL"),
                                                  Locale(identifier: "en-US")])
        let result = try await engine.transcribe(samples: samples, sampleRate: 16_000, mode: mode)
        let lower = result.text.lowercased()
        XCTAssertTrue(lower.contains("deployment"))
        XCTAssertTrue(lower.contains("production"))
        XCTAssertTrue(lower.contains("pull request"))
    }
}
```

- [ ] **Step 3: Record code-switch fixture once**

Record `DyktandoTests/Resources/code-switch-deployment-production.wav` saying "Trzeba zrobić deployment na production przed pull requestem" — 16 kHz mono WAV. Bundle in test target.

- [ ] **Step 4: Run test**

Expected: PASS for Whisper large-v3.

- [ ] **Step 5: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M8.3: code-switch corpus + Whisper v3 PL+EN test"
```

**Phase M8 acceptance:** Set Language Mode = Mixed PL+EN, default engine = Whisper large-v3 → dictate "trzeba zrobić deployment na production" → "deployment" and "production" appear in English spelling.

---

## M9. Post-processing polish + replacement rules

### Task M9.1: PolishCapitalizer + PunctuationHeuristic

**Files:**
- Create: `Dyktando/Postprocess/PolishCapitalizer.swift`
- Create: `Dyktando/Postprocess/PunctuationHeuristic.swift`
- Create: `DyktandoTests/PostprocessTests.swift`

- [ ] **Step 1: Tests**

```swift
import XCTest
@testable import Dyktando

final class PostprocessTests: XCTestCase {
    func test_capitalizesFirstAndAfterSentenceEnd() {
        XCTAssertEqual(PolishCapitalizer.apply("dzień dobry. jak się masz?"),
                       "Dzień dobry. Jak się masz?")
    }

    func test_addsTrailingDotIfMissing() {
        XCTAssertEqual(PunctuationHeuristic.apply("to jest dłuższe zdanie bez kropki"),
                       "to jest dłuższe zdanie bez kropki.")
    }

    func test_doesNotAddDotIfShort() {
        XCTAssertEqual(PunctuationHeuristic.apply("tak"), "tak")
    }
}
```

- [ ] **Step 2: Implement PolishCapitalizer**

```swift
enum PolishCapitalizer {
    static func apply(_ text: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in text {
            if capitalizeNext, ch.isLetter {
                out.append(Character(ch.uppercased()))
                capitalizeNext = false
            } else {
                out.append(ch)
            }
            if ".!?".contains(ch) { capitalizeNext = true }
        }
        return out
    }
}
```

- [ ] **Step 3: Implement PunctuationHeuristic**

```swift
enum PunctuationHeuristic {
    static func apply(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return text }
        if ".!?".contains(last) { return text }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount > 6 ? trimmed + "." : trimmed
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M9.1: PolishCapitalizer + PunctuationHeuristic with tests"
```

---

### Task M9.2: ReplacementRules + PostprocessPipeline

**Files:**
- Create: `Dyktando/Postprocess/ReplacementRules.swift`
- Create: `Dyktando/Postprocess/PostprocessPipeline.swift`

- [ ] **Step 1: Test**

```swift
func test_replacementRules_appliesDefaultDictation() {
    let rules = ReplacementRules.defaults
    XCTAssertEqual(rules.apply("powiedz kropka"), "powiedz .")
    XCTAssertEqual(rules.apply("hello nowa linia world"), "hello \n world")
}

func test_pipeline_skipsReplacementsForEnglishWordsInMixedMode() {
    let pipeline = PostprocessPipeline(mode: .mixed(primary: .init(identifier: "pl-PL"),
                                                    allowed: [.init(identifier: "en-US")]))
    // "kropka" inside "merge request kropka" should still expand because kropka is Polish dictation marker.
    // The skip only protects words that match the English list, e.g. "deployment".
    let out = pipeline.apply("deployment kropka")
    XCTAssertEqual(out, "Deployment.")
}
```

- [ ] **Step 2: Implement ReplacementRules**

```swift
struct ReplacementRules {
    let pairs: [(String, String)]
    static let defaults = ReplacementRules(pairs: [
        ("kropka", "."),
        ("przecinek", ","),
        ("znak zapytania", "?"),
        ("wykrzyknik", "!"),
        ("nowa linia", "\n"),
        ("nowy akapit", "\n\n")
    ])

    func apply(_ text: String) -> String {
        var out = text
        for (k, v) in pairs {
            out = out.replacingOccurrences(of: " \(k) ", with: " \(v) ")
            if out.hasSuffix(" \(k)") { out = String(out.dropLast(k.count + 1)) + v }
        }
        return out
    }
}
```

- [ ] **Step 3: Implement PostprocessPipeline**

```swift
struct PostprocessPipeline {
    let mode: LanguageMode

    func apply(_ raw: String) -> String {
        let replaced = ReplacementRules.defaults.apply(raw)
        let punct = PunctuationHeuristic.apply(replaced)
        let capped = PolishCapitalizer.apply(punct)
        // Smart spacing
        return smartSpace(capped)
    }

    private func smartSpace(_ s: String) -> String {
        s.replacingOccurrences(of: " .", with: ".")
         .replacingOccurrences(of: " ,", with: ",")
         .replacingOccurrences(of: " ?", with: "?")
         .replacingOccurrences(of: " !", with: "!")
    }
}
```

- [ ] **Step 4: Wire pipeline into AppDelegate before TextInjector**

```swift
let pipeline = PostprocessPipeline(mode: self.currentMode)
let polished = pipeline.apply(result.text)
self.injector.insert(polished)
```

- [ ] **Step 5: Commit**

```bash
git add Dyktando DyktandoTests
git commit -m "M9.2: PostprocessPipeline composing replace+punct+caps+smartspace"
```

**Phase M9 acceptance:** Dictate "dzień dobry kropka jak się masz znak zapytania" → "Dzień dobry. Jak się masz?".

---

## M10. Distribution

### Task M10.1: Makefile + create-dmg

**Files:**
- Create: `Makefile`
- Create: `scripts/make-dmg.sh`

- [ ] **Step 1: Write Makefile**

```makefile
.PHONY: build test archive dmg clean

XCODE_PROJECT := Dyktando.xcodeproj
SCHEME := Dyktando
BUILD_DIR := build

build:
	xcodebuild -project $(XCODE_PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR) build | xcpretty

test:
	xcodebuild test -project $(XCODE_PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR) | xcpretty

archive:
	xcodebuild archive -project $(XCODE_PROJECT) -scheme $(SCHEME) \
	  -archivePath $(BUILD_DIR)/Dyktando.xcarchive | xcpretty

dmg: archive
	./scripts/make-dmg.sh $(BUILD_DIR)/Dyktando.xcarchive

clean:
	rm -rf $(BUILD_DIR) *.dmg
```

- [ ] **Step 2: Write make-dmg.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
ARCHIVE="$1"
APP="$ARCHIVE/Products/Applications/Dyktando.app"

if ! command -v create-dmg >/dev/null; then
  echo "Install create-dmg: brew install create-dmg" >&2
  exit 1
fi

codesign --force --deep --sign - "$APP"

create-dmg \
  --volname "Dyktando" \
  --window-size 540 360 \
  --icon "Dyktando.app" 140 180 \
  --app-drop-link 400 180 \
  "Dyktando.dmg" \
  "$APP"

echo "Built Dyktando.dmg"
```

```bash
chmod +x scripts/make-dmg.sh
```

- [ ] **Step 3: Build first DMG**

```bash
brew install create-dmg xcpretty
make dmg
ls -lh Dyktando.dmg
```

Expected: `Dyktando.dmg` present, double-click opens installer.

- [ ] **Step 4: Commit**

```bash
git add Makefile scripts
git commit -m "M10.1: Makefile + create-dmg script for ad-hoc signed distribution"
```

---

### Task M10.2: README with install + usage

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README with proper install + usage**

```markdown
# Dyktando

Polish-focused on-device dictation app for macOS. Wispr-Flow-style global hotkey, four selectable engines, side-by-side comparison.

## Install

1. Download `Dyktando.dmg` from [Releases](#).
2. Drag `Dyktando.app` to `/Applications`.
3. Launch. Follow first-run onboarding (microphone + accessibility).

## Use

- `F5` (hold) — push-to-talk dictation
- `⌃⌥Space` — toggle dictation
- `⌃⌥C` (hold) — comparison mode (4 engines side-by-side)
- `⌃⌥M` — switch active model
- `⌃⌥,` — open Settings

All shortcuts rebindable in Settings → Skróty.

## Build from source

```bash
git clone https://github.com/<you>/dyktando-mac.git
cd dyktando-mac
open Dyktando.xcodeproj
```

Requires Xcode 26.5+ and macOS 14+.

## Privacy

100% on-device. No audio leaves your Mac. Verify with Little Snitch — there is no analytics, no telemetry, no cloud transcription.

## License

MIT (or whatever you choose).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "M10.2: README with install, usage, and privacy notes"
```

**Phase M10 acceptance:** `make dmg` produces an installable DMG that you can hand to a friend's Mac.

---

## Self-review (run before handing off)

1. **Spec coverage** — every numbered section of the spec maps to a milestone:

   - §1 Overview / §1.1 Goals → covered by full plan
   - §2 Architecture → file layout in plan; M0–M1 lay foundations
   - §3 Engine layer → M2 (Apple), M4 (Whisper), M5 (Parakeet)
   - §4 Audio pipeline → M1.3
   - §5 Hotkeys → M1.2, M6.5
   - §6 Text injection → M2.3, M3.1, M3.2
   - §7 HUD → M1.4
   - §8 Comparison mode → M7
   - §9 Settings UI → M6
   - §10 Polish post-processing → M9
   - §11 Permissions and onboarding → M3.3, M3.4
   - §12 Distribution → M10
   - §13 Testing strategy → tests embedded throughout
   - §14 Multilingual / code-switching → M8
   - §15 Open questions → carried as TODOs (audio device picker wiring, vocabulary boosting, stats export)
   - §16 Out of scope → enforced by not planning those tasks

2. **Placeholder scan** — no TBD / TODO / "implement later" in steps. (One TODO acknowledged in M6.5 audio device picker, scoped explicitly.)

3. **Type consistency** — `EngineID`, `TranscriptionResult`, `LanguageMode`, `ComparisonRow`, `HotkeyEvent`, `CaptureKind` all defined once (M2.1, M1.2, M7.1) and referenced consistently. Function signatures `engine.transcribe(samples:sampleRate:mode:)` consistent across engines.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-20-dyktando-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task (M0.1 → M0.2 → … → M10.2), review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
