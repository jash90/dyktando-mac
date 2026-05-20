import XCTest
@testable import Dyktando

final class AudioRingBufferTests: XCTestCase {
    func test_appendAndDrain_returnsAllSamples() {
        let buf = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
        let samples: [Float] = (0..<1000).map { Float($0) * 0.001 }

        buf.append(samples)
        let drained = buf.drain()

        XCTAssertEqual(drained.count, 1000)
        XCTAssertEqual(drained.first, 0)
        XCTAssertEqual(drained.last ?? -1, 0.999, accuracy: 1e-5)
    }

    func test_drain_emptiesBuffer() {
        let buf = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
        buf.append([1, 2, 3])
        _ = buf.drain()
        XCTAssertEqual(buf.drain(), [])
    }

    func test_concurrentAppends_areThreadSafe() {
        let buf = AudioRingBuffer(capacitySeconds: 60, sampleRate: 16_000)
        let group = DispatchGroup()
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                buf.append([1, 2, 3, 4, 5])
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(buf.drain().count, 50)
    }
}
