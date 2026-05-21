import AppKit

@MainActor
final class MenuBarController {
    private(set) var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dyktando")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Ustawienia…",
                                  action: #selector(AppDelegate.openSettings),
                                  keyEquivalent: ",")
        settings.target = NSApp.delegate
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Zakończ",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }
}
