import Foundation

// MARK: - Tomo's diary (#137 item 2, Stats Take Two's direction 1)
//
// Tomo writes a page for every day you played together (a day starts at 4 am), in its own words at its age, the way the
// postcard's message is: ばあ！ on the first day, the day's words (new picture words first), a sulk when you came back
// after days apart (まってた！ もう！), a やったー for each level grown or おおきく なった！ at a birthday, a groan on a hard
// day (many misses), a cheer on a run of days in a row, and またね！. Under it: the day's words as stickers, and what
// you did (new words, wins, practice, misses, words that got stronger, the run of days, the level, how often Tomo came
// by). A day without play has no page; the days apart show in the next page's sulk and in the list. Tomo's words come
// from the target pack (`lines.hello`, `diary`, `postcard`), the rest from the interface strings.

public struct TomoDiaryPage: Identifiable, Equatable, Sendable {
    /// The day's start (4 am).
    public var id: Date { day }
    public let day: Date
    /// "Day 17 together".
    public let dayNumber: Int
    /// What happened that day.
    public let summary: TomoStats.Summary
    /// Days without play since the page before (0: the day after it, or the first page).
    public let apart: Int
    /// Days in a row with play, ending this day.
    public let streak: Int
    /// The day Tomo hatched.
    public let first: Bool
    /// Tomo turned a new age that day.
    public let birthday: Bool
    /// Tomo's age at the end of the day.
    public let age: Int
    /// How many visits Tomo made that day (not counting the learner opening it).
    public let visits: Int
    /// Tomo's words, and what they mean in the learner's language.
    public let message: String
    public let gloss: String
    /// The first two things Tomo says, for the list of pages.
    public let headline: String
    /// The day's new words, oldest first: the page's stickers.
    public let stickers: [String]
    /// What you did, never a zero.
    public let facts: [TomoPostcard.Fact]
}

extension TomoStats {
    /// Every page of Tomo's diary, oldest first: one for each day with an answer since this Tomo's stats began.
    public func diary(_ ui: LearnerPack) -> [TomoDiaryPage] {
        guard let since else { return [] }
        let now = TomoClock.now, end = Self.day(after: Self.dayStart(of: now))
        let rows = progress.answerLog(from: since, to: end).filter { $0.result == "right" || $0.result == "wrong" }
        let byDay = Dictionary(grouping: rows) { Self.dayStart(of: $0.at) }
        let days = byDay.keys.sorted(), played = Set(days)
        let visits = Dictionary(grouping: self.visits(from: progress.metAt, to: end).filter { $0.opened != .learner }) {
            Self.dayStart(of: $0.started)
        }
        let hatchDay = Self.dayStart(of: progress.metAt)
        var pages: [TomoDiaryPage] = [], previous: Date?
        for day in days {
            let next = Self.day(after: day)
            let s = summarize(byDay[day] ?? [], from: day, to: next)
            let apart = previous.map { prev in
                (Self.calendar.dateComponents([.day], from: prev, to: day).day ?? 1) - 1
            } ?? 0
            let ages = growth.filter { $0.kind == "age" && $0.at >= day && $0.at < next }
            let birthday = !ages.isEmpty || age(onLevel: s.levelTo) > age(onLevel: s.levelFrom)
            pages.append(page(day: day, s, apart: max(apart, 0), streak: Self.run(endingOn: day, in: played),
                              first: day == hatchDay, birthday: birthday, visits: visits[day]?.count ?? 0, ui))
            previous = day
        }
        return pages
    }

    private func page(day: Date, _ s: Summary, apart: Int, streak: Int, first: Bool, birthday: Bool, visits: Int,
                      _ ui: LearnerPack) -> TomoDiaryPage {
        let pack = progress.pack, learner = ui.id, age = age(onLevel: s.levelTo)
        let lines = pack.diaryLines(age: age)
        func line(_ l: TargetPack.SpokenLine?) -> (say: String, gloss: String)? { l.map { ($0.say, Self.plain($0.translation(learner))) } }

        // Tomo's words: hello on the first day, a sulk after days apart, the day's words, a cheer for growing, a groan on
        // a hard day, a cheer for a run of days, and see you.
        var said: [(say: String, gloss: String)] = []
        if first, let hello = line(pack.lines.hello) { said.append(hello) }
        if apart > 0, let sulk = line(lines?.missed) { said.append(sulk) }
        let pictured = { (id: String) in progress.word(id, learner: learner).emoji != nil }
        var ids: [String] = []
        let answered = s.answered.keys.sorted { (s.answered[$0] ?? 0, $1) > (s.answered[$1] ?? 0, $0) }
        for id in s.newWords.filter(pictured) + s.newWords + answered.filter(pictured) where ids.count < 3 && !ids.contains(id) {
            ids.append(id)
        }
        said += ids.map { id in
            let w = progress.word(id, learner: learner)
            return (w.say, ui("postcard.word", ["word": Self.plain(w.meaning)]))
        }
        if birthday, let big = line(lines?.birthday) {
            said.append(big)
        } else {
            let yay = line(pack.postcard?.grew) ?? (pack.lines.levelUp, "")
            for _ in 0..<min(2, max(0, s.levelTo - s.levelFrom)) { said.append(yay) }
        }
        if s.misses >= 5, s.misses * 3 >= s.answers, let hard = line(lines?.hard) { said.append(hard) }
        if streak >= 3, apart == 0, let cheer = line(lines?.streak) { said.append(cheer) }
        said.append(Self.spoken(pack.postcard?.bye, or: pack.lines.seeYou, learner))

        // What you did: the day's counts, the run of days, the level, and Tomo's visits.
        var facts = counts(s, ui).filter { $0.id != "streak" }
        if streak >= 2 { facts.append(.init(id: "streak", text: ui("postcard.streak", ["n": "\(streak)"]), dot: nil)) }
        if s.grew { facts.append(.init(id: "level", text: ui("postcard.grew", ["from": "\(s.levelFrom)", "to": "\(s.levelTo)"]), dot: nil)) }
        if visits > 0 { facts.append(.init(id: "visits", text: ui.counted("diary.visits", visits), dot: nil)) }

        return TomoDiaryPage(
            day: day, dayNumber: progress.daysTogether(at: day), summary: s, apart: apart, streak: streak, first: first,
            birthday: birthday, age: age, visits: visits,
            message: said.map(\.say).joined(separator: " "),
            gloss: said.map(\.gloss).filter { !$0.isEmpty }.joined(separator: " "),
            headline: said.prefix(2).map(\.say).joined(separator: " "),
            stickers: s.newWords, facts: facts)
    }

    /// A page as text, for Copy this page: the day, Tomo's words, what they mean, what you did, the app.
    public func diaryText(_ page: TomoDiaryPage, _ ui: LearnerPack) -> String {
        [ui("diary.copyTitle", ["date": Self.longDay(page.day, ui)]), page.message, page.gloss,
         page.facts.map(\.text).joined(separator: ui("list.separator")), ui("postcard.recap.app")]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// "Sunday, October 11" (10月11日 日曜日).
    public static func longDay(_ d: Date, _ ui: LearnerPack) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: ui.id)
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: d)
    }
}
