import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("defaultEngineID")
    var defaultEngineID: String = EngineID.parakeetTDTv3.rawValue

    @AppStorage("languageModeRaw")
    var languageModeRaw: String = "single:pl-PL"

    /// UID urządzenia wejściowego z Core Audio; pusty = domyślne wejście systemu (Ustawienia → Audio).
    @AppStorage(AudioDevices.preferenceKey)
    var inputDeviceUID: String = ""

    @AppStorage("hudEnabled")
    var hudEnabled: Bool = true

    @AppStorage("launchAtLogin")
    var launchAtLogin: Bool = false

    private init() {}
}
