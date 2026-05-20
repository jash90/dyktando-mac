import AppKit
import SwiftUI

@MainActor
final class HUDController {
    let state = HUDState()
    private var window: NSPanel?

    func show(near point: NSPoint) {
        let panel = window ?? makeWindow()
        window = panel
        panel.setFrameOrigin(NSPoint(x: point.x - 60, y: point.y + 24))
        panel.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        return panel
    }
}
