import SwiftUI

struct ModelsTab: View {
    @ObservedObject var prefs = Preferences.shared
    @StateObject private var registry = EngineRegistry.shared
    @State private var installing: Set<EngineID> = []

    var body: some View {
        List(EngineID.allCases, id: \.self) { id in
            if let engine = registry.engine(for: id) {
                EngineRow(
                    engine: engine,
                    isDefault: prefs.defaultEngineID == id.rawValue,
                    isInstalling: installing.contains(id),
                    onInstall: { install(engine) },
                    onUninstall: { uninstall(engine) },
                    onSetDefault: { prefs.defaultEngineID = id.rawValue }
                )
            }
        }
        .listStyle(.inset)
    }

    private func install(_ engine: TranscriptionEngine) {
        let id = engine.id
        installing.insert(id)
        Task {
            do { try await engine.install { _ in } }
            catch { print("install failed: \(error)") }
            installing.remove(id)
        }
    }

    private func uninstall(_ engine: TranscriptionEngine) {
        do { try engine.uninstall() } catch { print("uninstall failed: \(error)") }
    }
}

struct EngineRow: View {
    let engine: TranscriptionEngine
    let isDefault: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onSetDefault: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(engine.displayName).font(.headline)
                    if isDefault {
                        Text("DOMYŚLNY")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                    }
                }
                Text(engine.isInstalled ? "Zainstalowany" : "Niezainstalowany")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isInstalling {
                ProgressView().controlSize(.small)
            } else if engine.isInstalled {
                if !isDefault {
                    Button("Ustaw domyślny", action: onSetDefault)
                }
                if engine.id != .appleSpeechPL {   // Apple is system-provided, can't uninstall
                    Button("Odinstaluj", role: .destructive, action: onUninstall)
                }
            } else {
                Button("Zainstaluj", action: onInstall)
            }
        }
        .padding(.vertical, 4)
    }
}
