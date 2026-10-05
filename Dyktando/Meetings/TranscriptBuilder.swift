import Foundation

/// Jedna wypowiedź z jednej ścieżki (fragment VAD przepisany przez silnik).
struct Utterance: Codable, Equatable, Sendable {
    enum Track: String, Codable, Sendable { case mic, system }
    var start: Double
    var end: Double
    var track: Track
    var text: String
    var speaker: String = ""
}

/// Fragment z diaryzacji ścieżki „system” (FluidAudio `TimedSpeakerSegment`).
struct SpeakerSegment: Equatable, Sendable {
    var speakerID: String
    var start: Double
    var end: Double
}

struct TranscriptDocument: Codable, Equatable, Sendable {
    var meetingID: String
    var engine: String
    var createdAt: Date
    var durationSeconds: Double
    var utterances: [Utterance]

    var speakers: [String] {
        var seen: [String] = []
        for u in utterances where !seen.contains(u.speaker) { seen.append(u.speaker) }
        return seen
    }
}

/// Składanie transkryptu spotkania z dwóch ścieżek — czysta logika (bez audio i modeli), testowana osobno.
enum TranscriptBuilder {
    static let me = "Ja"
    static let others = "Rozmówcy"

    /// Etykiety mówców dla wypowiedzi ze ścieżki „system”: najdłuższe nakładanie z segmentem diaryzacji;
    /// numeracja „Rozmówca 1, 2…” w kolejności pierwszego pojawienia się. Bez diaryzacji — „Rozmówcy”.
    static func labelSystemUtterances(_ utterances: [Utterance], speakers: [SpeakerSegment]?) -> [Utterance] {
        guard let speakers, !speakers.isEmpty else {
            return utterances.map { var u = $0; u.speaker = others; return u }
        }
        var names: [String: String] = [:]
        return utterances.sorted { $0.start < $1.start }.map { u in
            var best: (id: String, overlap: Double)?
            var totals: [String: Double] = [:]
            for s in speakers {
                let overlap = min(u.end, s.end) - max(u.start, s.start)
                if overlap > 0 { totals[s.speakerID, default: 0] += overlap }
            }
            for (id, overlap) in totals where overlap > (best?.overlap ?? 0) { best = (id, overlap) }
            var labeled = u
            if let id = best?.id {
                if names[id] == nil { names[id] = "Rozmówca \(names.count + 1)" }
                labeled.speaker = names[id]!
            } else {
                labeled.speaker = others
            }
            return labeled
        }
    }

    /// Echo: bez słuchawek głos rozmówców z głośników trafia też do mikrofonu. Wypowiedź z mikrofonu,
    /// która nakłada się w czasie z wypowiedzią systemową i ma podobny tekst, odrzucamy.
    static func removeEcho(mic: [Utterance], system: [Utterance], similarity threshold: Double = 0.6) -> [Utterance] {
        mic.filter { m in
            !system.contains { s in
                let overlap = min(m.end, s.end) - max(m.start, s.start)
                let shorter = max(0.01, min(m.end - m.start, s.end - s.start))
                return overlap / shorter > 0.5 && wordSimilarity(m.text, s.text) >= threshold
            }
        }
    }

    /// Podobieństwo tekstów: część wspólna słów (≥ 3 litery) względem krótszej wypowiedzi.
    static func wordSimilarity(_ a: String, _ b: String) -> Double {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 3 })
        }
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(min(wa.count, wb.count))
    }

    /// Kolejne wypowiedzi tej samej osoby z przerwą < `gap` łączymy w jedną.
    static func mergeConsecutive(_ utterances: [Utterance], gap: Double = 2.0) -> [Utterance] {
        var out: [Utterance] = []
        for u in utterances.sorted(by: { $0.start < $1.start }) {
            if var last = out.last, last.speaker == u.speaker, u.start - last.end < gap {
                last.end = max(last.end, u.end)
                last.text += " " + u.text
                out[out.count - 1] = last
            } else {
                out.append(u)
            }
        }
        return out
    }

    static func build(mic: [Utterance], system: [Utterance], speakers: [SpeakerSegment]?) -> [Utterance] {
        let labeledSystem = labelSystemUtterances(system, speakers: speakers)
        let labeledMic = removeEcho(mic: mic, system: system).map { var u = $0; u.speaker = me; return u }
        return mergeConsecutive(labeledMic + labeledSystem)
    }

    // MARK: - Zapis

    static func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    static func markdown(_ doc: TranscriptDocument, startedAt: Date) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "pl_PL")
        date.dateFormat = "d MMMM yyyy, HH:mm"
        var lines = [
            "# Spotkanie — \(date.string(from: startedAt))",
            "",
            "Długość: \(AppDelegate.clock(doc.durationSeconds)) · Model: \(doc.engine) · Mówcy: \(doc.speakers.joined(separator: ", "))",
            "",
        ]
        for u in doc.utterances {
            lines.append("[\(timestamp(u.start))] **\(u.speaker):** \(u.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
