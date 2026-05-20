import AppKit
import SwiftUI

@MainActor
final class HUDController {
    let state = HUDState()
    private var panel: DraggablePanel?
    private var moveObserver: NSObjectProtocol?

    private static let originXKey = "hudOriginX"
    private static let originYKey = "hudOriginY"

    func show() {
        let p = panel ?? makeWindow()
        panel = p
        p.setFrameOrigin(savedOrigin() ?? defaultOrigin(for: p))
        p.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    /// Briefly nudges the HUD to the cursor — kept for the comparison-mode flow
    /// that wants to draw the user's attention. The new persistent HUD ignores
    /// this in regular use; callers should generally just call `show()`.
    func showNear(_ point: NSPoint) {
        let p = panel ?? makeWindow()
        panel = p
        if savedOrigin() == nil {
            p.setFrameOrigin(NSPoint(x: point.x - p.frame.width / 2, y: point.y + 24))
        }
        p.orderFrontRegardless()
    }

    private func makeWindow() -> DraggablePanel {
        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: HUDView(state: state))

        // Persist new position whenever the user drops the HUD somewhere.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main) { [weak self] _ in
                Task { @MainActor in self?.persistOrigin() }
            }
        return panel
    }

    private func persistOrigin() {
        guard let panel else { return }
        let origin = panel.frame.origin
        let d = UserDefaults.standard
        d.set(Double(origin.x), forKey: Self.originXKey)
        d.set(Double(origin.y), forKey: Self.originYKey)
    }

    private func savedOrigin() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.originXKey) != nil,
              d.object(forKey: Self.originYKey) != nil else { return nil }
        let p = NSPoint(x: d.double(forKey: Self.originXKey),
                        y: d.double(forKey: Self.originYKey))
        return clamp(p)
    }

    /// Keeps the HUD inside *some* visible screen — protects against a saved
    /// position that's off-screen after disconnecting an external display.
    private func clamp(_ p: NSPoint) -> NSPoint {
        let frame = NSRect(origin: p, size: panel?.frame.size ?? NSSize(width: 120, height: 36))
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return p
        }
        guard let main = NSScreen.main else { return p }
        return NSPoint(x: main.visibleFrame.midX - frame.width / 2,
                       y: main.visibleFrame.minY + 80)
    }

    private func defaultOrigin(for panel: NSPanel) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let v = screen.visibleFrame
        return NSPoint(x: v.midX - panel.frame.width / 2,
                       y: v.minY + 80)
    }
}

/// Borderless panels don't drag by default even with
/// `isMovableByWindowBackground = true` when their content is an opaque
/// SwiftUI hierarchy. Routing `mouseDown` to `performDrag` makes every
/// pixel a drag handle.
final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        self.performDrag(with: event)
    }
}
