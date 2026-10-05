import XCTest
@testable import Dyktando

final class MLXSidecarEngineTests: XCTestCase {
    @MainActor
    func test_registry_hasAllFourEngines() {
        let registry = EngineRegistry()
        for id in EngineID.allCases {
            XCTAssertNotNil(registry.engine(for: id), "brak silnika \(id.rawValue)")
        }
        XCTAssertEqual(registry.engine(for: .canary1bV2)?.displayName, "Canary-1b-v2")
        XCTAssertEqual(registry.engine(for: .whisperLargeV3Turbo)?.displayName, "Whisper large-v3-turbo")
        XCTAssertEqual(registry.engine(for: .whisperLargeV3)?.displayName, "Whisper large-v3")
    }

    func test_resolve_fallsBackToParakeet() {
        XCTAssertEqual(EngineRegistry.resolve(preferred: "nieznany", isInstalled: { _ in true }), .parakeetTDTv3)
        XCTAssertEqual(EngineRegistry.resolve(preferred: "canary-1b-v2", isInstalled: { _ in false }), .parakeetTDTv3)
        XCTAssertEqual(EngineRegistry.resolve(preferred: "canary-1b-v2", isInstalled: { $0 == .canary1bV2 }), .canary1bV2)
        XCTAssertEqual(EngineRegistry.resolve(preferred: "whisper-large-v3", isInstalled: { _ in true }), .whisperLargeV3)
    }

    func test_languageCode() {
        let pl = Locale(identifier: "pl-PL")
        let en = Locale(identifier: "en-US")
        XCTAssertEqual(MLXSidecarEngine.languageCode(for: .single(pl), autoDetects: true), "pl")
        XCTAssertEqual(MLXSidecarEngine.languageCode(for: .mixed(primary: en, allowed: [pl, en]), autoDetects: true), "en")
        XCTAssertNil(MLXSidecarEngine.languageCode(for: .multilingualAuto([pl, en]), autoDetects: true))
        // Canary nie wykrywa języka sam — wybieramy polski, jeśli jest na liście.
        XCTAssertEqual(MLXSidecarEngine.languageCode(for: .multilingualAuto([en, pl]), autoDetects: false), "pl")
    }

    func test_encodeSamples_isFloat32LittleEndian() throws {
        let samples: [Float] = [0, 0.5, -1, 0.25]
        let data = try XCTUnwrap(Data(base64Encoded: MLXSidecar.encodeSamples(samples)))
        XCTAssertEqual(data.count, samples.count * 4)
        let decoded = data.withUnsafeBytes { raw in
            (0..<samples.count).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
        XCTAssertEqual(decoded, samples)
    }

    func test_resample_changesLengthProportionally() {
        let x = [Float](repeating: 0.1, count: 48_000)
        XCTAssertEqual(MLXSidecarEngine.resample(x, from: 48_000, to: 16_000).count, 16_000)
        XCTAssertEqual(MLXSidecarEngine.resample(x, from: 16_000, to: 16_000).count, 48_000)
    }

    @MainActor
    func test_menuBar_hasModelSubmenu() {
        let controller = MenuBarController()
        let model = controller.statusItem.menu?.items.first { $0.title == "Model" }
        XCTAssertNotNil(model?.submenu)
    }

    /// Integracja — tylko gdy Whisper turbo jest zainstalowany przez aplikację (serwer MLX gotowy).
    func test_transcribePolishFixture_whisperTurbo() async throws {
        let engine = MLXSidecarEngine(MLXSidecarEngine.whisperTurbo)
        guard engine.isInstalled else {
            throw XCTSkip("Whisper large-v3-turbo (MLX) nie jest zainstalowany w aplikacji")
        }
        let result = try await engine.transcribe(samples: try TestFixtures.polishThreeSeconds(),
                                                 sampleRate: 16_000,
                                                 mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertFalse(result.text.isEmpty)
        print("Whisper turbo (MLX) transcribed: '\(result.text)'")
    }

    /// Pełna ścieżka instalacji przez kod aplikacji (zasoby z paczki → uv sync → /prepare) i transkrypcja.
    /// Opt-in, bo pobiera modele: TEST_RUNNER_DYKTANDO_MLX_INSTALL=1 make test
    func test_installAndTranscribe_allMLXEngines() async throws {
        guard ProcessInfo.processInfo.environment["DYKTANDO_MLX_INSTALL"] == "1" else {
            throw XCTSkip("ustaw TEST_RUNNER_DYKTANDO_MLX_INSTALL=1, żeby zainstalować modele MLX")
        }
        let samples = try TestFixtures.polishThreeSeconds()
        for variant in [MLXSidecarEngine.canary, MLXSidecarEngine.whisperTurbo, MLXSidecarEngine.whisperLarge] {
            let engine = MLXSidecarEngine(variant)
            let start = Date()
            try await engine.install { _ in }
            XCTAssertTrue(engine.isInstalled, variant.displayName)
            let result = try await engine.transcribe(samples: samples, sampleRate: 16_000,
                                                     mode: .single(Locale(identifier: "pl-PL")))
            XCTAssertFalse(result.text.isEmpty, variant.displayName)
            print("[\(variant.displayName)] install+transcribe \(Int(Date().timeIntervalSince(start)))s, inference \(result.inferenceMillis) ms: '\(result.text)'")
        }
    }
}
