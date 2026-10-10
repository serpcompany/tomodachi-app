import Foundation

// MARK: - What you and Tomo did together: the one stats layer (#137 item 2, #130 "Today and Tomo's week")
//
// Every stats screen reads its numbers here: the Today line (the Tomo and Together screens), Tomo's week as a postcard
// (TomoPostcard.swift), and later the word garden, the height pillar and the diary. They're counted from the Tomo's own
// logs (TomoStore: `answer`, `growth`, `visit`), which stay on each device, so stats show this device only until the
// logs sync (#62). A TomoStats takes the TomoProgress it describes, so another Tomo (a friend) has its own.
// Streaks, misses and missed days are data, and the layer gives them; the one rule (concepts.md) is never a growing
// count of things to review or do. Ignored visits are logged and not shown yet, a choice for now. A day starts at 4 am,
// like the daily new words, so 1 am still belongs to the day before; Tomo's week starts on Monday at 4 am, when its
// postcard comes.

/// One time Tomo and the learner were together, for the visit log (TomoStore's `visit` table, this device only): a
/// visit Tomo started, as the card or as a peek, or the learner opening Tomo (free play). TomoGame records it, for the
/// mood ladder and later screens (the stats screens leave ignored visits off for now).
public struct TomoVisit: Equatable, Sendable {
    public enum Opened: String, Sendable { case card, peek, learner }
    /// finished: played to its end · ignored: left alone until it tucked back in · closed: put away (×, Esc, leaving
    /// the iPhone app) · rested: nothing counted, and it tucked back in.
    public enum Ended: String, Sendable { case finished, ignored, closed, rested }

    public var started: Date
    public var opened: Opened
    /// When its card opened: at the start for the card or the learner, later (or never) for a peek.
    public var cardAt: Date?
    public var endedAt: Date?
    /// Nil while it runs, or when the app quit during it.
    public var ended: Ended?

    public init(started: Date, opened: Opened, cardAt: Date? = nil, endedAt: Date? = nil, ended: Ended? = nil) {
        self.started = started
        self.opened = opened
        self.cardAt = cardAt
        self.endedAt = endedAt
        self.ended = ended
    }
}

@MainActor
public struct TomoStats {
    /// The Tomo these stats describe.
    public let progress: TomoProgress
    private let growth: [TomoStore.GrowthRow]

    public init(_ progress: TomoProgress) {
        self.progress = progress
        growth = progress.growthEvents()
    }

    /// What happened in a stretch of time, from the logs.
    public struct Summary: Equatable, Sendable {
        public var from: Date
        public var to: Date
        /// Answers given: right and wrong tries (help requests and the wrong language aren't answers).
        public var answers = 0
        /// Right answers that counted (a word moved), right answers that were practice, and wrong tries (misses).
        public var wins = 0
        public var practice = 0
        public var misses = 0
        /// How many days had an answer, and the longest run of them in a row (on Tomo's 4 am days).
        public var daysPlayed = 0
        public var longestRun = 0
        /// Words met for the first time, in the order they were met.
        public var newWords: [String] = []
        /// Words met before that moved up a stage, in order.
        public var stronger: [String] = []
        /// How many answers each word got.
        public var answered: [String: Int] = [:]
        /// Tomo's level when it began and when it ended, and how many level-ups were logged in it.
        public var levelFrom = 1
        public var levelTo = 1
        public var levelUps = 0

        public init(from: Date, to: Date) {
            self.from = from
            self.to = to
        }

        public var played: Bool { answers > 0 }
        public var grew: Bool { levelTo > levelFrom }
    }

    /// What happened in `[from, to)`.
    public func summary(from: Date, to: Date) -> Summary {
        summarize(progress.answerLog(from: from, to: to), from: from, to: to)
    }

    private func summarize(_ rows: [TomoStore.AnswerRow], from: Date, to: Date) -> Summary {
        var s = Summary(from: from, to: to)
        var met = Set<String>(), moved = Set<String>()
        var days = Set<Date>()
        for r in rows where r.result == "right" || r.result == "wrong" {
            s.answers += 1
            days.insert(Self.dayStart(of: r.at))
            if let id = r.item { s.answered[id, default: 0] += 1 }
            guard r.result == "right" else { s.misses += 1; continue }
            guard r.counted else { s.practice += 1; continue }
            s.wins += 1
            guard let id = r.item else { continue }
            if r.before == nil {
                if met.insert(id).inserted { s.newWords.append(id) }
            } else if let b = r.before, let a = r.after, a > b, !met.contains(id), moved.insert(id).inserted {
                s.stronger.append(id)
            }
        }
        s.daysPlayed = days.count
        s.longestRun = Self.runs(days).max() ?? 0
        s.levelFrom = level(at: from)
        s.levelTo = max(level(at: to), s.levelFrom)
        s.levelUps = growth.filter { $0.kind == "level" && $0.at >= from && $0.at < to }.count
        return s
    }

    /// Tomo's level at a time, from the growth log; from now on, its level now. Before the first level-up this device
    /// logged, one below it; with none logged, the level now (a Tomo that grew elsewhere).
    public func level(at t: Date) -> Int {
        if t >= TomoClock.now { return progress.level }
        let ups = growth.filter { $0.kind == "level" }
        if let last = ups.last(where: { $0.at <= t }) { return last.value }
        if let next = ups.first(where: { $0.at > t }) { return max(1, next.value - 1) }
        return progress.level
    }

    /// Tomo's age on a level: the pack's age for it (a birthday is always a level-up).
    public func age(onLevel level: Int) -> Int {
        let levels = progress.pack.levels
        guard !levels.isEmpty else { return 1 }
        return max(levels[min(max(level, 1), levels.count) - 1].age, 1)
    }

    // MARK: Today

    /// Today, since 4 am.
    public var today: Summary {
        let day = Self.dayStart(of: TomoClock.now)
        return summary(from: day, to: Self.day(after: day))
    }

    /// "12 answers · 3 new words · 5 days in a row · Lv 61 → 62": what you did today, in the learner's words. Before
    /// the first answer, "Nothing yet today", with the streak still waiting on today ("· 4 days in a row"). A streak
    /// shows from two days. Never a count of what's left to do.
    public func todayLine(_ ui: LearnerPack) -> String {
        let t = today, streak = currentStreak
        var parts = t.played ? [ui.counted("today.answers", t.answers)] : [ui("today.nothing")]
        if !t.newWords.isEmpty { parts.append(ui.counted("today.newWords", t.newWords.count)) }
        if streak >= 2 { parts.append(ui("today.streak", ["n": "\(streak)"])) }
        if t.played, t.grew { parts.append(ui("today.grew", ["from": "\(t.levelFrom)", "to": "\(t.levelTo)"])) }
        return parts.joined(separator: ui("list.separator"))
    }

    // MARK: Streaks and missed days (Tomo's 4 am days)

    /// The days (each its 4 am start) with at least one answer in `[from, to)`.
    public func daysPlayed(from: Date, to: Date) -> Set<Date> {
        Set(progress.answerLog(from: from, to: to).filter { $0.result == "right" || $0.result == "wrong" }
            .map { Self.dayStart(of: $0.at) })
    }

    /// The streak on a day: days in a row with at least one answer, ending on the day `t` belongs to (0 when it has
    /// none).
    public func streak(endingOn t: Date) -> Int {
        let day = Self.dayStart(of: t)
        return Self.run(endingOn: day, in: daysPlayed(from: progress.metAt, to: Self.day(after: day)))
    }

    /// The streak now: today's, or before today's first answer, yesterday's, since it isn't broken until today ends.
    public var currentStreak: Int {
        let today = Self.dayStart(of: TomoClock.now)
        let played = daysPlayed(from: progress.metAt, to: Self.day(after: today))
        return played.contains(today) ? Self.run(endingOn: today, in: played)
            : Self.run(endingOn: Self.day(before: today), in: played)
    }

    /// Days without an answer in `[from, to)`, counted from when this Tomo's stats began (`since`), up to yesterday:
    /// today isn't missed until it's over.
    public func missedDays(from: Date, to: Date) -> Int {
        guard let since else { return 0 }
        let played = daysPlayed(from: from, to: to)
        let last = min(Self.dayStart(of: to.addingTimeInterval(-1)), Self.day(before: Self.dayStart(of: TomoClock.now)))
        var day = Self.dayStart(of: max(from, since)), missed = 0
        while day <= last {
            if !played.contains(day) { missed += 1 }
            day = Self.day(after: day)
        }
        return missed
    }

    /// Visits left alone until they tucked back in, in `[from, to)`. Data for later screens; none shows it yet.
    public func ignoredVisits(from: Date, to: Date) -> Int {
        visits(from: from, to: to).filter { $0.ended == .ignored }.count
    }

    nonisolated static func day(after d: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: d) ?? d }
    nonisolated static func day(before d: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: d) ?? d }

    /// How many days in a row in `days` end on `day`.
    nonisolated static func run(endingOn day: Date, in days: Set<Date>) -> Int {
        var n = 0, d = day
        while days.contains(d) {
            n += 1
            d = Self.day(before: d)
        }
        return n
    }

    /// The lengths of each run of days in a row.
    nonisolated static func runs(_ days: Set<Date>) -> [Int] {
        days.filter { !days.contains(day(before: $0)) }.map { start in
            var n = 0, d = start
            while days.contains(d) {
                n += 1
                d = day(after: d)
            }
            return n
        }
    }

    // MARK: Weeks

    /// When this Tomo's stats begin on this device: its first answer here, never before it hatched. Nil: none yet.
    public var since: Date? { progress.firstAnswerAt() }

    /// Every finished week since then, oldest first: Monday 4 am to the next Monday 4 am, the first one from `since`.
    /// The newest is the one whose postcard came last Monday morning. A week without an answer is still a week.
    public func weeks() -> [Summary] {
        guard let since else { return [] }
        let now = TomoClock.now
        let rows = progress.answerLog(from: since, to: now)
        var out: [Summary] = [], start = Self.weekStart(of: since), i = 0
        while let end = Self.calendar.date(byAdding: .day, value: 7, to: start), end <= now {
            let from = max(start, since)
            var bucket: [TomoStore.AnswerRow] = []
            while i < rows.count, rows[i].at < end {
                if rows[i].at >= from { bucket.append(rows[i]) }
                i += 1
            }
            out.append(summarize(bucket, from: from, to: end))
            start = end
        }
        return out
    }

    // MARK: Visits

    /// The visit log in `[from, to)`, for screens that show visits (the diary).
    public func visits(from: Date, to: Date) -> [TomoVisit] { progress.visitLog(from: from, to: to) }

    // MARK: Days and weeks on Tomo's clock

    /// Weeks and days are counted on the Gregorian calendar in this time zone, whatever calendar the device shows.
    nonisolated static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// The 4 am that starts the day `t` belongs to (TomoClock.dayStart's rule: before 4 am is still the day before).
    nonisolated public static func dayStart(of t: Date) -> Date {
        let cal = calendar
        let four = cal.date(bySettingHour: 4, minute: 0, second: 0, of: t) ?? t
        return four > t ? cal.date(byAdding: .day, value: -1, to: four) ?? four : four
    }

    /// The Monday 4 am that starts the week `t` belongs to.
    nonisolated public static func weekStart(of t: Date) -> Date {
        let cal = calendar, day = dayStart(of: t)
        let back = (cal.component(.weekday, from: day) + 5) % 7      // Monday 0 … Sunday 6 (Sunday is weekday 1)
        return cal.date(byAdding: .day, value: -back, to: day) ?? day
    }
}

extension LearnerPack {
    /// A counted phrase: `key.one` for one ("1 new word"), else `key` with `{n}` ("3 new words").
    public func counted(_ key: String, _ n: Int) -> String {
        n == 1 && strings["\(key).one"] != nil ? self("\(key).one") : self(key, ["n": "\(n)"])
    }
}
