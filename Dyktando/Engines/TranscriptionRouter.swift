import Foundation

struct ComparisonRow: Equatable, Sendable {
    let engineID: EngineID
    let result: TranscriptionResult
}

final class TranscriptionRouter: @unchecked Sendable {
    private let engines: [TranscriptionEngine]

    init(engines: [TranscriptionEngine]) {
        self.engines = engines
    }

    /// Run one engine.
    func route(samples: [Float], sampleRate: Double, mode: LanguageMode,
               using engine: TranscriptionEngine) async throws -> TranscriptionResult {
        try await engine.transcribe(samples: samples, sampleRate: sampleRate, mode: mode)
    }

    /// Run all installed engines in parallel and return rows for each that succeeded.
    func routeAll(samples: [Float], sampleRate: Double, mode: LanguageMode) async -> [ComparisonRow] {
        let installed = engines.filter { $0.isInstalled }
        return await withTaskGroup(of: ComparisonRow?.self) { group in
            for engine in installed {
                let id = engine.id
                group.addTask {
                    do {
                        let r = try await engine.transcribe(samples: samples,
                                                            sampleRate: sampleRate,
                                                            mode: mode)
                        return ComparisonRow(engineID: id, result: r)
                    } catch {
                        print("Engine \(id) failed: \(error)")
                        return nil
                    }
                }
            }
            var rows: [ComparisonRow] = []
            for await row in group {
                if let row { rows.append(row) }
            }
            return rows
        }
    }
}
