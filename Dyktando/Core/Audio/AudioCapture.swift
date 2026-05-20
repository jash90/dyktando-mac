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

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0,
                         bufferSize: 1024,
                         format: inputFormat) { [weak self] pcm, _ in
            self?.handleTap(pcm)
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = buffer.drain()
        delegate?.audioCapture(self,
                               finishedWith: samples,
                               sampleRate: targetFormat.sampleRate)
    }

    private func handleTap(_ pcm: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(pcm.frameLength) * ratio)
        guard outFrames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: outFrames) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
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
