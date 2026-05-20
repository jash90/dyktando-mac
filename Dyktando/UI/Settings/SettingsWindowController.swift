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
        }
        .padding(16)
        .frame(width: 620, height: 460)
    }
}
