import AppKit
import SwiftUI

@MainActor
final class CommandsWindowController: NSWindowController {
    static let shared = CommandsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Dyktando — Akcje"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 420)
        super.init(window: window)
        window.contentView = NSHostingView(rootView: CommandsView())
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
