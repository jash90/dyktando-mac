import AppKit
import SwiftUI

struct CommandsView: View {
    @StateObject private var store = CommandStore.shared
    @State private var selection: Command.ID?

    var body: some View {
        HSplitView {
            // ── Left: list ────────────────────────────────────────────────
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.commands) { cmd in
                        commandRow(cmd).tag(cmd.id)
                    }
                    .onMove(perform: store.move(fromOffsets:toOffset:))
                }
                .listStyle(.inset)

                Divider()
                HStack(spacing: 4) {
                    Button { addCommand() } label: { Image(systemName: "plus") }
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                    Text("\(store.commands.count) komend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 240)

            // ── Right: editor ────────────────────────────────────────────
            Group {
                if let id = selection, let i = store.commands.firstIndex(where: { $0.id == id }) {
                    CommandEditor(command: bindingForCommand(at: i))
                } else {
                    placeholder
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear {
            if selection == nil { selection = store.commands.first?.id }
        }
    }

    @ViewBuilder
    private func commandRow(_ cmd: Command) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cmd.enabled ? .green : .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.name.isEmpty ? "Bez nazwy" : cmd.name)
                    .font(.body)
                Text(cmd.trigger.isEmpty ? "(brak triggera)" : cmd.trigger)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(cmd.actions.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "command.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Wybierz komendę z listy lub utwórz nową")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bindingForCommand(at index: Int) -> Binding<Command> {
        Binding(
            get: { store.commands[index] },
            set: { store.update($0) }
        )
    }

    private func addCommand() {
        let fresh = Command(name: "Nowa komenda", trigger: "", actions: [])
        store.add(fresh)
        selection = fresh.id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        store.remove(id)
        selection = store.commands.first?.id
    }
}

// MARK: - Editor

private struct CommandEditor: View {
    @Binding var command: Command

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metaSection
                actionsSection
                hintSection
            }
            .padding(16)
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nazwa").frame(width: 70, alignment: .leading)
                TextField("Krótki opis", text: $command.name)
                    .textFieldStyle(.roundedBorder)
                Toggle("Aktywna", isOn: $command.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack {
                Text("Trigger").frame(width: 70, alignment: .leading)
                TextField("np. otwórz mail", text: $command.trigger)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Akcje").font(.headline)
                Spacer()
                Menu {
                    Button("Naciśnij skrót")    { append(.pressKeys(.init(keyCode: 9, modifiersRaw: NSEvent.ModifierFlags.command.rawValue, label: "⌘V"))) }
                    Button("Otwórz aplikację")  { append(.openTarget(.bundleID("com.apple.Safari"))) }
                    Button("Otwórz URL")        { append(.openTarget(.url(URL(string: "https://example.com")!))) }
                    Button("Pauza")             { append(.wait(milliseconds: 200)) }
                } label: {
                    Label("Dodaj akcję", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if command.actions.isEmpty {
                Text("Brak akcji. Dodaj pierwszą — np. \"Otwórz aplikację\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(command.actions.enumerated()), id: \.offset) { index, _ in
                    ActionRow(action: actionBinding(at: index)) {
                        command.actions.remove(at: index)
                    }
                }
            }
        }
    }

    private var hintSection: some View {
        Text("Komenda odpala się tylko gdy cała wypowiedź (po post-procesie i bez końcowej kropki) pokrywa się z triggerem. Wymaga uprawnienia **Accessibility** dla akcji \"Naciśnij skrót\".")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func append(_ action: CommandAction) {
        command.actions.append(action)
    }

    private func actionBinding(at index: Int) -> Binding<CommandAction> {
        Binding(
            get: { command.actions[index] },
            set: { command.actions[index] = $0 }
        )
    }
}

// MARK: - Action row

private struct ActionRow: View {
    @Binding var action: CommandAction
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content
            Spacer(minLength: 8)
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch action {
        case .pressKeys:  return "keyboard"
        case .openTarget: return "app.badge"
        case .wait:       return "hourglass"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action {
        case .pressKeys(let combo):
            HStack {
                Text("Naciśnij")
                KeyComboRecorder(combo: keyComboBinding(initial: combo))
            }
        case .openTarget(let target):
            OpenTargetEditor(target: openTargetBinding(initial: target))
        case .wait(let ms):
            HStack {
                Text("Pauza")
                Stepper(value: waitBinding(initial: ms), in: 0...10_000, step: 100) {
                    Text("\(ms) ms").font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Action binding helpers

    private func keyComboBinding(initial: KeyCombo) -> Binding<KeyCombo?> {
        Binding(
            get: {
                if case .pressKeys(let c) = action { return c }
                return initial
            },
            set: { newValue in
                if let newValue { action = .pressKeys(newValue) }
            }
        )
    }

    private func openTargetBinding(initial: OpenTarget) -> Binding<OpenTarget> {
        Binding(
            get: {
                if case .openTarget(let t) = action { return t }
                return initial
            },
            set: { action = .openTarget($0) }
        )
    }

    private func waitBinding(initial: Int) -> Binding<Int> {
        Binding(
            get: {
                if case .wait(let ms) = action { return ms }
                return initial
            },
            set: { action = .wait(milliseconds: $0) }
        )
    }
}

// MARK: - Open target editor

private struct OpenTargetEditor: View {
    @Binding var target: OpenTarget
    @State private var kind: Kind

    private enum Kind: String, CaseIterable, Identifiable {
        case bundle = "Aplikacja (bundle id)"
        case url    = "URL"
        case file   = "Plik / .app"
        var id: String { rawValue }
    }

    init(target: Binding<OpenTarget>) {
        self._target = target
        switch target.wrappedValue {
        case .bundleID: _kind = State(initialValue: .bundle)
        case .url:      _kind = State(initialValue: .url)
        case .fileURL:  _kind = State(initialValue: .file)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, new in convert(to: new) }

            switch kind {
            case .bundle:
                TextField("np. com.apple.Mail", text: bundleBinding)
                    .textFieldStyle(.roundedBorder)
            case .url:
                TextField("https://…", text: urlBinding)
                    .textFieldStyle(.roundedBorder)
            case .file:
                HStack {
                    TextField("/Applications/Safari.app", text: filePathBinding)
                        .textFieldStyle(.roundedBorder)
                    Button("Wybierz…") { pickFile() }
                }
            }
        }
    }

    private var bundleBinding: Binding<String> {
        Binding(
            get: {
                if case .bundleID(let id, _) = target { return id }
                return ""
            },
            set: { target = .bundleID($0) }
        )
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                if case .url(let u, _) = target { return u.absoluteString }
                return ""
            },
            set: {
                if let url = URL(string: $0) { target = .url(url) }
            }
        )
    }

    private var filePathBinding: Binding<String> {
        Binding(
            get: {
                if case .fileURL(let u, _) = target { return u.path }
                return ""
            },
            set: {
                let url = URL(fileURLWithPath: $0)
                target = .fileURL(url)
            }
        )
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application, .item]
        if panel.runModal() == .OK, let url = panel.url {
            target = .fileURL(url)
            kind = .file
        }
    }

    private func convert(to new: Kind) {
        switch new {
        case .bundle where !isBundle:
            target = .bundleID("")
        case .url where !isURL:
            target = .url(URL(string: "https://")!)
        case .file where !isFile:
            target = .fileURL(URL(fileURLWithPath: "/Applications"))
        default: break
        }
    }

    private var isBundle: Bool { if case .bundleID = target { return true }; return false }
    private var isURL: Bool    { if case .url      = target { return true }; return false }
    private var isFile: Bool   { if case .fileURL  = target { return true }; return false }
}
