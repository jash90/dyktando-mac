import AVFoundation

/// Zapisuje ścieżkę spotkania na dysk na bieżąco: 16 kHz mono, 16-bit PCM w plikach CAF
/// rotowanych co `segmentSeconds` (`mic-000.caf`, `mic-001.caf`…). Nic nie rośnie w pamięci,
/// a awaria aplikacji kosztuje najwyżej bieżący plik (CAF bez domkniętego nagłówka da się odczytać).
/// `append` można wołać z wątku audio — zapis idzie przez własną kolejkę szeregową.
final class SegmentedAudioWriter: @unchecked Sendable {
    let directory: URL
    let prefix: String
    let segmentSamples: Int

    private let queue: DispatchQueue
    private var file: AVAudioFile?
    private var samplesInSegment = 0
    private var segmentIndex = -1
    private var totalSamples = 0
    private var finished = false
    private var writeError: Error?
    private var segmentNames: [String] = []

    init(directory: URL, prefix: String, segmentSeconds: Double = 300) {
        self.directory = directory
        self.prefix = prefix
        self.segmentSamples = max(1, Int(segmentSeconds * MonoResampler.sampleRate))
        self.queue = DispatchQueue(label: "dyktando.meeting.writer.\(prefix)")
    }

    /// Łączna liczba zapisanych próbek (16 kHz).
    var samplesWritten: Int { queue.sync { totalSamples } }
    var secondsWritten: Double { Double(samplesWritten) / MonoResampler.sampleRate }
    var segments: [String] { queue.sync { segmentNames } }
    var lastError: Error? { queue.sync { writeError } }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            guard !finished else { return }
            var offset = 0
            while offset < samples.count {
                do {
                    if file == nil || samplesInSegment >= segmentSamples { try openNextSegment() }
                    let n = min(samples.count - offset, segmentSamples - samplesInSegment)
                    try write(samples[offset ..< offset + n])
                    samplesInSegment += n
                    totalSamples += n
                    offset += n
                } catch {
                    writeError = error
                    NSLog("[Meeting] write %@ failed: %@", prefix, String(describing: error))
                    return
                }
            }
        }
    }

    /// Domyka bieżący plik. Po `finish` dalsze `append` są ignorowane.
    func finish() {
        queue.sync {
            finished = true
            file = nil  // AVAudioFile zapisuje nagłówek przy zwolnieniu
        }
    }

    // MARK: - Pliki

    static func segmentName(prefix: String, index: Int) -> String {
        String(format: "%@-%03d.caf", prefix, index)
    }

    private func openNextSegment() throws {
        file = nil
        segmentIndex += 1
        samplesInSegment = 0
        let name = Self.segmentName(prefix: prefix, index: segmentIndex)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: MonoResampler.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: directory.appendingPathComponent(name),
                               settings: settings,
                               commonFormat: .pcmFormatFloat32,
                               interleaved: false)
        segmentNames.append(name)
    }

    private func write(_ chunk: ArraySlice<Float>) throws {
        guard let file,
              let buf = AVAudioPCMBuffer(pcmFormat: MonoResampler.targetFormat,
                                         frameCapacity: AVAudioFrameCount(chunk.count)) else { return }
        buf.frameLength = AVAudioFrameCount(chunk.count)
        chunk.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: chunk.count)
        }
        try file.write(from: buf)
    }
}

/// Odczyt ścieżki zapisanej przez `SegmentedAudioWriter` jako jednego ciągłego sygnału 16 kHz.
enum SegmentedAudioReader {
    /// Wszystkie pliki ścieżki w kolejności (`mic-000.caf`, `mic-001.caf`…).
    static func segmentURLs(in directory: URL, prefix: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix(prefix + "-") && $0.hasSuffix(".caf") }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Łączna długość ścieżki w próbkach 16 kHz.
    static func totalSamples(in directory: URL, prefix: String) -> Int {
        segmentURLs(in: directory, prefix: prefix).reduce(0) { sum, url in
            sum + ((try? AVAudioFile(forReading: url).length).map(Int.init) ?? 0)
        }
    }

    /// Fragment ścieżki [start, start+count) — czyta tylko potrzebne pliki, nie całość do pamięci.
    static func read(directory: URL, prefix: String, start: Int, count: Int) throws -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(count)
        var fileStart = 0
        for url in segmentURLs(in: directory, prefix: prefix) {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let length = Int(file.length)
            defer { fileStart += length }
            let from = max(start, fileStart), to = min(start + count, fileStart + length)
            guard from < to else { continue }
            file.framePosition = AVAudioFramePosition(from - fileStart)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(to - from)) else { continue }
            try file.read(into: buf, frameCount: AVAudioFrameCount(to - from))
            out.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
            if fileStart + length >= start + count { break }
        }
        return out
    }

    /// Plik ucięty przez awarię (kill -9) ma niedomknięty nagłówek CAF: AVAudioFile go czyta,
    /// ale inne programy (QuickTime, libsndfile) zgłaszają „malformed”. Przepisuje go na domknięty.
    static func repair(_ url: URL) throws {
        let source = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".repair-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: source.fileFormat.settings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk: AVAudioFrameCount = 160_000
            while source.framePosition < source.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk) else { break }
                try source.read(into: buf, frameCount: chunk)
                if buf.frameLength == 0 { break }
                try out.write(from: buf)
            }
        }  // `out` zwolniony = nagłówek domknięty
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Skleja ścieżkę do jednego pliku WAV 16 kHz (wejście dla diaryzacji, która czyta plik z dysku).
    static func exportWAV(directory: URL, prefix: String, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: MonoResampler.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: url)
        let out = try AVAudioFile(forWriting: url, settings: settings,
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        for segment in segmentURLs(in: directory, prefix: prefix) {
            let file = try AVAudioFile(forReading: segment, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk: AVAudioFrameCount = 160_000
            while file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
                try file.read(into: buf, frameCount: chunk)
                if buf.frameLength == 0 { break }
                try out.write(from: buf)
            }
        }
    }
}
