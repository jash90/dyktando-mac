import AppKit
import Foundation

/// Launches a macOS application by name (e.g. "Mail", "Safari", "Notion").
/// We resolve the name to a bundle URL via Launch Services; the LLM
/// supplies the user-visible app name and we do the lookup.
struct OpenAppSkill: Skill {
    let id = "open_app"
    let description = "uruchom aplikację na Macu po nazwie (Mail, Safari, Notion, Spotify itp.)"
    let parameters: [SkillParameter] = [
        SkillParameter("name", "nazwa aplikacji widoczna w Finderze")
    ]

    func run(params: [String: String]) async throws -> String {
        let name = try require("name", in: params)
        let url: URL? = await MainActor.run {
            // Try common bundle id patterns first; fall back to name-based search.
            let candidates = [
                "com.apple.\(name.lowercased())",
                "com.\(name.lowercased())",
            ]
            for id in candidates {
                if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u }
            }
            return NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(name).app"))
        }
        guard let url else { throw SkillError.execution("Nie znalazłem aplikacji '\(name)'") }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            Task { @MainActor in
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    cont.resume(returning: "▶ \(name)")
                }
            }
        }
    }
}
