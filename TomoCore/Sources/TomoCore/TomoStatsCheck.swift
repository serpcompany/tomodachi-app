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
                     var practiced: [String] = []; var answered: [String: Int] = [:] }
        var days: [Int: Day] = [:], levelAfter: [Int: Int] = [:], visits = 0, ignored = 0, n = 0
        var firstAnswer: Date?
        var stages: [String: [(at: Date, stage: Int)]] = [:]      // each word's stage after each answer, for the replay
        var grewAt: [Int: Date] = [:]                              // when each level was reached, for the pillar
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
                if !d.practiced.contains(id) { d.practiced.append(id) }
            }
            days[day] = d
            stages[id, default: []].append((TomoClock.now, after))
            if let up = p.levelUpIfReady() { grewAt[up.level] = TomoClock.now }
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
                s.practiced += d.practiced.filter { !s.practiced.contains($0) }
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
                && a.practiced == b.practiced
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

        // The garden: every word met, at its stage now; the replay's stages from the log; the ranges.
        let plants = stats.garden()
        check(plants.count == p.items.count && plants.map(\.met) == plants.map(\.met).sorted()
              && plants.allSatisfy { p.items[$0.id]?.stage == $0.stage && $0.pale == ((p.items[$0.id]?.stage ?? 0) < (p.items[$0.id]?.peak ?? 0)) },
              "stats: the garden has every word met (\(plants.count)), oldest first, at its stage now, pale when it slipped (\(plants.filter(\.pale).count))")
        let replayed = (0...20).allSatisfy { d in
            let t = at(d, 23.9)
            return plants.allSatisfy { plant in
                plant.stage(at: t) == (stages[plant.id]?.last { $0.at <= t }?.stage ?? 0)
            }
        }
        check(replayed, "stats: the replay's stage of every word at the end of every day matches the learner's own record")
        check(same(stats.summary(.today), tally(20...20)) && same(stats.summary(.week), tally(19...20))
              && same(stats.summary(.all), tally(0...20)),
              "stats: today, this week (from Monday 5 October) and since we met match the tally, waterings included (\(stats.summary(.week).practiced.count) watered this week)")
        let weekRecap = stats.recap(stats.summary(.week), range: stats.rangeText(.week, ui), ui)
        check(weekRecap.hasPrefix(ui("postcard.recap.title", ["range": stats.rangeText(.week, ui)]))
              && weekRecap.contains(stats.counts(stats.summary(.week), ui).map(\.text).joined(separator: " · "))
              && stats.rangeText(.week, ui) == "Oct 5–Oct 6",
              "stats: Copy recap says the range and its numbers: \(weekRecap.split(separator: "\n").prefix(2).joined(separator: " / "))")

        // The height pillar: a mark for every level reached, dated when the learner reached it, birthdays where the
        // pack's age goes up, and the next birthday ahead.
        let marks = stats.marks()
        check(marks.map(\.level) == Array(1...p.level) && marks.first?.at == p.metAt
              && marks.dropFirst().allSatisfy { grewAt[$0.level] == $0.at }
              && marks.allSatisfy { $0.birthday == ($0.level == 1 || pack.levels[$0.level - 1].age > pack.levels[$0.level - 2].age)
                                    && $0.age == pack.levels[$0.level - 1].age },
              "stats: the pillar has a mark per level (\(marks.count)), each dated when the learner reached it, birthdays where the age goes up")
        let firstBirthday = (pack.levels.indices.first { pack.levels[$0].age > pack.levels[0].age } ?? 0) + 1
        check(stats.nextBirthday?.level == firstBirthday && stats.nextBirthday?.age == pack.levels[firstBirthday - 1].age,
              "stats: the next birthday on the pillar is \(pack.ageLabel(stats.nextBirthday?.age ?? 0)) at Lv \(firstBirthday)")
        check((1...p.level).allSatisfy { lv in grewAt[lv].map { stats.level(at: $0) == lv && stats.level(at: $0.addingTimeInterval(-1)) == lv - 1 } ?? true },
              "stats: sliding back in time, Tomo's level on each mark's day is that mark's level, and one less just before")

        // Tomo's diary: a page for every day the learner played, its numbers that day's, the days apart before it, the
        // run of days, and Tomo's words: hello on the first day, a sulk after days apart, a cheer on a run, a やったー on
        // a day it grew, and see you.
        let diary = stats.diary(ui), playedDays = (0...20).filter(played.contains)
        let ja = pack.diaryLines(age: 1)
        check(diary.map(\.day) == playedDays.map { at($0, 4) }
              && zip(diary, playedDays).allSatisfy { same($0.summary, tally($1...$1)) && $0.streak == run(endingOn: $1) },
              "stats: the diary has a page for every day played (\(diary.count)), each with that day's numbers and run of days")
        let apart = Dictionary(uniqueKeysWithValues: zip(playedDays.dropFirst(), playedDays).map { ($0, $0 - $1 - 1) })
        check(zip(diary, playedDays).allSatisfy { $0.apart == (apart[$1] ?? 0) } && diary.contains { $0.apart == 7 },
              "stats: each page knows the days apart before it (7 after the quiet week)")
        let hello = pack.lines.hello?.say ?? "-", bye = pack.postcard?.bye.say ?? "-"
        check(diary.first?.first == true && diary.first?.message.hasPrefix(hello) == true
              && diary.allSatisfy { $0.message.hasSuffix(bye) && $0.first == ($0.day == diary.first?.day) },
              "stats: the first page starts with \(hello), and every page signs off \(bye)")
        check(diary.allSatisfy { ($0.apart > 0) == $0.message.contains(ja?.missed.say ?? "-") }
              && diary.first { $0.apart == 7 }?.gloss.contains(ja?.missed.translation("en") ?? "-") == true,
              "stats: after days apart Tomo sulks (\(ja?.missed.say ?? "")), and only then")
        let grewDays = playedDays.filter { level(endOf: $0) > ($0 == 0 ? 1 : level(endOf: $0 - 1)) }
        check(zip(diary, playedDays).allSatisfy { page, d in
                  page.message.contains(pack.postcard?.grew.say ?? "-") == grewDays.contains(d)
                  && page.message.contains(ja?.streak.say ?? "-") == (page.streak >= 3 && page.apart == 0)
              } && !grewDays.isEmpty,
              "stats: Tomo cheers on the days it grew (\(grewDays.count)) and on runs of 3 days or more")
        check(diary.allSatisfy { $0.facts.allSatisfy { !$0.text.hasPrefix("0") } }
              && diary.last.map { stats.diaryText($0, ui).contains($0.message) } == true,
              "stats: no page lists a zero, and Copy this page has Tomo's words")

        // The learner's own log: JSON that reads back, and Markdown with a row for every week, word and answer.
        let json = stats.exportJSON(ui), log = TomoLogExport.decode(json)
        let answerRows = p.answerLog(from: start, to: at(21, 4)).count
        check(log?.answers.count == answerRows && log?.words.count == p.items.count
              && log?.growth.count == p.growthEvents().count && log?.visits.count == visits + ignored + 2
              && log?.answers.first?.word == stats.garden().first?.id && log?.tomo.level == p.level,
              "stats: the JSON export reads back with every answer (\(answerRows)), word, level-up and visit")
        let md = stats.exportMarkdown(ui), tableRows = md.split(separator: "\n").filter { $0.hasPrefix("| ") }.count
        check(md.hasPrefix("# \(ui("export.title"))") && tableRows == 6 + (weeks.count + 1) + p.items.count + answerRows,
              "stats: the Markdown export has a row for every week (\(weeks.count) and this one), word and answer")
        // Its answers' times are on the person's own clock, in each language (#197): an afternoon answer reads
        // "6:29 PM" or "18:29", 「午後6:29」 or 「18:29」, as the device's 12- or 24-hour setting says.
        if let pm = log?.answers.map(\.at).first(where: { Calendar.current.component(.hour, from: $0) >= 13 }) {
            var rows: [String] = []
            for learner in lang.learners {
                for cycle in [Locale.HourCycle.oneToTwelve, .zeroToTwentyThree] {
                    let f = DateFormatter()
                    f.locale = tomoClockLocale(learner.id, hourCycle: cycle)
                    f.dateStyle = .short
                    f.timeStyle = .short
                    let time = f.string(from: pm), twelve = cycle == .oneToTwelve
                    check(stats.exportMarkdown(learner, hourCycle: cycle).contains("| \(time) |")
                          && time.contains(f.pmSymbol) == twelve,
                          "stats: in \(learner.id) on a \(twelve ? 12 : 24)-hour clock, the Markdown export writes an "
                          + "afternoon answer's time \"\(time)\"")
                    rows.append(time)
                }
            }
            check(Set(rows).count == rows.count, "stats: each language and clock writes it its own way (\(rows))")
        } else {
            check(false, "stats: the simulated learner answers in the afternoon")
        }

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
        check(none.weeks().isEmpty && none.since == nil && none.todayLine(ui) == ui("today.nothing") && none.garden().isEmpty
              && first.isFirst && first.facts.map(\.id) == ["first"] && first.message.hasPrefix(pack.lines.hello?.say ?? "-"),
              "stats: a brand-new Tomo has an empty garden, no weeks, nothing yet today, and a first postcard: \(first.message)")
        check(none.marks().map(\.level) == [1] && none.marks().first?.at == fresh.metAt && none.marks().first?.birthday == true,
              "stats: a brand-new Tomo's pillar has one mark, the day it hatched")
        // A Tomo that grew on another device: its levels are on the pillar, undated here.
        TomoStore(learner: "fr", target: pack.id, directory: dir)?.saveTomo(.init(metAt: at(0, 8), level: 12, age: 1))
        let elsewhere = TomoStats(TomoProgress(pack: pack, learner: "fr", directory: dir)).marks()
        check(elsewhere.count == 12 && elsewhere.dropFirst().allSatisfy { $0.at == nil },
              "stats: levels grown on another device are on the pillar, without a day")
        check(none.diary(ui).isEmpty, "stats: a brand-new Tomo's diary has no pages yet")
        // A hard day: many misses, and Tomo groans about it.
        let hard = TomoProgress(pack: pack, learner: "it", directory: dir)
        for (k, id) in hard.visitItems(limit: 1).prefix(1).enumerated() where k == 0 {
            for _ in 0..<6 { hard.logTry(id, mode: "sim", result: "wrong") }
            hard.answeredRight(id, mode: "sim", wrongTries: 6, hint: false)
        }
        let hardPage = TomoStats(hard).diary(ui).last
        check(hardPage?.summary.misses == 6 && hardPage?.message.contains(ja?.hard.say ?? "-") == true,
              "stats: on a hard day (6 misses) Tomo groans: \(hardPage?.message ?? "")")
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
        daysTogetherSelfTest(check)
    }

    /// "Day N together" (#224): the diary's page for today and the Tomo screen say the same day, counted on Tomo's 4 am
    /// days from the day it hatched (Day 1), in English and Japanese. One Tomo hatches in New York on the Friday evening
    /// before the clocks go back (Sunday 1 November 2026, 2 am), one on the Saturday morning before they go forward
    /// (Sunday 14 March 2027), and one in Tokyo before its learner flies to Los Angeles. At each moment the learner
    /// answers a word, so today has a page: late in the day, later than Tomo hatched, and just after midnight (still the
    /// day before's page) among them. Then every page's day follows from the first page's (Day 1) and the days apart.
    static func daysTogetherSelfTest(_ check: (Bool, String) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-days-\(UUID().uuidString)")
        let zone = NSTimeZone.default, savedNew = TomoProgress.newPerDayForChecks
        defer {
            try? FileManager.default.removeItem(at: dir)
            NSTimeZone.default = zone
            TomoClock.stopped = nil
            TomoProgress.newPerDayForChecks = savedNew
        }
        TomoProgress.newPerDayForChecks = 10
        let lang = TomoLanguages.shared
        guard let pack = lang.targets.first(where: { $0.id == "ja" }),
              let en = lang.learners.first(where: { $0.id == "en" }), let ja = lang.learners.first(where: { $0.id == "ja" })
        else { check(false, "days together: the Japanese pack and both interfaces load"); return }

        // A time on a zone's own clock: [year, month, day, hour, minute].
        func date(_ zone: String, _ c: [Int]) -> Date? {
            guard let tz = TimeZone(identifier: zone) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            return cal.date(from: DateComponents(year: c[0], month: c[1], day: c[2], hour: c[3], minute: c[4]))
        }
        let ny = "America/New_York", tokyo = "Asia/Tokyo", la = "America/Los_Angeles"
        // Each Tomo: where and when it hatched, then each moment and the day it's on (the day it hatched is Day 1).
        let tomos: [(name: String, zone: String, met: [Int], moments: [(zone: String, at: [Int], day: Int)])] = [
            ("the night the clocks go back", ny, [2026, 10, 30, 18, 0], [
                (ny, [2026, 10, 30, 23, 0], 1), (ny, [2026, 10, 31, 0, 30], 1),     // just after midnight: the hatch day
                (ny, [2026, 10, 31, 20, 0], 2),                                     // later in the day than it hatched
                (ny, [2026, 11, 1, 0, 30], 2), (ny, [2026, 11, 1, 1, 30], 2),       // the hour that comes twice
                (ny, [2026, 11, 1, 10, 0], 3), (ny, [2026, 11, 2, 0, 30], 3),       // after the 25-hour day
                (ny, [2026, 11, 2, 9, 0], 4)]),
            ("the night the clocks go forward", ny, [2027, 3, 13, 9, 0], [
                (ny, [2027, 3, 14, 0, 30], 1), (ny, [2027, 3, 14, 3, 30], 1),       // 3:30 comes after 1:59, before 4 am
                (ny, [2027, 3, 14, 4, 30], 2), (ny, [2027, 3, 15, 0, 30], 2),       // after the 23-hour day
                (ny, [2027, 3, 15, 10, 0], 3)]),
            ("a flight from Tokyo to Los Angeles", tokyo, [2026, 10, 1, 21, 0], [
                (tokyo, [2026, 10, 1, 23, 0], 1), (tokyo, [2026, 10, 2, 0, 30], 1), (tokyo, [2026, 10, 2, 21, 30], 2),
                // In Los Angeles Tomo hatched at 5 am on Thursday 1 October, so Friday is still Day 2.
                (la, [2026, 10, 2, 10, 0], 2), (la, [2026, 10, 3, 0, 30], 2), (la, [2026, 10, 3, 9, 0], 3)]),
        ]
        for (k, tomo) in tomos.enumerated() {
            guard let met = date(tomo.zone, tomo.met), let hatchZone = TimeZone(identifier: tomo.zone) else {
                check(false, "days together: \(tomo.zone) is a time zone"); continue
            }
            let folder = dir.appendingPathComponent("tomo-\(k)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSTimeZone.default = hatchZone
            TomoClock.stopped = met
            let p = TomoProgress(pack: pack, learner: "en", directory: folder)
            for m in tomo.moments {
                guard let t = date(m.zone, m.at), let here = TimeZone(identifier: m.zone) else { continue }
                NSTimeZone.default = here
                TomoClock.stopped = t
                if let id = p.nextFreePlayItem() ?? p.practiceItem(after: nil, talk: false) {
                    p.answeredRight(id, mode: "sim", wrongTries: 0, hint: false)
                }
                // What each screen shows: the diary's newest page (today's) and the Tomo screen, in each language.
                let shown = [en, ja].map { ui in
                    let page = TomoStats(p).diary(ui).last
                    return (today: page?.day == dayStart(of: t),
                            diary: page.map { ui("words.days", ["n": "\($0.dayNumber)"]) } ?? "-",
                            tomo: ui("words.days", ["n": "\(p.daysTogether)"]), expected: ui("words.days", ["n": "\(m.day)"]))
                }
                let stamp = String(format: "%04d-%02d-%02d %02d:%02d", m.at[0], m.at[1], m.at[2], m.at[3], m.at[4])
                check(shown.allSatisfy { $0.today && $0.diary == $0.tomo && $0.tomo == $0.expected },
                      "days together (\(tomo.name)): at \(stamp) in \(m.zone), today's diary page and the Tomo screen say "
                      + shown.map { "\"\($0.diary)\" and \"\($0.tomo)\"" }.joined(separator: ", ")
                      + " (expected \(shown.map(\.expected).joined(separator: ", ")))")
            }
            let pages = TomoStats(p).diary(en)
            check(pages.first?.first == true && pages.first?.dayNumber == 1
                  && zip(pages.dropFirst(), pages).allSatisfy { $0.dayNumber == $1.dayNumber + $0.apart + 1 }
                  && pages.map(\.dayNumber) == Array(Set(tomo.moments.map(\.day))).sorted(),
                  "days together (\(tomo.name)): the first page is Day 1, and each page's day follows from the days apart "
                  + "(\(pages.map(\.dayNumber)))")
        }
    }
}
