import SwiftUI

struct ModelsTab: View {
    @ObservedObject var prefs = Preferences.shared
    @StateObject private var registry = EngineRegistry.shared
    @State private var installing: Set<EngineID> = []
    @State private var installProgress: [EngineID: Double] = [:]
    @State private var alertMessage: String?
    @State private var registryTick: Int = 0   // force re-render after install completes

    var body: some View {
        List(EngineID.allCases, id: \.self) { id in
            if let engine = registry.engine(for: id) {
                EngineRow(
                    engine: engine,
                    isDefault: prefs.defaultEngineID == id.rawValue,
                    isInstalling: installing.contains(id),
                    progress: installProgress[id],
                    onInstall: { install(engine) },
                    onUninstall: { uninstall(engine) },
                    onSetDefault: { prefs.defaultEngineID = id.rawValue }
                )
                .id("\(id.rawValue)-\(registryTick)")
            }
        }
        .listStyle(.inset)
        .alert("Błąd",
               isPresented: Binding(
                   get: { alertMessage != nil },
                   set: { if !$0 { alertMessage = nil } })) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func install(_ engine: TranscriptionEngine) {
        let id = engine.id
        installing.insert(id)
        installProgress[id] = 0
        Task { @MainActor in
            do {
                try await engine.install { fraction in
                    Task { @MainActor in
                        installProgress[id] = fraction
                    }
                }
                print("Install OK: \(id.rawValue)")
            } catch {
                let msg = "Instalacja \(engine.displayName) nie powiodła się:\n\(error.localizedDescription)\n\nSzczegóły: \(String(describing: error))"
                print("install failed [\(id.rawValue)]: \(error)")
                alertMessage = msg
            }
            installing.remove(id)
            installProgress[id] = nil
            registryTick &+= 1
        }
    }

    private func uninstall(_ engine: TranscriptionEngine) {
        do {
            try engine.uninstall()
            registryTick &+= 1
        } catch {
            alertMessage = "Odinstalowanie nie powiodło się: \(error.localizedDescription)"
            print("uninstall failed: \(error)")
        }
    }
}

struct EngineRow: View {
    let engine: TranscriptionEngine
    let isDefault: Bool
    let isInstalling: Bool
    let progress: Double?
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
                if isInstalling, let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 180)
                }
            }
            Spacer()
            if isInstalling {
                ProgressView().controlSize(.small)
            } else if engine.isInstalled {
                if !isDefault {
                    Button("Ustaw domyślny", action: onSetDefault)
                }
                if engine.id != .appleSpeechPL {
                    Button("Odinstaluj", role: .destructive, action: onUninstall)
                }
            } else {
                Button("Zainstaluj", action: onInstall)
            }
        }
        .padding(.vertical, 4)
    }
}
