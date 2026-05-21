import Foundation
import AVFoundation
import WhisperKit

// Disambiguate from WhisperKit's own TranscriptionResult class.
private typealias EngineResult = Dyktando.TranscriptionResult

/// Tiny reference wrapper used to thread mutable state through `@Sendable`
/// progress callbacks without `@MainActor` ping-pong on every tick.
private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    enum Variant: String, CaseIterable {
        // `rawValue` is the canonical short name WhisperKit expects in
        // `WhisperKit.download(variant:)` and `WhisperKitConfig(model:)`.
        // The download glob is built as `*openai*<variant>/*` and matched
        // against repo paths like `openai_whisper-large-v3-turbo/...`, so
        // the variant itself must NOT contain the `whisper-` prefix.
        // The turbo folder in argmaxinc/whisperkit-coreml is
        // `openai_whisper-large-v3_turbo` (underscore before "turbo", not
        // the hyphen most docs show), so the variant string must use
        // an underscore to make the `*openai*<variant>/*` glob match.
        case largeV3Turbo = "large-v3_turbo"
        case largeV3 = "large-v3"

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

        /// Subdirectory created by WhisperKit under `downloadBase`.
        /// HuggingFace stores the models under `openai_whisper-<variant>/`.
        var folderName: String { "openai_whisper-\(rawValue)" }
    }

    let id: EngineID
    let displayName: String
    let supportedLanguages: Set<Locale>
    private let variant: Variant
    private var kit: WhisperKit?

    /// Parent directory we hand to `WhisperKit.download(downloadBase:)`. The
    /// library appends `<variant.rawValue>/` underneath, so the final
    /// per-model folder is `modelsRoot/<variant.rawValue>/`.
    private let modelsRoot: URL
    /// Actual location of this variant's `.mlmodelc` files.
    private let modelFolder: URL

    init(variant: Variant) {
        self.variant = variant
        self.id = variant.engineID
        self.displayName = variant.displayName
        self.modelsRoot = AppPaths.support
            .appendingPathComponent("Models", isDirectory: true)
        self.modelFolder = modelsRoot
            .appendingPathComponent(variant.folderName, isDirectory: true)
        // Whisper supports ~100 languages. We expose the core set we care about.
        self.supportedLanguages = Set([
            "pl", "en", "de", "fr", "es", "it", "nl", "pt", "cs", "sk",
            "hu", "ro", "bg", "hr", "da", "fi", "el", "et", "lv", "lt",
            "ru", "uk", "sl", "sv"
        ].map(Locale.init(identifier:)))
    }

    var isInstalled: Bool { resolvedModelFolder != nil }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        // The total install is split into two visible phases for the user:
        //   • 0 → 0.90  → download (network + unpack into modelFolder)
        //   • 0.90 → 1  → load into WhisperKit (prewarm CoreML graphs)
        // Progress callbacks from WhisperKit only cover the download leg, so
        // we cap them at 0.90 and bump to 1.0 after the engine finishes
        // prewarming.
        let startedAt = Date()
        NSLog("[Whisper] install '%@' begin", variant.rawValue)

        let lastLoggedFraction = SendableBox(0.0)
        let lastLoggedAt = SendableBox(Date())

        let downloaded = try await WhisperKit.download(
            variant: variant.rawValue,
            downloadBase: modelsRoot,
            useBackgroundSession: false,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { p in
                let f = p.fractionCompleted
                // Log every 5 % or every 3 s, whichever comes first, so the
                // unified log shows whether we're stalled or just slow.
                let prev = lastLoggedFraction.value
                let elapsed = Date().timeIntervalSince(lastLoggedAt.value)
                if f - prev >= 0.05 || elapsed >= 3.0 || f >= 1.0 {
                    NSLog("[Whisper] download %@: %.1f%% (completed=%lld / %lld bytes, desc=%@)",
                          self.variant.rawValue, f * 100,
                          p.completedUnitCount, p.totalUnitCount,
                          p.localizedDescription ?? "<nil>")
                    lastLoggedFraction.value = f
                    lastLoggedAt.value = Date()
                }
                progress(f * 0.90)
            }
        )
        NSLog("[Whisper] download finished in %.1fs → %@",
              Date().timeIntervalSince(startedAt), downloaded.path)

        // Snapshot what landed on disk so we can see partial downloads.
        if let entries = try? FileManager.default.contentsOfDirectory(
            atPath: downloaded.path) {
            NSLog("[Whisper] downloaded folder contains %d entries: %@",
                  entries.count, entries.joined(separator: ", "))
        }

        UserDefaults.standard.set(downloaded.path,
                                  forKey: Self.modelPathKey(for: variant))

        // We deliberately do NOT call `WhisperKit(config)` here. Prewarming
        // compiles 1.5–2 GB of CoreML/ANE state which on some Macs can hang
        // the install task for many minutes with no progress visible. The
        // engine is marked installed once the bytes land on disk; the
        // actual load happens lazily on first `transcribe(...)`.
        NSLog("[Whisper] install '%@' done (download) in %.1fs — prewarm deferred",
              variant.rawValue, Date().timeIntervalSince(startedAt))
        progress(1)
    }

    /// Resolves where this variant's model bundle actually lives.
    ///
    /// WhisperKit uses HubApi under the hood, which creates a deep tree like
    /// `<downloadBase>/models/<repo>/<variant>/` — not directly under
    /// `downloadBase`. We can't assume the layout, so we do a bounded
    /// recursive scan for the unique `MelSpectrogram.mlmodelc` sentinel
    /// inside a folder whose name matches this variant.
    private var resolvedModelFolder: URL? {
        let fm = FileManager.default
        let key = Self.modelPathKey(for: variant)

        // 1. Trust the persisted path if the model is still there.
        if let saved = UserDefaults.standard.string(forKey: key) {
            let mel = URL(fileURLWithPath: saved)
                .appendingPathComponent("MelSpectrogram.mlmodelc")
            if fm.fileExists(atPath: mel.path) {
                return URL(fileURLWithPath: saved)
            }
        }

        // 2. Recursive scan from modelsRoot.
        guard let enumerator = fm.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let variantName = variant.rawValue
        for case let url as URL in enumerator {
            // HubApi keeps a partials directory under .cache/huggingface that
            // satisfies the MelSpectrogram check but lacks the rest of the
            // model — skip it so we don't claim a half-installed model is
            // ready.
            if url.path.contains("/.cache/") { continue }
            guard url.lastPathComponent.contains(variantName) else { continue }
            let mel = url.appendingPathComponent("MelSpectrogram.mlmodelc")
            let audio = url.appendingPathComponent("AudioEncoder.mlmodelc")
            let text = url.appendingPathComponent("TextDecoder.mlmodelc")
            if fm.fileExists(atPath: mel.path),
               fm.fileExists(atPath: audio.path),
               fm.fileExists(atPath: text.path) {
                UserDefaults.standard.set(url.path, forKey: key)
                return url
            }
        }
        return nil
    }

    private static func modelPathKey(for variant: Variant) -> String {
        "WhisperKit.modelPath.\(variant.rawValue)"
    }

    /// Loads the model into memory (CoreML + ANE compilation) ahead of any
    /// `transcribe()` call so the first dictation isn't blocked by a
    /// multi-second cold start. Safe to call multiple times — becomes a
    /// no-op once `kit != nil`.
    func prewarm() async {
        if kit != nil { return }
        guard let folder = resolvedModelFolder else { return }
        do {
            NSLog("[Whisper] prewarm '%@' begin", variant.rawValue)
            let start = Date()
            let config = WhisperKitConfig(
                model: variant.rawValue,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: false
            )
            kit = try await WhisperKit(config)
            NSLog("[Whisper] prewarm '%@' done in %.1fs",
                  variant.rawValue, Date().timeIntervalSince(start))
        } catch {
            NSLog("[Whisper] prewarm '%@' failed: %@",
                  variant.rawValue, "\(error)")
        }
    }

    func uninstall() throws {
        let fm = FileManager.default
        // Remove every directory under modelsRoot whose name matches the
        // variant — covers both the resolved final folder and the cache /
        // partials directory HubApi leaves behind.
        if let enumerator = fm.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            var toRemove: [URL] = []
            for case let url as URL in enumerator
            where url.lastPathComponent == variant.folderName
                || url.lastPathComponent == "openai_whisper-\(variant.rawValue)"
                || url.lastPathComponent.contains(variant.rawValue) {
                toRemove.append(url)
            }
            for url in toRemove where fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.modelPathKey(for: variant))
        kit = nil
    }

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> Dyktando.TranscriptionResult {
        if kit == nil {
            // Lazy-load from disk if the model is already downloaded — don't
            // trigger a fresh download from the transcription path.
            guard let folder = resolvedModelFolder else {
                throw EngineError.notInstalled
            }
            let config = WhisperKitConfig(
                model: variant.rawValue,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: false
            )
            kit = try await WhisperKit(config)
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
