import Foundation

actor ComparisonStats {
    struct Entry: Codable {
        let timestamp: Date
        let chosen: EngineID
        let language: String
    }

    struct Nudge {
        let winner: EngineID
        let winRate: Double
    }

    private let url: URL
    private var entries: [Entry] = []

    init(url: URL) {
        self.url = url
        loadFromDisk()
    }

    init() {
        self.url = AppPaths.support.appendingPathComponent("comparison-stats.json")
        loadFromDisk()
    }

    func record(chosen: EngineID, language: Locale) {
        entries.append(Entry(
            timestamp: Date(),
            chosen: chosen,
            language: language.identifier))
        persist()
    }

    func nudgeIfApplicable(for language: Locale) -> Nudge? {
        let recent = entries
            .filter { $0.language == language.identifier }
            .suffix(10)
        guard recent.count >= 10 else { return nil }
        let counts = Dictionary(grouping: recent, by: \.chosen).mapValues(\.count)
        guard let (winner, count) = counts.max(by: { $0.value < $1.value }) else { return nil }
        let rate = Double(count) / 10.0
        return rate >= 0.7 ? Nudge(winner: winner, winRate: rate) : nil
    }

    func allEntries() -> [Entry] { entries }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
