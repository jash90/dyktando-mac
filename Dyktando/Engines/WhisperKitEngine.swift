import Foundation
import AVFoundation
import WhisperKit

// Disambiguate from WhisperKit's own TranscriptionResult class.
private typealias EngineResult = Dyktando.TranscriptionResult

final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    enum Variant: String, CaseIterable {
        case largeV3Turbo = "openai_whisper-large-v3-turbo"
        case largeV3 = "openai_whisper-large-v3"

        var engineID: EngineID {
            switch self {
            case .largeV3Turbo: return .whisperLargeV3Turbo
            case .largeV3: return .whisperLargeV3
            }
        }

        var displayName: String {
            switch self {
            case .largeV3Turbo: return "Whisper large-v3-turbo"
            case .largeV3: return "Whisper large-v3"
            }
        }
    }

    let id: EngineID
    let displayName: String
    let supportedLanguages: Set<Locale>
    private let variant: Variant
    private var kit: WhisperKit?
    private let modelDir: URL

    init(variant: Variant) {
        self.variant = variant
        self.id = variant.engineID
        self.displayName = variant.displayName
        self.modelDir = AppPaths.support
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(variant.engineID.rawValue, isDirectory: true)
        // Whisper supports ~100 languages. We expose the core set we care about.
        self.supportedLanguages = Set([
            "pl", "en", "de", "fr", "es", "it", "nl", "pt", "cs", "sk",
            "hu", "ro", "bg", "hr", "da", "fi", "el", "et", "lv", "lt",
            "ru", "uk", "sl", "sv"
        ].map(Locale.init(identifier:)))
    }

    var isInstalled: Bool {
        // Heuristic: model dir exists and has at least one .mlmodelc subfolder.
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: modelDir,
                                                         includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { $0.pathExtension == "mlmodelc" }
            || contents.contains { $0.lastPathComponent.hasSuffix(".mlmodelc") }
            || !contents.isEmpty
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let config = WhisperKitConfig(
            model: variant.rawValue,
            modelFolder: modelDir.path,
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: true
        )
        kit = try await WhisperKit(config)
        progress(1)
    }

    func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: modelDir.path) {
            try fm.removeItem(at: modelDir)
        }
        kit = nil
    }

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> Dyktando.TranscriptionResult {
        if kit == nil {
            try await install { _ in }
        }
        guard let kit else { throw EngineError.notInstalled }

        let start = Date()
        let options = DecodingOptions(
            task: .transcribe,
            language: languageHint(for: mode)
        )

        // transcribe(audioArray:decodeOptions:) returns [TranscriptionResult] (WhisperKit's type).
        // We rely on type inference here to avoid collision with Dyktando.TranscriptionResult.
        let whisperResults = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )
        let text = whisperResults
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lang = options.language.map(Locale.init(identifier:)) ?? Locale(identifier: "pl")
        return EngineResult(
            text: text,
            language: lang,
            inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
            confidence: nil
        )
    }

    private func languageHint(for mode: LanguageMode) -> String? {
        switch mode {
        case .single(let l):
            return String(l.identifier.prefix(2))
        case .multilingualAuto, .mixed:
            return nil // Let Whisper auto-detect (required for code-switching).
        }
    }
}
