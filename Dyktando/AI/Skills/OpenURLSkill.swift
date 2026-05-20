import AppKit
import Foundation

/// Opens an arbitrary URL (http/https/file/custom scheme) in the default
/// handler. Useful when the user names a destination directly: "otwórz
/// github" → router fills `https://github.com`.
struct OpenURLSkill: Skill {
    let id = "open_url"
    let description = "otwórz dowolny URL (http/https) w domyślnej przeglądarce"
    let parameters: [SkillParameter] = [
        SkillParameter("url", "pełny URL, np. https://github.com")
    ]

    func run(params: [String: String]) async throws -> String {
        let raw = try require("url", in: params)
        guard let url = URL(string: raw), url.scheme != nil else {
            throw SkillError.invalidParam("url", raw)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SkillError.execution("Nie udało się otworzyć URL") }
        return url.host.map { "🌐 \($0)" } ?? "🌐 \(raw)"
    }
}
