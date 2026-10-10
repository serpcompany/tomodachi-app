import Foundation

// MARK: - Tomo's week, as a postcard (#130 "Today and Tomo's week", Stats Take Two's direction 4)
//
// Every Monday morning (4 am, when Tomo's week starts) Tomo sends a postcard of the week before: on the front, the
// week's word (the picture word answered most) and Tomo; on the back, Tomo's message in its own words and what you
// did, from TomoStats: new words, wins, practice, misses, words that got stronger, the week's longest run of days in a
// row, the level and days together, each only when it isn't zero. A week without an answer still gets one, kept
// light: Tomo sleeps on it ("Zz… またね！"), and its back has Tomo's level and days together. A brand-new Tomo, before
// its first Monday, has a first postcard: Tomo says hello and when its first postcard comes. All text comes from the
// target pack (`postcard`, `lines.hello`) and the learner's interface strings. The card is drawn by
// TomoPostcardView.swift, which also renders it as an image to share (#29).

public struct TomoPostcard: Identifiable, Equatable, Sendable {
    /// A line on the back. `dot`: the Win or Practice colour, like the card's results.
    public struct Fact: Identifiable, Equatable, Sendable {
        public enum Dot: Sendable { case win, practice, miss }
        public let id: String
        public let text: String
        public let dot: Dot?
    }

    /// The week's first day (4 am), or the hatch for a first postcard.
    public let id: Date
    /// A brand-new Tomo's card, before its first Monday: no numbers.
    public let isFirst: Bool
    /// The week's first and last days, at 4 am.
    public let firstDay: Date
    public let lastDay: Date
    /// "Oct 5–Oct 11", in the learner's language.
    public let range: String
    /// The front: Tomo's word and its picture. Asleep, its sleepy line and no picture.
    public let word: String
    public let picture: String?
    /// The back: Tomo's message in the target language, and what it means in the learner's.
    public let message: String
    public let gloss: String
    public let facts: [Fact]
    /// Tomo at the week's end: its level, age, and how far through that age's levels it was (0…1, the stamp's ring).
    public let level: Int
    public let age: Int
    public let ageLabel: String
    public let ageShare: Double
    public let grew: Bool
    public let asleep: Bool
    /// Which of the cards' soft colours its hill takes (0…5).
    public let hue: Int
    /// The text shared with the card's picture.
    public let recap: String
}

extension TomoStats {
    /// Tomo's postcards, oldest first: one for every finished week (`weeks`), each sent the Monday morning after it.
    public func postcards(_ ui: LearnerPack) -> [TomoPostcard] { weeks().map { postcard($0, ui) } }

    /// The week's postcard.
    public func postcard(_ s: Summary, _ ui: LearnerPack) -> TomoPostcard {
        let pack = progress.pack, learner = ui.id
        let firstDay = Self.dayStart(of: s.from)
        let lastDay = Self.calendar.date(byAdding: .day, value: -1, to: s.to) ?? s.from
        let range = Self.range(firstDay, lastDay, ui)
        let age = age(onLevel: s.levelTo)
        let lines = pack.postcard

        // The front's word: the picture word answered most (then the one met first), else any word answered.
        let order = s.newWords + s.stronger + s.answered.keys.sorted()
        func rank(_ id: String) -> (Int, Int, Int) {
            (progress.word(id, learner: learner).emoji == nil ? 0 : 1, s.answered[id] ?? 0,
             -(order.firstIndex(of: id) ?? order.count))
        }
        let favourite = s.answered.keys.max { rank($0) < rank($1) }

        // Tomo's message: the week's word and up to two more (new picture words first), a やったー per level grown (two
        // at most), and see you; asleep, its sleepy line.
        var said: [(say: String, gloss: String)] = []
        if let favourite {
            var ids = [favourite]
            let pictured = { (id: String) in progress.word(id, learner: learner).emoji != nil }
            let candidates = s.newWords.filter(pictured) + s.answered.keys.sorted { rank($0) > rank($1) }.filter(pictured)
                + s.newWords
            for id in candidates where ids.count < 3 && !ids.contains(id) { ids.append(id) }
            said = ids.map { id in
                let w = progress.word(id, learner: learner)
                return (w.say, ui("postcard.word", ["word": Self.plain(w.meaning)]))
            }
            let grew = lines?.grew
            for _ in 0..<min(2, max(0, s.levelTo - s.levelFrom)) {
                said.append((grew?.say ?? pack.lines.levelUp, grew.map { Self.plain($0.translation(learner)) } ?? ""))
            }
            said.append(Self.spoken(lines?.bye, or: pack.lines.seeYou, learner))
        } else {
            said.append(Self.spoken(lines?.asleep, or: pack.lines.seeYou, learner))
        }

        // The back: what you did, never a zero.
        var facts: [TomoPostcard.Fact] = []
        if !s.newWords.isEmpty { facts.append(.init(id: "new", text: ui.counted("postcard.newWords", s.newWords.count), dot: nil)) }
        if s.wins > 0 { facts.append(.init(id: "wins", text: ui.counted("postcard.wins", s.wins), dot: .win)) }
        if s.practice > 0 { facts.append(.init(id: "practice", text: ui.counted("postcard.practice", s.practice), dot: .practice)) }
        if s.misses > 0 { facts.append(.init(id: "misses", text: ui.counted("postcard.misses", s.misses), dot: .miss)) }
        if !s.stronger.isEmpty {
            facts.append(.init(id: "stronger", text: ui.counted("postcard.stronger", s.stronger.count), dot: nil))
        }
        if s.longestRun >= 2 { facts.append(.init(id: "streak", text: ui("postcard.streak", ["n": "\(s.longestRun)"]), dot: nil)) }
        facts.append(.init(id: "level", text: s.grew ? ui("postcard.grew", ["from": "\(s.levelFrom)", "to": "\(s.levelTo)"])
                                                     : ui("level", ["n": "\(s.levelTo)"]), dot: nil))
        facts.append(.init(id: "days", text: ui("words.days", ["n": "\(progress.daysTogether(at: lastDay))"]), dot: nil))

        // The shared text: the same numbers, the level, the week's new words.
        let sep = ui("list.separator")
        var recap = [ui("postcard.recap.title", ["range": range])]
        let counts = facts.filter { ["new", "wins", "practice", "misses", "streak"].contains($0.id) }.map(\.text)
        if !counts.isEmpty { recap.append(counts.joined(separator: sep)) }
        recap.append(s.grew ? ui("postcard.recap.grew", ["from": "\(s.levelFrom)", "to": "\(s.levelTo)", "age": pack.ageLabel(age)])
                            : ui("postcard.recap.level", ["age": pack.ageLabel(age), "n": "\(s.levelTo)"]))
        if !s.newWords.isEmpty {
            let words = s.newWords.prefix(6).map { progress.word($0, learner: learner).say }.joined(separator: " ")
            recap.append(ui("postcard.recap.words", ["words": words]))
        }
        recap.append(ui("postcard.recap.app"))

        let front = favourite.map { progress.word($0, learner: learner) }
        return TomoPostcard(
            id: firstDay, isFirst: false, firstDay: firstDay, lastDay: lastDay, range: range,
            word: front?.say ?? said[0].say, picture: front?.emoji,
            message: said.map(\.say).joined(separator: " "), gloss: said.map(\.gloss).filter { !$0.isEmpty }.joined(separator: " "),
            facts: facts, level: s.levelTo, age: age, ageLabel: pack.ageLabel(age), ageShare: ageShare(level: s.levelTo),
            grew: s.grew, asleep: favourite == nil, hue: Self.hue(firstDay), recap: recap.joined(separator: "\n"))
    }

    /// A brand-new Tomo's card, before its first Monday: Tomo says hello (ばあ！) and when its first postcard comes.
    public func firstPostcard(_ ui: LearnerPack) -> TomoPostcard {
        let pack = progress.pack, learner = ui.id, today = Self.dayStart(of: TomoClock.now)
        let hello = pack.lines.hello.map { ($0.say, Self.plain($0.translation(learner))) } ?? (pack.lines.practice, "")
        let bye = Self.spoken(pack.postcard?.bye, or: pack.lines.seeYou, learner)
        let level = progress.level, age = progress.age
        return TomoPostcard(
            id: progress.metAt, isFirst: true, firstDay: today, lastDay: today, range: Self.range(today, today, ui),
            word: hello.0, picture: nil, message: [hello.0, bye.say].joined(separator: " "),
            gloss: [hello.1, bye.gloss].filter { !$0.isEmpty }.joined(separator: " "),
            facts: [.init(id: "first", text: ui("postcard.first"), dot: nil)],
            level: level, age: age, ageLabel: pack.ageLabel(age), ageShare: ageShare(level: level),
            grew: false, asleep: false, hue: 0, recap: "")
    }

    /// Whether the newest postcard came this morning: it's the Monday it was sent (the Tomo screen says so).
    public func arrivedToday(_ card: TomoPostcard?) -> Bool {
        guard let card, !card.isFirst else { return false }
        return Self.dayStart(of: TomoClock.now) == Self.calendar.date(byAdding: .day, value: 1, to: card.lastDay)
    }

    /// On the Monday a postcard came (its week just ended), that week ("Oct 5–Oct 11"); any other day, nil. Reads only
    /// the first answer, so the Tomo screen can ask often.
    public func postcardCameToday(_ ui: LearnerPack) -> String? {
        let now = TomoClock.now, monday = Self.weekStart(of: now)
        guard Self.dayStart(of: now) == monday, let since, since < monday,
              let lastDay = Self.calendar.date(byAdding: .day, value: -1, to: monday),
              let weekAgo = Self.calendar.date(byAdding: .day, value: -7, to: monday) else { return nil }
        return Self.range(Self.dayStart(of: max(weekAgo, since)), lastDay, ui)
    }

    // MARK: Pieces

    /// How far through its age's levels Tomo was on a level, 0…1.
    private func ageShare(level: Int) -> Double {
        guard let span = progress.ageSpans.first(where: { $0.from <= level && level <= $0.to }) else { return 0 }
        return Double(level - span.from + 1) / Double(span.to - span.from + 1)
    }

    /// "Oct 5–Oct 11" (one day: "Oct 5").
    static func range(_ a: Date, _ b: Date, _ ui: LearnerPack) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: ui.id)
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let from = f.string(from: a), to = f.string(from: b)
        return from == to ? from : ui("postcard.range", ["from": from, "to": to])
    }

    /// A pack line, said and meant: its own, or a plain line with no meaning given.
    private static func spoken(_ line: TargetPack.SpokenLine?, or fallback: String, _ learner: String) -> (say: String, gloss: String) {
        line.map { ($0.say, plain($0.translation(learner))) } ?? (fallback, "")
    }

    /// A meaning without its note: "woof woof (doggy)" → "woof woof".
    static func plain(_ meaning: String) -> String {
        meaning.replacingOccurrences(of: #"\s*[(（][^()（）]*[)）]\s*$"#, with: "", options: .regularExpression)  // text-ok: matches full-width brackets
    }

    /// The hill's colour for a week: one of six, by the week of the year.
    nonisolated static func hue(_ day: Date) -> Int { calendar.component(.weekOfYear, from: day) % 6 }
}
