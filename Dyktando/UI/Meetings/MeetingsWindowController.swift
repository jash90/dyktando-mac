import AppKit
import SwiftUI

@MainActor
final class MeetingsWindowController: NSWindowController {
    static let shared = MeetingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Dyktando — Spotkania"
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DyktandoMeetings")
        super.init(window: window)
        window.contentView = NSHostingView(rootView: MeetingsView())
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(select meetingID: String? = nil) {
        if let meetingID { NotificationCenter.default.post(name: .selectMeeting, object: meetingID) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let selectMeeting = Notification.Name("DyktandoSelectMeeting")
}

struct MeetingsView: View {
    @ObservedObject private var processing = MeetingProcessing.shared
    @ObservedObject private var recorder = MeetingRecorder.shared
    @State private var meetings: [Meeting] = []
    @State private var selection: String?
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(meetings, selection: $selection) { meeting in
                MeetingRow(meeting: meeting, job: processing.jobs[meeting.id])
                    .tag(meeting.id)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 290)
            .toolbar(removing: .sidebarToggle)
            .overlay {
                if meetings.isEmpty {
                    Text("Brak nagranych spotkań.\nNagraj pierwsze z menu Dyktando albo skrótem ⌃⌥R.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
        } detail: {
            if let id = selection, let meeting = meetings.first(where: { $0.id == id }) {
                MeetingDetail(meeting: meeting, job: processing.jobs[id], onDeleted: reload)
                    .id(id)
            } else {
                Text("Wybierz spotkanie").foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reload)
        .onReceive(refresh) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .selectMeeting)) { note in
            reload()
            selection = note.object as? String
        }
    }

    private func reload() {
        meetings = MeetingStore.shared.all()
        if selection == nil { selection = meetings.first?.id }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let job: MeetingProcessing.Job?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title ?? PolishDate.short(meeting.startedAt))
                .font(.headline)
            HStack(spacing: 6) {
                Text(AppDelegate.clock(meeting.durationSeconds))
                Text("·")
                Text(job.map { "\($0.status) \(Int($0.progress * 100))%" } ?? meeting.state.label)
                    .foregroundStyle(meeting.state == .failed ? .red : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct MeetingDetail: View {
    let meeting: Meeting
    let job: MeetingProcessing.Job?
    let onDeleted: () -> Void

    @State private var tab = 0
    @State private var transcript: String?
    @State private var summary: String?
    @State private var confirmDelete = false

    private let store = MeetingStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let job {
                HStack {
                    ProgressView(value: job.progress).frame(maxWidth: 260)
                    Text(job.status).font(.caption).foregroundStyle(.secondary)
                    Button("Przerwij") { MeetingProcessing.shared.cancel(meeting.id) }
                }
            }
            if let error = meeting.lastError, job == nil {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            actions
            Picker("", selection: $tab) {
                Text("Transkrypt").tag(0)
                Text("Podsumowanie").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            ScrollView {
                Text(MarkdownLite.render(content))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .onAppear(perform: load)
        .onChange(of: meeting.state) { _, _ in load() }
        .confirmationDialog("Usunąć to spotkanie (audio, transkrypt i podsumowania)?", isPresented: $confirmDelete) {
            Button("Usuń", role: .destructive) {
                try? store.delete(meeting.id)
                onDeleted()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PolishDate.long(meeting.startedAt)).font(.title2.bold())
            Text([
                "Długość \(AppDelegate.clock(meeting.durationSeconds))",
                meeting.state.label,
                meeting.hasSystemAudio ? "mikrofon + dźwięk aplikacji" : "tylko mikrofon",
                meeting.transcriptEngine.map { "model: \($0)" },
                meeting.audioDeleted ? "audio usunięte" : nil,
            ].compactMap { $0 }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var busy: Bool { job != nil || meeting.state == .recording }

    private var actions: some View {
        HStack {
            Menu("Przepisz") {
                ForEach(EngineID.allCases, id: \.self) { id in
                    if let engine = EngineRegistry.shared.engine(for: id) {
                        Button(engine.displayName + (engine.isInstalled ? "" : " (niezainstalowany)")) {
                            MeetingProcessing.shared.transcribe(meeting.id, engineID: id)
                        }
                        .disabled(!engine.isInstalled)
                    }
                }
            }
            .disabled(busy || meeting.audioDeleted)
            .fixedSize()
            Menu("Podsumuj") {
                ForEach(AIProviderID.allCases) { provider in
                    Button(provider.displayName + (KeychainStore.ai.has(provider.rawValue) ? "" : " (brak klucza)")) {
                        MeetingProcessing.shared.summarize(meeting.id, provider: provider)
                    }
                }
            }
            .disabled(busy || transcript == nil)
            .fixedSize()
            Button("Kopiuj") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
            }
            .disabled(tab == 0 ? transcript == nil : summary == nil)
            Button("Pokaż w Finderze") {
                NSWorkspace.shared.activateFileViewerSelecting([store.folder(for: meeting.id)])
            }
            Spacer()
            Button("Usuń", role: .destructive) { confirmDelete = true }.disabled(busy)
        }
    }

    private var content: String {
        if tab == 0 {
            return transcript ?? (meeting.state == .recording ? "Nagrywanie trwa…"
                                  : "Brak transkryptu — użyj „Przepisz”.")
        }
        return summary ?? "Brak podsumowania — użyj „Podsumuj” (wymaga klucza dostawcy w Ustawieniach → AI)."
    }

    private func load() {
        transcript = try? String(contentsOf: store.transcriptURL(for: meeting.id), encoding: .utf8)
        summary = MeetingSummarizer.latest(for: meeting.id).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

extension Meeting.State {
    var label: String {
        switch self {
        case .recording:    return "nagrywanie"
        case .interrupted:  return "przerwane (aplikacja zamknięta w trakcie)"
        case .recorded:     return "nagrane"
        case .transcribing: return "przepisywanie"
        case .transcribed:  return "przepisane"
        case .summarizing:  return "podsumowywanie"
        case .summarized:   return "podsumowane"
        case .failed:       return "błąd"
        }
    }
}

/// Daty po polsku niezależnie od języka systemu (aplikacja nie ma lokalizacji, więc `formatted()` brałby angielski).
enum PolishDate {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = format
        return f
    }
    static func short(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return formatter(sameYear ? "d MMM, HH:mm" : "d MMM yyyy, HH:mm").string(from: date)
    }
    static func long(_ date: Date) -> String { formatter("EEEE, d MMMM yyyy, HH:mm").string(from: date).capitalizedFirst }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Lekki podgląd Markdown dla transkryptu i podsumowania: nagłówki (#, ##, ###), listy, pogrubienia/kursywa.
/// `Text` w SwiftUI renderuje Markdown tylko w liniach (bez nagłówków), więc nagłówki składamy sami.
enum MarkdownLite {
    static func render(_ markdown: String) -> AttributedString {
        var out = AttributedString()
        for (i, raw) in markdown.components(separatedBy: "\n").enumerated() {
            if i > 0 { out.append(AttributedString("\n")) }
            var line = raw
            var font: Font?
            if let match = line.range(of: #"^#{1,3}\s+"#, options: .regularExpression) {
                let level = line[match].filter { $0 == "#" }.count
                line.removeSubrange(match)
                font = level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold()
            } else if line.hasPrefix("- [ ] ") {
                line = "☐ " + line.dropFirst(6)
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                line = "☑ " + line.dropFirst(6)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            } else if line.hasPrefix("> ") {
                line = String(line.dropFirst(2))
                font = .caption
            }
            var piece = (try? AttributedString(markdown: line,
                                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(line)
            if let font { piece.font = font }
            out.append(piece)
        }
        return out
    }
}
