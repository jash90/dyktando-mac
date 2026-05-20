import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ capture: AudioCapture, level rms: Float)
    func audioCapture(_ capture: AudioCapture,
                      finishedWith samples: [Float],
                      sampleRate: Double)
}

final class AudioCapture {
    weak var delegate: AudioCaptureDelegate?

    private let engine = AVAudioEngine()
    private let buffer = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
    private var converter: AVAudioConverter?
    private var tapCount: Int = 0

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    func start() throws {
        tapCount = 0
        converter = nil  // recreated lazily in handleTap from the real pcm.format
        let input = engine.inputNode
        let reportedFormat = input.outputFormat(forBus: 0)
        NSLog("[Audio] start() called, inputNode.outputFormat: sr=%f ch=%d",
              reportedFormat.sampleRate, reportedFormat.channelCount)

        guard reportedFormat.channelCount > 0, reportedFormat.sampleRate > 0 else {
            throw NSError(
                domain: "Dyktando.AudioCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Mikrofon zwraca format 0 kanałów / 0 Hz — uprawnienie nie zostało przyznane lub brak urządzenia."])
        }

        // Pass `format: nil` so the engine installs the tap with the bus's
        // actual hardware-driven format. Querying `outputFormat(forBus:)` can
        // return a stale/internal value (seen: 24 kHz reported, 48 kHz at HW),
        // which makes `installTap(format:)` raise an uncatchable NSException.
        input.installTap(onBus: 0,
                         bufferSize: 1024,
                         format: nil) { [weak self] pcm, _ in
            self?.handleTap(pcm)
        }
        engine.prepare()
        try engine.start()
        NSLog("[Audio] engine started, isRunning=%@", engine.isRunning ? "true" : "false")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = buffer.drain()
        NSLog("[Audio] stop() called, taps=%d captured %d samples (%.2fs)", tapCount, samples.count, Double(samples.count) / targetFormat.sampleRate)
        delegate?.audioCapture(self,
                               finishedWith: samples,
                               sampleRate: targetFormat.sampleRate)
    }

    private func handleTap(_ pcm: AVAudioPCMBuffer) {
        tapCount &+= 1
        NSLog("[Audio] tap #%d: frames=%d sr=%f ch=%d",
              tapCount, pcm.frameLength, pcm.format.sampleRate, pcm.format.channelCount)

        if converter == nil {
            converter = AVAudioConverter(from: pcm.format, to: targetFormat)
            NSLog("[Audio] converter created from real tap format: %f Hz → %f Hz",
                  pcm.format.sampleRate, targetFormat.sampleRate)
        }
        guard let converter else { NSLog("[Audio] tap: no converter, skipping"); return }

        // Assumes input sample rate >= 16 kHz (true for all macOS built-in/USB mics).
        // At ratio ≤ 1, AVAudioConverter completes in a single input buffer call.
        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(pcm.frameLength) * ratio)
        guard outFrames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: outFrames) else {
            NSLog("[Audio] tap: outFrames=%d, skip", outFrames)
            return
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                // Crucial: signal "no more right now" rather than end-of-stream.
                // Otherwise AVAudioConverter enters terminal state after the first
                // tap callback and produces zero output for every subsequent call.
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return pcm
        }

        guard error == nil,
              let channelData = out.floatChannelData?[0] else { return }

        let count = Int(out.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
        buffer.append(samples)

        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumSquares / Float(max(count, 1)))
        delegate?.audioCapture(self, level: rms)
    }
}
