import AppKit
import Foundation

/// System-level actions that don't need an extra app: lock screen, sleep,
/// show desktop, empty trash. The LLM picks which one via the `action` param.
struct SystemSkill: Skill {
    let id = "system_action"
    let description = "wykonaj akcję systemową: lock_screen, sleep, show_desktop, empty_trash"
    let parameters: [SkillParameter] = [
        SkillParameter("action", "lock_screen | sleep | show_desktop | empty_trash")
    ]

    func run(params: [String: String]) async throws -> String {
        let action = try require("action", in: params).lowercased()
        switch action {
        case "lock_screen":
            // Fire-and-forget via shell out to keep things simple and not
            // pull in private SPI for screen locking.
            await runShell(["/usr/bin/pmset", "displaysleepnow"])
            return "🔒 Zablokowano ekran"
        case "sleep":
            await runShell(["/usr/bin/pmset", "sleepnow"])
            return "💤 Uśpiono Mac"
        case "show_desktop":
            await MainActor.run { NSWorkspace.shared.hideOtherApplications() }
            return "🖥 Pokazano biurko"
        case "empty_trash":
            await runShell(["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty the trash"])
            return "🗑 Opróżniono kosz"
        default:
            throw SkillError.invalidParam("action", action)
        }
    }

    private func runShell(_ args: [String]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: args[0])
                task.arguments = Array(args.dropFirst())
                _ = try? task.run()
                task.waitUntilExit()
                cont.resume()
            }
        }
    }
}
