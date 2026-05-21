import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("defaultEngineID")
    var defaultEngineID: String = EngineID.parakeetTDTv3.rawValue

    @AppStorage("languageModeRaw")
    var languageModeRaw: String = "single:pl-PL"

    @AppStorage("hudEnabled")
    var hudEnabled: Bool = true

    @AppStorage("launchAtLogin")
    var launchAtLogin: Bool = false

    private init() {}
}
