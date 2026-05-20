import Foundation

@MainActor
final class CommandStore: ObservableObject {
    static let shared = CommandStore()

    @Published private(set) var commands: [Command] = []

    private let fileURL: URL = AppPaths.support.appendingPathComponent("commands.json")
    private let queue = DispatchQueue(label: "Dyktando.CommandStore.io", qos: .utility)

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ command: Command) {
        commands.append(command)
        save()
    }

    func update(_ command: Command) {
        guard let i = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[i] = command
        save()
    }

    func remove(_ id: Command.ID) {
        commands.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Matching

    /// Returns the first enabled command whose trigger matches the given
    /// post-processed transcription. Matching is whole-utterance, lower-cased,
    /// trim, and trailing punctuation stripped (so "otwórz mail." matches a
    /// trigger of "otwórz mail").
    func match(_ text: String) -> Command? {
        let needle = CommandMatcher.normalize(text)
        guard !needle.isEmpty else { return nil }
        return commands.first { cmd in
            cmd.enabled && CommandMatcher.normalize(cmd.trigger) == needle
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            commands = try JSONDecoder().decode([Command].self, from: data)
        } catch {
            NSLog("[Commands] Failed to load %@: %@", fileURL.path, "\(error)")
        }
    }

    private func save() {
        let snapshot = commands
        let url = fileURL
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("[Commands] Failed to save %@: %@", url.path, "\(error)")
            }
        }
    }
}
