import AppKit
import CoreAudio
import SwiftUI

/// Czysta logika podpowiedzi „Wykryto spotkanie — nagrać?” (testowana bez Core Audio).
struct MeetingDetectionLogic {
    /// Aplikacje do rozmów i przeglądarki (Meet, Teams w przeglądarce…). Dopasowanie po prefiksie,
    /// bo przeglądarki używają mikrofonu z procesów pomocniczych (`com.google.Chrome.helper`).
    static let meetingApps = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark", "com.tinyspeck.slackmacgap", "com.apple.FaceTime", "com.hnc.Discord",
        "com.google.Chrome", "com.apple.Safari", "com.apple.WebKit", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    private(set) var handled: Set<String> = []  // aplikacje, o które już zapytaliśmy w tej „sesji” mikrofonu

    static func matchingApp(_ bundleID: String) -> String? {
        meetingApps.first { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// `activeBundleIDs` — procesy używające teraz mikrofonu. Zwraca aplikację, o którą zapytać, albo nil.
    mutating func update(activeBundleIDs: [String], isRecording: Bool, enabled: Bool) -> String? {
        let active = Set(activeBundleIDs.compactMap(Self.matchingApp))
        handled.formIntersection(active)  // aplikacja przestała używać mikrofonu → następna rozmowa znów zapyta
        guard enabled, !isRecording else {
            handled.formUnion(active)     // nie pytaj o rozmowę, która już trwa w momencie startu/końca nagrywania
            return nil
        }
        guard let app = active.subtracting(handled).sorted().first else { return nil }
        handled.insert(app)
        return app
    }
}

/// Co 5 s sprawdza, które procesy używają mikrofonu (macOS 14.2+), i pokazuje podpowiedź.
@MainActor
final class MeetingDetector {
    static let shared = MeetingDetector()
    private var logic = MeetingDetectionLogic()
    private var timer: Timer?
    private var panel: NSPanel?

    func start() {
        guard #available(macOS 14.2, *) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard #available(macOS 14.2, *) else { return }
        let active = Self.processesUsingMicrophone().filter { $0 != Bundle.main.bundleIdentifier }
        if let app = logic.update(activeBundleIDs: active, isRecording: MeetingRecorder.shared.isRecording,
                                  enabled: Preferences.shared.meetingDetectionPrompt) {
            showPrompt(appName: Self.displayName(for: app))
        }
    }

    // MARK: - Panel

    private func showPrompt(appName: String) {
        panel?.close()
        let view = MeetingPromptView(appName: appName,
                                     onRecord: { [weak self] in
                                         self?.panel?.close()
                                         (NSApp.delegate as? AppDelegate)?.startMeetingRecording()
                                     },
                                     onDismiss: { [weak self] in self?.panel?.close() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 96),
                            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 380, y: screen.maxY - 120))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak panel] in panel?.close() }
    }

    /// Procesy pomocnicze bez własnej aplikacji (mikrofon w Safari idzie przez WebKit).
    static let displayAliases = ["com.apple.WebKit": "com.apple.Safari"]

    static func displayName(for bundleID: String) -> String {
        let bundleID = displayAliases[bundleID] ?? bundleID
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }

    // MARK: - Core Audio

    @available(macOS 14.2, *)
    static func processesUsingMicrophone() -> [String] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.compactMap { object in
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &runAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { return nil }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)
            let status = withUnsafeMutablePointer(to: &bundle) {
                AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, $0)
            }
            guard status == noErr, let bundle else { return nil }
            return bundle.takeRetainedValue() as String
        }
    }
}

private struct MeetingPromptView: View {
    let appName: String
    let onRecord: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle").font(.title).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 6) {
                Text("Wykryto spotkanie w \(appName)").font(.headline)
                Text("Nagrać je w Dyktando? Pamiętaj, by poinformować rozmówców.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Nagraj", action: onRecord).keyboardShortcut(.defaultAction)
                    Button("Nie teraz", action: onDismiss)
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }
}
