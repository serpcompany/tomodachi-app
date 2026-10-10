import Foundation

// MARK: - The stats layer, checked against a simulated learner (TOMO_SELFTEST; docs/verification.md)
//
// A learner plays three weeks on Tomo's stopped clock with the real rules, from a Wednesday: three visits a day, an
// ignored one, free play in the evening (answers that count, then two that are practice), a miss now and then, a
// quiet Sunday, a whole quiet week and an answer at 3:59 on a Monday morning. The run keeps its own tally of what it
// did, by its own idea of the day (before 4 am is still the day before), and TomoStats has to agree: today, every
// week, the Today line and the postcards, the misses, and the streak: the 3:59 answer keeps Sunday in it (the 4 am
// boundary), the quiet week breaks it, and it waits on today until today is over. Then: a quiet week's postcard is
// light (Tomo asleep, no zeros), ignored visits are counted and left off the Today line and the postcards (a choice for
// now), a brand-new Tomo has its own first postcard, and start over begins the stats again.

extension TomoStats {
    static func selfTest(_ check: (Bool, String) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-stats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let savedNew = TomoProgress.newPerDayForChecks
        defer { TomoClock.stopped = nil; TomoProgress.newPerDayForChecks = savedNew }
        TomoProgress.newPerDayForChecks = 10
        let lang = TomoLanguages.shared
        guard let pack = lang.targets.first(where: { $0.id == "ja" }), let ui = lang.learners.first(where: { $0.id == "en" })
        else { check(false, "stats: the Japanese pack and the English interface load"); return }

        // Wednesday 16 September 2026, 8:00: a short first week (Wed–Sun), then Monday 21, 28 and 5 October.
        let cal = calendar
        guard let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 8)) else { return }
        func at(_ day: Int, _ hour: Double) -> Date {
            (cal.date(byAdding: .day, value: day, to: start) ?? start).addingTimeInterval((hour - 8) * 3600)
        }
        TomoClock.stopped = start
        let p = TomoProgress(pack: pack, learner: "en", directory: dir)

        // The run's own tally, by day (day 0 is the Wednesday; before 4 am counts for the day before).
        struct Day { var answers = 0, wins = 0, practice = 0, misses = 0; var new: [String] = [], moved: [String] = []
                     var answered: [String: Int] = [:] }
        var days: [Int: Day] = [:], levelAfter: [Int: Int] = [:], visits = 0, ignored = 0, n = 0
        var firstAnswer: Date?
        func answer(_ id: String, day: Int, practice: Bool = false) {
            n += 1
            firstAnswer = firstAnswer ?? TomoClock.now
            let miss = !practice && n % 7 == 3
            if miss {
                p.logTry(id, mode: "sim", result: "wrong")
                days[day, default: Day()].answers += 1
                days[day, default: Day()].misses += 1
                days[day, default: Day()].answered[id, default: 0] += 1
            }
            let before = p.items[id]?.stage
            let counted = p.answeredRight(id, mode: "sim", wrongTries: miss ? 1 : 0, hint: false)
            let after = p.items[id]?.stage ?? 0
            var d = days[day] ?? Day()
            d.answers += 1
            d.answered[id, default: 0] += 1
            if counted {
                d.wins += 1
                if before == nil { d.new.append(id) } else if after > before! { d.moved.append(id) }
            } else {
                d.practice += 1
            }
            days[day] = d
            _ = p.levelUpIfReady()
            levelAfter[day] = p.level
            TomoClock.stopped = TomoClock.now.addingTimeInterval(15)
        }
        func visit(day: Int, hour: Double, ignore: Bool = false) {
            TomoClock.stopped = at(day, hour)
            let began = TomoClock.now
            if ignore {
                p.logVisit(TomoVisit(started: began, opened: .peek, endedAt: began.addingTimeInterval(12), ended: .ignored))
                ignored += 1
                return
            }
            for id in p.visitItems(limit: DropIn.roundsPerVisit) { answer(id, day: day) }
            p.logVisit(TomoVisit(started: began, opened: .card, cardAt: began, endedAt: TomoClock.now, ended: .finished))
            visits += 1
        }

        let quiet = Set([4]).union(12...18)              // a quiet Sunday, and the whole week of 28 September
        for day in 0...20 where !quiet.contains(day) {
            if day == 5 {                                    // Monday 21, 3:59 am: still Sunday's, so the first week's
                TomoClock.stopped = at(day, 3.98)
                if let id = p.nextFreePlayItem() ?? p.practiceItem(after: nil, talk: false) {
                    answer(id, day: 4, practice: !p.counts(id))
                }
            }
            for hour in [8.5, 12.5, 19] { visit(day: day, hour: hour) }
            visit(day: day, hour: 15, ignore: true)
            TomoClock.stopped = at(day, 21)
            for _ in 0..<10 { guard let id = p.nextFreePlayItem() else { break }; answer(id, day: day) }
            for _ in 0..<2 {
                guard let id = p.items.keys.sorted().first(where: { !p.counts($0) }) else { break }
                answer(id, day: day, practice: true)
            }
        }
        TomoClock.stopped = at(20, 22)                       // Tuesday 6 October, 10 pm

        func level(endOf day: Int) -> Int { (0...max(day, 0)).reversed().lazy.compactMap { levelAfter[$0] }.first ?? 1 }
        // Days with an answer, by the run's own day numbers, and its runs of days in a row.
        let played = Set(days.filter { $0.value.answers > 0 }.keys)
        func run(endingOn day: Int) -> Int { var n = 0; while played.contains(day - n) { n += 1 }; return n }
        func longest(_ range: ClosedRange<Int>) -> Int { range.map { min(run(endingOn: $0), $0 - range.lowerBound + 1) }.max() ?? 0 }
        func tally(_ range: ClosedRange<Int>) -> Summary {
            var s = Summary(from: .distantPast, to: .distantPast)
            for d in range.compactMap({ days[$0] }) {
                s.answers += d.answers; s.wins += d.wins; s.practice += d.practice; s.misses += d.misses
                s.newWords += d.new
                s.stronger += d.moved.filter { !s.stronger.contains($0) }
                d.answered.forEach { s.answered[$0.key, default: 0] += $0.value }
            }
            s.stronger = s.stronger.filter { !s.newWords.contains($0) }
            s.daysPlayed = range.filter(played.contains).count
            s.longestRun = longest(range)
            s.levelFrom = range.lowerBound == 0 ? 1 : level(endOf: range.lowerBound - 1)
            s.levelTo = level(endOf: range.upperBound)
            return s
        }
        func same(_ a: Summary, _ b: Summary) -> Bool {
            a.answers == b.answers && a.wins == b.wins && a.practice == b.practice && a.misses == b.misses
                && a.daysPlayed == b.daysPlayed && a.longestRun == b.longestRun && a.newWords == b.newWords
                && Set(a.stronger) == Set(b.stronger) && a.answered == b.answered
                && a.levelFrom == b.levelFrom && a.levelTo == b.levelTo
        }
        func show(_ s: Summary) -> String {
            "\(s.answers) answers, \(s.wins) wins, \(s.practice) practice, \(s.misses) misses, \(s.newWords.count) new, "
                + "\(s.stronger.count) stronger, \(s.daysPlayed) days, \(s.longestRun) in a row, Lv \(s.levelFrom) → \(s.levelTo)"
        }

        // The day and the week on Tomo's clock.
        check(dayStart(of: at(5, 3.98)) == at(4, 4) && dayStart(of: at(5, 4)) == at(5, 4)
              && weekStart(of: at(5, 3.98)) == at(-2, 4) && weekStart(of: at(5, 4)) == at(5, 4)
              && weekStart(of: at(11, 23)) == at(5, 4),
              "stats: a day starts at 4 am, and Tomo's week on Monday at 4 am (3:59 on a Monday is still Sunday's)")

        let stats = TomoStats(p)
        let t = stats.today, expectToday = tally(20...20)
        check(same(t, expectToday), "stats: today matches what the learner did (\(show(t)))")
        let line = stats.todayLine(ui)
        let expectLine = [ui.counted("today.answers", expectToday.answers)]
            + (expectToday.newWords.isEmpty ? [] : [ui.counted("today.newWords", expectToday.newWords.count)])
            + (run(endingOn: 20) >= 2 ? ["\(run(endingOn: 20)) days in a row"] : [])
            + (expectToday.grew ? ["Lv \(expectToday.levelFrom) → \(expectToday.levelTo)"] : [])
        check(line == expectLine.joined(separator: " · ") && line.contains("answers") && line.contains("2 days in a row"),
              "stats: the Today line says it, with the streak: \"\(line)\"")

        // The streak: days in a row with an answer, on Tomo's 4 am days. Sunday 20 September had only the 3:59 answer of
        // Monday morning, and still counts; the quiet week breaks it; from Monday 5 October it starts again.
        check(stats.streak(endingOn: at(4, 12)) == 5 && stats.streak(endingOn: at(5, 3.5)) == 5
              && stats.streak(endingOn: at(11, 12)) == run(endingOn: 11) && run(endingOn: 11) == 12,
              "stats: the streak keeps a day whose only answer was before 4 am the next morning (12 days to Sunday 27)")
        check(stats.streak(endingOn: at(18, 12)) == 0 && stats.currentStreak == 2 && run(endingOn: 20) == 2,
              "stats: a quiet week breaks the streak, and it starts again (2 days now)")
        check(stats.missedDays(from: start, to: at(21, 4)) == 7 && (0...19).filter { !played.contains($0) }.count == 7,
              "stats: the missed days are the quiet week's 7")
        check(expectToday.misses > 0 && stats.today.misses == expectToday.misses,
              "stats: today's misses: \(stats.today.misses)")

        let weeks = stats.weeks()
        let expected = [tally(0...4), tally(5...11), tally(12...18)]
        check(weeks.count == 3 && weeks.first?.from == firstAnswer && weeks.first?.to == at(5, 4)
              && weeks.last?.to == at(19, 4),
              "stats: three finished weeks, the first from the first answer (Wednesday) to Monday 4 am")
        for (k, (w, e)) in zip(weeks, expected).enumerated() {
            check(same(w, e), "stats: week \(k + 1) matches the learner's own tally (\(show(w)))")
        }
        check(weeks.contains { $0.grew } && weeks.allSatisfy { $0.levelTo >= $0.levelFrom },
              "stats: Tomo grew in a week, and no week's level goes down")

        // Postcards: every number from the week, never a zero, the week's picture word on the front.
        let cards = stats.postcards(ui)
        check(cards.count == 3 && zip(cards, weeks).allSatisfy { $0.id == dayStart(of: $1.from) },
              "stats: a postcard for each finished week")
        if cards.count == 3, weeks.count == 3 {
            let card = cards[1], w = weeks[1], e = expected[1]
            let words = Dictionary(uniqueKeysWithValues: card.facts.map { ($0.id, $0.text) })
            check(words["new"] == ui.counted("postcard.newWords", e.newWords.count)
                  && words["wins"] == ui.counted("postcard.wins", e.wins)
                  && words["practice"] == ui.counted("postcard.practice", e.practice)
                  && words["misses"] == ui.counted("postcard.misses", e.misses) && e.misses > 0
                  && words["stronger"] == (w.stronger.isEmpty ? nil : ui.counted("postcard.stronger", w.stronger.count))
                  && words["streak"] == "7 days in a row" && e.longestRun == 7
                  && words["days"] == ui("words.days", ["n": "\(p.daysTogether(at: at(11, 4)))"]),
                  "stats: a played week's postcard has its numbers, misses and run: \(card.facts.map(\.text).joined(separator: " · "))")
            let firstWeek = Dictionary(uniqueKeysWithValues: cards[0].facts.map { ($0.id, $0.text) })
            check(firstWeek["streak"] == "5 days in a row" && expected[0].longestRun == 5,
                  "stats: the first week's run keeps Sunday, whose only answer was at 3:59 on Monday")
            let pictured = expected[1].answered.filter { p.word($0.key, learner: "en").emoji != nil }
            let most = pictured.values.max() ?? 0
            check(!card.asleep && card.picture != nil
                  && pictured.contains { p.word($0.key, learner: "en").say == card.word && $0.value == most },
                  "stats: its front is the week's most-answered picture word: \(card.word) \(card.picture ?? "")")
            check(card.message.hasPrefix(card.word) && card.message.hasSuffix(pack.postcard?.bye.say ?? "")
                  && !card.gloss.isEmpty,
                  "stats: Tomo's message starts with that word and signs off: \(card.message) / \(card.gloss)")
            let sleepy = cards[2]
            check(sleepy.asleep && sleepy.picture == nil && sleepy.word == pack.postcard?.asleep.say
                  && sleepy.facts.map(\.id) == ["level", "days"]
                  && sleepy.recap.split(separator: "\n").count == 3 && !cards.flatMap(\.facts).contains { $0.text.hasPrefix("0") },
                  "stats: a quiet week still gets a postcard, kept light: Tomo asleep, and no zeros")
            check(cards[0].recap.hasPrefix(ui("postcard.recap.title", ["range": cards[0].range]))
                  && cards[0].recap.hasSuffix(ui("postcard.recap.app")),
                  "stats: the shared text begins with the week and ends with the app: \(cards[0].recap.split(separator: "\n").first ?? "")")
        }

        // Ignored visits are in the log and counted, for the mood ladder and later screens; the Today line and the
        // postcards leave them off, a choice for now.
        let logged = stats.visits(from: start, to: at(21, 4))
        check(logged.count == visits + ignored && logged.filter { $0.ended == .ignored }.count == ignored
              && logged.allSatisfy { $0.endedAt != nil && ($0.opened == .peek) == ($0.cardAt == nil) },
              "stats: the visit log keeps every visit, how it opened and how it ended (\(visits) played, \(ignored) ignored)")
        check(stats.ignoredVisits(from: start, to: at(21, 4)) == ignored, "stats: it counts the ignored ones: \(ignored)")
        let shown = (stats.todayLine(ui), cards.map { $0.facts.map(\.text) + [$0.recap, $0.message] })
        for day in [6, 20] {
            let t0 = at(day, 16)
            p.logVisit(TomoVisit(started: t0, opened: .card, cardAt: t0, endedAt: t0.addingTimeInterval(10), ended: .ignored))
        }
        let again = TomoStats(p)
        check(again.todayLine(ui) == shown.0 && again.postcards(ui).map { $0.facts.map(\.text) + [$0.recap, $0.message] } == shown.1,
              "stats: the Today line and the postcards leave ignored visits off (for now)")

        // The postcard comes on Monday morning: Monday 5 October at 3:59 it isn't there yet, at 4 am it is, and that
        // Monday is the day it came.
        TomoClock.stopped = at(19, 3.98)
        let before = TomoStats(p).weeks().count
        TomoClock.stopped = at(19, 10)
        let monday = TomoStats(p), newest = monday.postcards(ui).last
        check(before == 2 && monday.weeks().count == 3 && monday.arrivedToday(newest)
              && monday.postcardCameToday(ui) == newest?.range,
              "stats: the week's postcard comes at 4 am on Monday, and that Monday the Tomo screen says so (\(newest?.range ?? ""))")
        TomoClock.stopped = at(20, 22)
        check(!TomoStats(p).arrivedToday(TomoStats(p).postcards(ui).last) && TomoStats(p).postcardCameToday(ui) == nil,
              "stats: on Tuesday it's just the latest one")
        // Before the day's first answer the streak waits on today; a day with none breaks it once it's over.
        TomoClock.stopped = at(21, 9)
        let waiting = TomoStats(p).todayLine(ui)
        TomoClock.stopped = at(22, 9)
        let broken = TomoStats(p)
        check(waiting == "Nothing yet today · 2 days in a row" && broken.currentStreak == 0
              && broken.todayLine(ui) == ui("today.nothing") && broken.missedDays(from: start, to: at(23, 4)) == 8,
              "stats: the next morning the streak waits (\"\(waiting)\"), and a day missed breaks it")
        TomoClock.stopped = at(20, 22)

        // A brand-new Tomo: no weeks, a Today line with nothing yet, and its own first postcard (no numbers).
        TomoClock.stopped = at(20, 22)
        let fresh = TomoProgress(pack: pack, learner: "es", directory: dir)
        let none = TomoStats(fresh), first = none.firstPostcard(ui)
        check(none.weeks().isEmpty && none.since == nil && none.todayLine(ui) == ui("today.nothing")
              && first.isFirst && first.facts.map(\.id) == ["first"] && first.message.hasPrefix(pack.lines.hello?.say ?? "-"),
              "stats: a brand-new Tomo has no weeks, nothing yet today, and a first postcard: \(first.message)")
        if let id = fresh.visitItems(limit: 1).first {
            fresh.answeredRight(id, mode: "sim", wrongTries: 0, hint: false)
            check(TomoStats(fresh).todayLine(ui) == "1 answer · 1 new word", "stats: one answer: \"\(TomoStats(fresh).todayLine(ui))\"")
        }

        // A testing Tomo has no logs; start over begins the stats again (the logs stay).
        let scratch = TomoProgress(pack: pack, learner: "en", directory: dir)
        scratch.scratch(age: 2)
        check(TomoStats(scratch).weeks().isEmpty && !TomoStats(scratch).today.played, "stats: a testing Tomo has none")
        TomoClock.stopped = at(20, 23)
        p.startOver()
        TomoClock.stopped = at(20, 23.5)
        let over = TomoStats(p)
        check(over.since == nil && over.weeks().isEmpty && !over.today.played
              && !(TomoStore(learner: "en", target: pack.id, directory: dir)?.answerLog(from: start, to: at(21, 4)).isEmpty ?? true),
              "stats: after start over the new Tomo's stats begin again, and the old logs stay")
    }
}
