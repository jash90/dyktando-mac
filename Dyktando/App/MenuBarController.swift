import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem
    private let modelMenu = NSMenu(title: "Model")

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dyktando")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let model = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelMenu.delegate = self
        model.submenu = modelMenu
        menu.addItem(model)
        menu.addItem(.separator())
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

    /// Lista modeli budowana przy każdym otwarciu — stan instalacji mógł się zmienić.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === modelMenu else { return }
        menu.removeAllItems()
        let registry = EngineRegistry.shared
        let active = registry.active(prefs: Preferences.shared).id
        for id in EngineID.allCases {
            guard let engine = registry.engine(for: id) else { continue }
            let title = engine.isInstalled ? engine.displayName : "\(engine.displayName) (niezainstalowany)"
            let item = NSMenuItem(title: title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id.rawValue
            item.state = id == active ? .on : .off
            item.isEnabled = engine.isInstalled
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "Zarządzaj modelami…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        manage.target = NSApp.delegate
        menu.addItem(manage)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        Preferences.shared.defaultEngineID = raw
        AppDelegate.shared?.prewarmActiveEngine()
    }
}
