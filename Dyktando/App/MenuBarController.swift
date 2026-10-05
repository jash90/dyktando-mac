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
        // Ikona w pasku menu: czerwone kółko podczas nagrywania spotkania.
        meetingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
    }

    private var showingRecordingIcon = false

    private func refreshIcon() {
        let recording = MeetingRecorder.shared.isRecording
        guard recording != showingRecordingIcon else { return }
        showingRecordingIcon = recording
        let image = NSImage(systemSymbolName: recording ? "record.circle.fill" : "mic.fill",
                            accessibilityDescription: recording ? "Dyktando — nagrywanie spotkania" : "Dyktando")
        image?.isTemplate = !recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
    }

    private let meetingItem = NSMenuItem(title: "Nagraj spotkanie", action: #selector(AppDelegate.toggleMeetingRecording),
                                         keyEquivalent: "")
    private var meetingTimer: Timer?

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        meetingItem.target = NSApp.delegate
        menu.addItem(meetingItem)
        let list = NSMenuItem(title: "Spotkania…", action: #selector(openMeetings), keyEquivalent: "")
        list.target = self
        menu.addItem(list)
        menu.addItem(.separator())
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
        if menu === statusItem.menu {
            let recorder = MeetingRecorder.shared
            if let started = recorder.startedAt {
                meetingItem.title = "Zatrzymaj nagrywanie (\(AppDelegate.clock(Date().timeIntervalSince(started))))"
            } else {
                meetingItem.title = "Nagraj spotkanie"
            }
            // Postęp przetwarzania (transkrypcja) — klik przerywa.
            menu.items.filter { $0.tag == Self.processingTag }.forEach(menu.removeItem)
            if let job = MeetingProcessing.shared.active {
                let item = NSMenuItem(title: "\(job.status) — \(Int(job.progress * 100))% (kliknij, aby przerwać)",
                                      action: #selector(cancelProcessing(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Self.processingTag
                item.representedObject = job.meetingID
                menu.insertItem(item, at: menu.index(of: meetingItem) + 1)
            }
            return
        }
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

    private static let processingTag = 4242

    @objc private func openMeetings() {
        MeetingsWindowController.shared.show()
    }

    @objc private func cancelProcessing(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        MeetingProcessing.shared.cancel(id)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        Preferences.shared.defaultEngineID = raw
        AppDelegate.shared?.prewarmActiveEngine()
    }
}
