import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk",
                                 default: .init(.f5))
    static let toggleDictation = Self("toggleDictation",
                                      default: .init(.space, modifiers: [.control, .option]))
    static let switchModel = Self("switchModel",
                                  default: .init(.m, modifiers: [.control, .option]))
    static let comparisonMode = Self("comparisonMode",
                                     default: .init(.c, modifiers: [.control, .option]))
    static let openSettings = Self("openSettings",
                                   default: .init(.comma, modifiers: [.control, .option]))
}
