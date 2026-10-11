import Foundation

// MARK: - What you did, in words and as files: the recap and the learner's own log (#137 item 2)
//
// The recap is the short text Copy recap puts on the clipboard and the postcard shares beside its picture: the range,
// what you did, Tomo's level and the new words. The export is the learner's own data: this Tomo's log on this device as
// JSON (everything as it's stored, for anyone who wants it raw) or Markdown (tables a person can read or paste). Both
// come from TomoStats, so they always say what the screens say. Text comes from the interface strings.

extension TomoStats {
    /// What you did in a stretch, as the lines a postcard's back and the recap list: new words, wins, practice, misses,
    /// words that got stronger, and a run of days in a row. Only what isn't zero.
    public func counts(_ s: Summary, _ ui: LearnerPack) -> [TomoPostcard.Fact] {
        var facts: [TomoPostcard.Fact] = []
        if !s.newWords.isEmpty { facts.append(.init(id: "new", text: ui.counted("postcard.newWords", s.newWords.count), dot: nil)) }
        if s.wins > 0 { facts.append(.init(id: "wins", text: ui.counted("postcard.wins", s.wins), dot: .win)) }
        if s.practice > 0 { facts.append(.init(id: "practice", text: ui.counted("postcard.practice", s.practice), dot: .practice)) }
        if s.misses > 0 { facts.append(.init(id: "misses", text: ui.counted("postcard.misses", s.misses), dot: .miss)) }
        if !s.stronger.isEmpty {
            facts.append(.init(id: "stronger", text: ui.counted("postcard.stronger", s.stronger.count), dot: nil))
        }
        if s.longestRun >= 2 { facts.append(.init(id: "streak", text: ui("postcard.streak", ["n": "\(s.longestRun)"]), dot: nil)) }
        return facts
    }

    /// The recap: "Tomo and me · Oct 5–Oct 11", what you did, Tomo's level, the new words, the app.
    public func recap(_ s: Summary, range: String, _ ui: LearnerPack) -> String {
        let pack = progress.pack, age = age(onLevel: s.levelTo)
        var lines = [ui("postcard.recap.title", ["range": range])]
        let facts = counts(s, ui).map(\.text)
        if !facts.isEmpty { lines.append(facts.joined(separator: ui("list.separator"))) }
        lines.append(s.grew ? ui("postcard.recap.grew", ["from": "\(s.levelFrom)", "to": "\(s.levelTo)", "age": pack.ageLabel(age)])
                            : ui("postcard.recap.level", ["age": pack.ageLabel(age), "n": "\(s.levelTo)"]))
        if !s.newWords.isEmpty {
            let words = s.newWords.prefix(6).map { progress.word($0, learner: ui.id).say }.joined(separator: " ")
            lines.append(ui("postcard.recap.words", ["words": words]))
        }
        lines.append(ui("postcard.recap.app"))
        return lines.joined(separator: "\n")
    }

    /// A range's days, for the recap's title: "Oct 11", "Oct 5–Oct 11", "Sep 18–Oct 11".
    public func rangeText(_ range: Range, _ ui: LearnerPack) -> String {
        let today = Self.dayStart(of: TomoClock.now)
        switch range {
        case .today: return Self.range(today, today, ui)
        case .week:  return Self.range(max(Self.weekStart(of: TomoClock.now), Self.dayStart(of: progress.metAt)), today, ui)
        case .all:   return Self.range(Self.dayStart(of: progress.metAt), today, ui)
        }
    }

    /// A day, short: "Oct 3" (10月3日).
    public static func shortDay(_ d: Date, _ ui: LearnerPack) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: ui.id)
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: d)
    }

    // MARK: The learner's own log

    /// Everything this device logged for this Tomo since it hatched, and its words now.
    public func log(_ ui: LearnerPack) -> TomoLogExport {
        let now = TomoClock.now, end = Self.day(after: Self.dayStart(of: now))
        let words = progress.items.values.sorted { ($0.introduced, $0.id) < ($1.introduced, $1.id) }.map { i in
            let w = progress.word(i.id, learner: ui.id)
            return TomoLogExport.Word(id: i.id, say: w.say, reading: w.reading, meaning: w.meaning, stage: i.stage,
                                      best: max(i.peak, i.stage), met: i.introduced, due: i.due)
        }
        return TomoLogExport(
            app: ui("postcard.recap.app"), exported: now,
            tomo: .init(learner: ui.id, target: progress.pack.id, hatched: progress.metAt, level: progress.level,
                        age: progress.age),
            words: words,
            answers: progress.answerLog(from: progress.metAt, to: end).map {
                .init(at: $0.at, word: $0.item, level: $0.level, mode: $0.mode, result: $0.result, wrongTries: $0.wrongTries,
                      hint: $0.hint, counted: $0.counted, stageBefore: $0.before, stageAfter: $0.after)
            },
            growth: growthLog.map { .init(at: $0.at, kind: $0.kind, value: $0.value) },
            visits: visits(from: progress.metAt, to: end).map {
                .init(started: $0.started, opened: $0.opened.rawValue, cardAt: $0.cardAt, endedAt: $0.endedAt,
                      ended: $0.ended?.rawValue)
            })
    }

    /// The log as JSON: dates in ISO 8601 with this device's offset, keys sorted, pretty.
    public func exportJSON(_ ui: LearnerPack) -> Data {
        (try? TomoLogExport.encoder.encode(log(ui))) ?? Data()
    }

    /// The log as Markdown: Tomo, then a table of weeks, the words and every answer (its time on the person's own 12-
    /// or 24-hour clock, `hourCycle`).
    public func exportMarkdown(_ ui: LearnerPack, hourCycle: Locale.HourCycle = Locale.current.hourCycle) -> String {
        let log = log(ui), pack = progress.pack
        let day = DateFormatter(), time = DateFormatter()
        day.locale = Locale(identifier: ui.id)
        day.dateStyle = .medium
        time.locale = tomoClockLocale(ui.id, hourCycle: hourCycle)   // each answer's time, on the person's own clock
        time.dateStyle = .short
        time.timeStyle = .short
        func row(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        func table(_ head: [String], _ rows: [[String]]) -> [String] {
            [row(head), row(head.map { _ in "---" })] + rows.map(row)
        }
        func stage(_ n: Int) -> String { "\(ui("stage.\(TomoSRS.group(n))")) (\(n))" }

        var md = ["# \(ui("export.title"))", "",
                  "\(log.app) · \(ui("export.exported", ["date": day.string(from: log.exported)]))", "",
                  [pack.ageLabel(progress.age), ui("level", ["n": "\(progress.level)"]),
                   ui("words.days", ["n": "\(progress.daysTogether)"])].joined(separator: ui("list.separator")), "",
                  ui("export.note"), ""]

        var weeks = self.weeks().map { ($0, Self.range(Self.dayStart(of: $0.from), Self.day(before: $0.to), ui)) }
        if since != nil { weeks.append((summary(.week), rangeText(.week, ui))) }
        md += ["## \(ui("export.weeks"))", ""] + table(
            ["export.col.week", "export.col.answers", "export.col.wins", "export.col.practice", "export.col.misses",
             "export.col.new", "export.col.days", "export.col.level"].map { ui($0) },
            weeks.map { s, range in
                [range, "\(s.answers)", "\(s.wins)", "\(s.practice)", "\(s.misses)", "\(s.newWords.count)", "\(s.daysPlayed)",
                 s.grew ? ui("postcard.grew", ["from": "\(s.levelFrom)", "to": "\(s.levelTo)"]) : ui("level", ["n": "\(s.levelTo)"])]
            }) + [""]

        md += ["## \(ui("export.words")) (\(log.words.count))", ""] + table(
            ["export.col.word", "export.col.reading", "export.col.meaning", "export.col.stage", "export.col.met"].map { ui($0) },
            log.words.map { [$0.say, $0.reading ?? "", $0.meaning, stage($0.stage), day.string(from: $0.met)] }) + [""]

        md += ["## \(ui("export.answers")) (\(log.answers.count))", ""] + table(
            ["export.col.when", "export.col.word", "export.col.result", "export.col.counted", "export.col.stage"].map { ui($0) },
            log.answers.map { a in
                [time.string(from: a.at), a.word.map { progress.word($0, learner: ui.id).say } ?? "",
                 ui("export.result.\(a.result)"), ui(a.counted ? "export.yes" : "export.no"),
                 a.stageAfter.map { after in a.stageBefore.map { "\($0) → \(after)" } ?? "→ \(after)" } ?? ""]
            })
        return md.joined(separator: "\n") + "\n"
    }

    /// This Tomo's growth log (level-ups, birthdays) on this device.
    var growthLog: [TomoStore.GrowthRow] { progress.growthEvents() }
}

/// The learner's own log, as exported (`TomoStats.log`): Tomo, its words now, and every answer, level-up, birthday and
/// visit this device logged since it hatched.
public struct TomoLogExport: Codable, Equatable, Sendable {
    public struct Tomo: Codable, Equatable, Sendable {
        public let learner: String, target: String
        public let hatched: Date
        public let level: Int, age: Int
    }
    public struct Word: Codable, Equatable, Sendable {
        public let id: String, say: String
        public let reading: String?
        public let meaning: String
        public let stage: Int, best: Int
        public let met: Date
        public let due: Date?
    }
    public struct Answer: Codable, Equatable, Sendable {
        public let at: Date
        public let word: String?
        public let level: Int
        public let mode: String, result: String
        public let wrongTries: Int
        public let hint: Bool, counted: Bool
        public let stageBefore: Int?, stageAfter: Int?
    }
    public struct Growth: Codable, Equatable, Sendable {
        public let at: Date
        public let kind: String
        public let value: Int
    }
    public struct Visit: Codable, Equatable, Sendable {
        public let started: Date
        public let opened: String
        public let cardAt: Date?, endedAt: Date?
        public let ended: String?
    }

    public let app: String
    public let exported: Date
    public let tomo: Tomo
    public let words: [Word]
    public let answers: [Answer]
    public let growth: [Growth]
    public let visits: [Visit]

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(iso.string(from: date))
        }
        return e
    }

    /// Reads an exported log back (the self-test checks the round trip).
    public static func decode(_ data: Data) -> TomoLogExport? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = iso.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: s))
            }
            return date
        }
        return try? d.decode(TomoLogExport.self, from: data)
    }
}
