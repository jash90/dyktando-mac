import SwiftUI

struct LanguageTab: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var selection: ModeKind = .mixed

    enum ModeKind: String, CaseIterable, Hashable {
        case single = "Pojedynczy"
        case auto = "Multi auto-detect"
        case mixed = "Mixed PL+EN"
    }

    var body: some View {
        Form {
            Section {
                Picker("Tryb", selection: $selection) {
                    ForEach(ModeKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selection) { _, new in apply(new) }
            } header: {
                Text("Tryb języka")
            } footer: {
                Text(description(for: selection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear { selection = currentSelection() }
    }

    private func description(for kind: ModeKind) -> String {
        switch kind {
        case .single: return "Wymuszamy język polski. Słowa angielskie będą zapisane fonetycznie."
        case .auto:   return "Silnik wybiera język per wypowiedź. Bez mieszania w jednym zdaniu."
        case .mixed:  return "Code-switching: silnik utrzymuje angielskie terminy po angielsku, polskie po polsku."
        }
    }

    private func currentSelection() -> ModeKind {
        switch LanguageModeCodec.decode(prefs.languageModeRaw) {
        case .single: return .single
        case .multilingualAuto: return .auto
        case .mixed: return .mixed
        }
    }

    private func apply(_ kind: ModeKind) {
        let pl = Locale(identifier: "pl-PL")
        let en = Locale(identifier: "en-US")
        let mode: LanguageMode
        switch kind {
        case .single: mode = .single(pl)
        case .auto:   mode = .multilingualAuto([pl, en])
        case .mixed:  mode = .mixed(primary: pl, allowed: [pl, en])
        }
        prefs.languageModeRaw = LanguageModeCodec.encode(mode)
    }
}
