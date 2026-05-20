import Foundation

final class AudioRingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private let queue = DispatchQueue(label: "dyktando.audio.ringbuffer",
                                      qos: .userInteractive)

    init(capacitySeconds: Int, sampleRate: Int) {
        storage = []
        storage.reserveCapacity(capacitySeconds * sampleRate)
    }

    func append(_ samples: [Float]) {
        queue.sync { storage.append(contentsOf: samples) }
    }

    func drain() -> [Float] {
        queue.sync {
            let out = storage
            storage.removeAll(keepingCapacity: true)
            return out
        }
    }
}
