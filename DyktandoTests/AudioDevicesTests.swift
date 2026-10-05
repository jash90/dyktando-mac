import XCTest
@testable import Dyktando

final class AudioDevicesTests: XCTestCase {
    func test_inputDevices_haveInputChannelsAndUniqueUIDs() throws {
        let devices = AudioDevices.inputDevices()
        guard !devices.isEmpty else { throw XCTSkip("brak urządzeń wejściowych (CI)") }
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
        for d in devices {
            XCTAssertGreaterThan(AudioDevices.inputChannelCount(d.id), 0, d.name)
            XCTAssertFalse(d.name.isEmpty)
        }
        print("Wejścia audio: \(devices.map(\.name))")
    }

    func test_selectedDevice_emptyOrUnknownUID_meansSystemDefault() {
        let defaults = UserDefaults(suiteName: "AudioDevicesTests")!
        defaults.removePersistentDomain(forName: "AudioDevicesTests")
        XCTAssertNil(AudioDevices.selectedDevice(defaults: defaults))
        defaults.set("nie-ma-takiego-urzadzenia", forKey: AudioDevices.preferenceKey)
        XCTAssertNil(AudioDevices.selectedDevice(defaults: defaults))
    }

    func test_selectedDevice_findsConnectedDeviceByUID() throws {
        guard let first = AudioDevices.inputDevices().first else { throw XCTSkip("brak urządzeń wejściowych (CI)") }
        let defaults = UserDefaults(suiteName: "AudioDevicesTests2")!
        defaults.set(first.uid, forKey: AudioDevices.preferenceKey)
        XCTAssertEqual(AudioDevices.selectedDevice(defaults: defaults), first)
    }
}
