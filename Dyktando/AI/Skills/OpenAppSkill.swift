import AppKit
import Foundation

/// Launches a macOS application by user-visible name (e.g. "Mail", "Teams",
/// "VS Code"). The resolver tries three strategies in order:
///   1. A curated map from common spoken names → real bundle ids.
///   2. A filesystem scan of `/Applications`, `~/Applications`, and
///      `/System/Applications` for a `.app` whose name contains the query
///      (case-insensitive). Exact matches win over substring matches.
///   3. A literal `/Applications/<name>.app` fallback as a last resort.
struct OpenAppSkill: Skill {
    let id = "open_app"
    let description = "uruchom aplikację na Macu po nazwie (Mail, Teams, Safari, Notion, Spotify itp.)"
    let parameters: [SkillParameter] = [
        SkillParameter("name", "nazwa aplikacji widoczna w Finderze")
    ]

    func run(params: [String: String]) async throws -> String {
        let raw = try require("name", in: params)
        let url: URL? = await MainActor.run { Self.resolve(name: raw) }
        guard let url else { throw SkillError.execution("Nie znalazłem aplikacji '\(raw)'") }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            Task { @MainActor in
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    cont.resume(returning: "▶ \(url.deletingPathExtension().lastPathComponent)")
                }
            }
        }
    }

    // MARK: - Resolver

    /// Curated lookup. Keys are normalised (lowercased, trimmed) — values are
    /// candidate bundle ids tried in order. Add a row here when a popular app
    /// has a spoken name that wouldn't match its disk filename.
    private static let knownBundleIDs: [String: [String]] = [
        "teams":        ["com.microsoft.teams2", "com.microsoft.teams"],
        "ms teams":     ["com.microsoft.teams2", "com.microsoft.teams"],
        "outlook":      ["com.microsoft.Outlook"],
        "word":         ["com.microsoft.Word"],
        "excel":        ["com.microsoft.Excel"],
        "powerpoint":   ["com.microsoft.PowerPoint"],
        "vs code":      ["com.microsoft.VSCode"],
        "vscode":       ["com.microsoft.VSCode"],
        "code":         ["com.microsoft.VSCode"],
        "cursor":       ["com.todesktop.230313mzl4w4u92"],
        "chrome":       ["com.google.Chrome"],
        "firefox":      ["org.mozilla.firefox"],
        "edge":         ["com.microsoft.edgemac"],
        "slack":        ["com.tinyspeck.slackmacgap"],
        "discord":      ["com.hnc.Discord"],
        "zoom":         ["us.zoom.xos"],
        "spotify":      ["com.spotify.client"],
        "notion":       ["notion.id"],
        "figma":        ["com.figma.Desktop"],
        "telegram":     ["ru.keepcoder.Telegram", "org.telegram.desktop"],
        "whatsapp":     ["WhatsApp", "net.whatsapp.WhatsApp"],
        "signal":       ["org.whispersystems.signal-desktop"],
        "1password":    ["com.1password.1password"],
        "obsidian":     ["md.obsidian"],
        "linear":       ["com.linear"],
        "spark":        ["com.readdle.smartemail-Mac"],
        "mail":         ["com.apple.mail"],
        "safari":       ["com.apple.Safari"],
        "music":        ["com.apple.Music"],
        "podcasty":     ["com.apple.podcasts"],
        "podcasts":     ["com.apple.podcasts"],
        "kalendarz":    ["com.apple.iCal"],
        "calendar":     ["com.apple.iCal"],
        "kontakty":     ["com.apple.AddressBook"],
        "contacts":     ["com.apple.AddressBook"],
        "wiadomości":   ["com.apple.MobileSMS"],
        "messages":     ["com.apple.MobileSMS"],
        "notatki":      ["com.apple.Notes"],
        "notes":        ["com.apple.Notes"],
        "przypomnienia":["com.apple.reminders"],
        "reminders":    ["com.apple.reminders"],
        "terminal":     ["com.apple.Terminal"],
        "finder":       ["com.apple.finder"],
        "ustawienia":   ["com.apple.systempreferences"],
        "settings":     ["com.apple.systempreferences"],
    ]

    static func resolve(name raw: String) -> URL? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "pl_PL"))
        guard !key.isEmpty else { return nil }

        // 1. Curated map
        if let ids = knownBundleIDs[key] {
            for id in ids {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    return url
                }
            }
        }

        // 2. Filesystem scan
        if let url = scanApplicationsFolders(for: key) {
            return url
        }

        // 3. Literal /Applications/<raw>.app
        let literal = URL(fileURLWithPath: "/Applications/\(raw).app")
        if FileManager.default.fileExists(atPath: literal.path) {
            return literal
        }
        return nil
    }

    private static let searchRoots: [URL] = {
        let fm = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
        ]
        if let user = fm.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(user)
        }
        return roots.filter { fm.fileExists(atPath: $0.path) }
    }()

    /// Walks the search roots looking for `.app` bundles whose display name
    /// equals or contains the lowercased needle. Exact matches are returned
    /// before substring matches.
    private static func scanApplicationsFolders(for needle: String) -> URL? {
        let fm = FileManager.default
        var exact: URL?
        var partial: URL?
        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(at: root,
                                                            includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries where entry.pathExtension == "app" {
                let base = entry.deletingPathExtension().lastPathComponent
                    .lowercased(with: Locale(identifier: "pl_PL"))
                if base == needle { return entry }                        // perfect hit
                if exact == nil, base.hasPrefix(needle) { exact = entry }  // prefix
                if partial == nil, base.contains(needle) { partial = entry } // substring
            }
        }
        return exact ?? partial
    }
}
