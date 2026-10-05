import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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

/// Sekcje ustawień w pasku bocznym (jak Ustawienia systemowe) — `TabView` przy 8 zakładkach
/// nie mieścił się w pasku okna i macOS chował wszystkie pod przyciskiem „>>”.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, models, language, shortcuts, audio, meetings, ai, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   return "Ogólne"
        case .models:    return "Modele"
        case .language:  return "Język"
        case .shortcuts: return "Skróty"
        case .audio:     return "Audio"
        case .meetings:  return "Spotkania"
        case .ai:        return "AI"
        case .privacy:   return "Prywatność"
        }
    }

    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .models:    return "cpu"
        case .language:  return "globe"
        case .shortcuts: return "keyboard"
        case .audio:     return "speaker.wave.2"
        case .meetings:  return "person.2.wave.2"
        case .ai:        return "sparkles"
        case .privacy:   return "lock.shield"
        }
    }
}

struct SettingsRoot: View {
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general:   GeneralTab()
                case .models:    ModelsTab()
                case .language:  LanguageTab()
                case .shortcuts: ShortcutsTab()
                case .audio:     AudioTab()
                case .meetings:  MeetingsTab()
                case .ai:        AITab()
                case .privacy:   PrivacyTab()
                }
            }
            .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 600, idealHeight: 620)
    }
}
