import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Dyktando — Ustawienia"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsRoot())
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsRoot: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
            ModelsTab()
                .tabItem { Label("Modele", systemImage: "cpu") }
            LanguageTab()
                .tabItem { Label("Język", systemImage: "globe") }
            ShortcutsTab()
                .tabItem { Label("Skróty", systemImage: "keyboard") }
            AudioTab()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            PrivacyTab()
                .tabItem { Label("Prywatność", systemImage: "lock.shield") }
        }
        .padding(16)
        .frame(minWidth: 720, idealWidth: 720, minHeight: 520, idealHeight: 520)
    }
}
