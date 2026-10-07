import Foundation

// MARK: - Growth, checked end to end (TOMO_SELFTEST; docs/verification.md)
//
// Beyond the rules' own checks in TomoProgress.selfTest: every level of every target pack can be finished, a birthday
// evolves Tomo once, and simulated learners grow on Tomo's clock, moved forward, with the real rules (waits, early
// reviews at half the wait, new words a day, levels needing 9 of 10) from the first word to the first talking
// question. The runs print how many days each step took: the pacing table for #38.

extension TomoProgress {
    /// The pack walk, the evolution and the simulated learners. `check` prints each result.
    static func growthSelfTest(_ check: (Bool, String) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-growth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let savedOffset = TomoClock.offset, savedNew = newPerDayForChecks
        defer { TomoClock.offset = savedOffset; TomoClock.stopped = nil; newPerDayForChecks = savedNew }
        newPerDayForChecks = 10                        // the default, whatever the learner chose in Settings

        packsSelfTest(check, in: dir)
        evolutionSelfTest(check)
        let lang = TomoLanguages.shared
        for pack in lang.targets {
            let learner = lang.learners.first { $0.id != pack.id } ?? lang.learner
            // Every pack to its first talking question; the small placeholder packs on to their last level.
            let toEnd = pack.levels.count <= 10
            for who in [TomoGrowthSim.perfect, TomoGrowthSim.realistic] {
                let sim = TomoGrowthSim(pack: pack, learner: learner, who: who,
                                        directory: dir.appendingPathComponent("sim-\(pack.id)-\(who.name)"))
                sim.run(toEnd: toEnd, maxDays: 1500)
                sim.report(check)
            }
        }
    }

    /// Every level of every target pack can be finished: enough of its items can be asked, each item is in one level,
    /// ages never go down, talking starts on the first level of the talking age, and the last level holds.
    static func packsSelfTest(_ check: (Bool, String) -> Void, in dir: URL) {
        let lang = TomoLanguages.shared
        for pack in lang.targets {
            let learner = lang.learners.first { $0.id != pack.id } ?? lang.learner
            let p = TomoProgress(pack: pack, learner: learner.id, directory: dir.appendingPathComponent("packs-\(pack.id)"))
            let levels = pack.levels, ids = levels.flatMap(\.itemIDs), name = "\(pack.id) → \(learner.id)"
            guard let first = levels.first else { check(false, "\(name): the pack has levels"); continue }
            check(first.age >= 1, "\(name): \(levels.count) levels, \(ids.count) items, from \(pack.ageLabel(first.age))")

            let repeated = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted()
            check(repeated.isEmpty, "\(name): every item is in one level, once"
                  + (repeated.isEmpty ? "" : " (repeated: \(repeated.prefix(5).joined(separator: ", ")))"))

            let younger = levels.indices.dropFirst().filter { levels[$0].age < levels[$0 - 1].age }.map { $0 + 1 }
            check(younger.isEmpty, "\(name): ages never go down from one level to the next"
                  + (younger.isEmpty ? "" : " (Lv \(younger.prefix(5).map(String.init).joined(separator: ", ")))"))

            var short: [String] = []
            for (i, level) in levels.enumerated() {
                let askable = level.itemIDs.filter { p.canAsk($0, learner: learner) }.count
                let needed = needed(of: level.itemIDs.count)
                if askable < needed { short.append("Lv \(i + 1): \(askable) of \(needed)") }
            }
            check(short.isEmpty, "\(name): every level has enough words a round can ask to finish it"
                  + (short.isEmpty ? "" : " (\(short.prefix(5).joined(separator: "; ")))"))

            let talk = levels.firstIndex { !($0.starters ?? []).isEmpty }
            let talkAge = levels.firstIndex { $0.age >= TomoGame.chatStage }
            check(talk == talkAge, "\(name): talking starts on the first level of \(pack.ageLabel(TomoGame.chatStage))"
                  + " (Lv \(talk.map { "\($0 + 1)" } ?? "none"))")

            // The last level, done: Tomo stays on it (there's no level after), the bar is full, nothing is left to
            // learn, and a testing age past the levels lands there.
            let last = levels.count, now = TomoClock.now
            p.level = last
            p.age = levels[last - 1].age
            for id in ids {
                p.items[id] = Item(id: id, stage: TomoSRS.knows, due: now.addingTimeInterval(7 * 86400),
                                   introduced: now.addingTimeInterval(-30 * 86400), answered: now.addingTimeInterval(-86400),
                                   right: 5, wrong: 0, peak: TomoSRS.knows)
            }
            check(p.isLastLevel && p.levelDone && p.levelUpIfReady() == nil && p.level == last && p.levelProgress == 1
                  && p.levelLeft.words == 0 && !p.canTeachNew && p.nextFreePlayItem() == nil && p.nextCountsAt != nil
                  && pack.firstLevel(age: levels[last - 1].age + 1) == last,
                  "\(name): the last level (Lv \(last)) done: Tomo stays, the bar is full, it rests until a review")
        }
    }

    /// A round can ask this item: a word or a talking question, with its right choice and two wrong ones.
    func canAsk(_ id: String, learner: LearnerPack) -> Bool {
        func fair(_ q: TomoRound) -> Bool {
            let choices = q.choices.map(\.id)
            return !q.say.isEmpty && !q.meaning.isEmpty && choices.contains(q.answer) && choices.count >= 3
                && Set(choices).count == choices.count
        }
        if let r = round(id) {
            return fair(TomoRound(r, learner: learner, otherMeanings: otherMeanings(for: id, learner: learner.id)))
        }
        guard let s = starter(id) else { return false }
        return [TomoRoundKind.meaning, .reply].allSatisfy {
            fair(TomoRound(s, kind: $0, others: pack.allStarters, learner: learner, praise: pack.lines.levelUp))
        }
    }

    /// A birthday evolves Tomo once: hearing it twice (the iPhone's view sees the age change, and the game says so)
    /// mustn't cut the evolution short.
    static func evolutionSelfTest(_ check: (Bool, String) -> Void) {
        let blob = TomoBlob(look: .mascot)
        var t = 100.0
        blob.clock = { t }
        blob.step()
        blob.grow(to: 1)
        blob.grow(to: 1)
        let evolving = blob.age == 0
        t += 0.6
        blob.step()
        check(evolving && blob.age == 1, "a birthday heard twice still evolves Tomo: the old shape, then the new one")
    }
}

/// A learner simulated on Tomo's clock: answers rounds the way the game asks them, and checks after each answer that
/// growth holds (level and age never go down, the bar is full only when the level is done and never moves back within
/// a level, "ready now" is true, every level-up and birthday is logged, birthdays land on the pack's age boundaries).
@MainActor
final class TomoGrowthSim {
    struct Learner {
        var name: String
        var right: Double                          // share of rounds answered right the first time
        var visits: [Double]                       // hours of the day Tomo drops in (up to 3 answers each)
        var freePlay: (hour: Double, answers: Int)?   // a free-play sitting each day
        var anyTime: Bool                          // plays the moment anything counts, day and night
    }
    /// Always right, and plays the moment anything counts: the fastest Tomo can grow.
    static let perfect = Learner(name: "perfect", right: 1, visits: [], freePlay: nil, anyTime: true)
    /// About 85% right the first time, 3 visits a day, and 10 answers of free play in the evening.
    static let realistic = Learner(name: "realistic", right: 0.85, visits: [8.5, 12.5, 19], freePlay: (21, 10),
                                   anyTime: false)

    let pack: TargetPack
    let learner: LearnerPack
    let who: Learner
    let p: TomoProgress
    let start: Date
    private var random: UInt64 = 0x9E3779B97F4A7C15
    private(set) var failures: [String] = []
    private(set) var reached: [Int: Double] = [:]        // level → day
    private(set) var birthdays: [Int: Int] = [:]         // age → level
    private(set) var answers = 0
    private(set) var talked: Double?                     // the day the first talking question was answered
    private var logged: [(kind: String, value: Int)] = []
    private var lastLevel = 1, lastAge = 1, bar = 0.0

    /// Starts at 8:00 today, on a new Tomo in `directory`.
    init(pack: TargetPack, learner: LearnerPack, who: Learner, directory: URL) {
        self.pack = pack
        self.learner = learner
        self.who = who
        let eight = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        start = eight
        TomoClock.stopped = eight                      // a clock that moves only when the run moves it: same run every time
        p = TomoProgress(pack: pack, learner: learner.id, directory: directory)
        lastAge = p.age
    }

    private var day: Double { TomoClock.now.timeIntervalSince(start) / 86400 }
    private var talkLevel: Int? { pack.levels.firstIndex { !($0.starters ?? []).isEmpty }.map { $0 + 1 } }
    private var done = false, toEnd = false

    private func fail(_ what: String) {
        if failures.count < 5 { failures.append("day \(String(format: "%.1f", day)), Lv \(p.level): \(what)") }
    }

    /// Runs until the first talking question is answered (or, `toEnd`, until the last level is done), or `maxDays`.
    func run(toEnd: Bool, maxDays: Double) {
        self.toEnd = toEnd
        let cal = Calendar.current
        var d = 0
        while !done && day < maxDays && failures.isEmpty {
            if who.anyTime {
                if let id = p.nextFreePlayItem() {
                    answer(id)
                } else if let at = p.nextCountsAt {
                    TomoClock.stopped = max(at, TomoClock.now).addingTimeInterval(1)
                } else {
                    fail("nothing counts, and nothing will")
                }
            } else {
                guard let date = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: start)) else { break }
                d += 1
                for hour in who.visits + [who.freePlay?.hour].compactMap({ $0 }) where !done {
                    TomoClock.stopped = date.addingTimeInterval(hour * 3600)
                    if hour == who.freePlay?.hour, let n = who.freePlay?.answers {
                        for _ in 0..<n where !done {               // free play, until Tomo rests
                            guard let id = p.nextFreePlayItem() else { break }
                            answer(id)
                        }
                    } else {
                        for id in p.visitItems(limit: DropIn.roundsPerVisit) where !done { answer(id) }   // a visit
                    }
                }
            }
            if toEnd && p.isLastLevel && p.levelDone { done = true }
        }
        if !done && failures.isEmpty { fail("didn't get there in \(Int(maxDays)) days") }
        if toEnd && done {
            check(p.levelUpIfReady() == nil && p.level == pack.levels.count && p.levelProgress == 1,
                  "the last level done, Tomo stays on it with a full bar")
        }
    }

    private func check(_ c: Bool, _ what: String) { if !c { fail(what) } }

    /// One round, answered the way this learner does: a miss first now and then, then right.
    private func answer(_ id: String) {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        let miss = Double(random >> 11) / Double(1 << 53) >= who.right
        if talkLevel == p.level, p.items[id] == nil, p.levelItems.contains(id) {
            check(p.isStarter(id) && p.canAsk(id, learner: learner), "the talking level's new items are talking questions")
        }
        p.answeredRight(id, mode: "sim", wrongTries: miss ? 1 : 0, hint: false)
        answers += 1
        TomoClock.stopped = TomoClock.now.addingTimeInterval(15)
        if p.isStarter(id), talked == nil {
            talked = day
            if !toEnd { done = true }
        }
        observe()
        if let up = p.levelUpIfReady() { leveled(up) }
        check(!p.levelDone || p.isLastLevel, "a done level levels up right away")
    }

    /// After each answer: what the bar and the card say holds up.
    private func observe() {
        check(p.level >= lastLevel && p.age >= lastAge, "level and age never go down")
        check(p.levelDone || p.levelProgress <= 1 - TomoProgress.goalShare + 1e-9,
              "the bar isn't full before the level is done")
        check(p.levelStanding <= p.levelProgress + 1e-9, "where the words stand is never past the bar")
        if p.level == lastLevel { check(p.levelProgress >= bar - 1e-9, "the bar never moves back within a level") }
        bar = p.levelProgress
        let left = p.levelLeft, now = TomoClock.now
        if left.words > 0 {
            let counts = p.levelItems.contains { id in
                guard let i = p.items[id] else { return p.canTeachNew }
                return i.stage < TomoSRS.knows && (p.isDue(id) || p.isEarlyOK(id))
            }
            let next = left.nextAt.map { "in \(Int($0.timeIntervalSince(now))) s" } ?? "now"
            check(left.nextAt.map { $0 > now && !counts } ?? counts,
                  "\"ready now\" only when a word of the level counts now (\(left.words) left, next \(next), counts: \(counts))")
        }
        lastLevel = p.level
        lastAge = p.age
    }

    private func leveled(_ up: (level: Int, birthday: Bool)) {
        let older = pack.levels[up.level - 1].age > pack.levels[up.level - 2].age
        check(up.level == lastLevel + 1, "one level at a time")
        check(up.birthday == older && p.age == pack.levels[up.level - 1].age,
              "a birthday exactly where the pack's age goes up (\(pack.ageLabel(p.age)))")
        reached[up.level] = day
        logged.append(("level", up.level))
        if up.birthday {
            birthdays[p.age] = up.level
            logged.append(("age", p.age))
        }
        bar = p.levelProgress
        check(bar == 0 || p.levelDone, "a new level starts with an empty bar")
        lastLevel = p.level
        lastAge = p.age
    }

    /// Checks the run and prints its pacing line.
    func report(_ check: (Bool, String) -> Void) {
        let name = "\(pack.id) \(who.name)"
        let log = p.growthLog()
        check(log.map(\.kind) == logged.map(\.kind) && log.map(\.value) == logged.map(\.value),
              "\(name): every level-up (\(reached.count)) and birthday (\(birthdays.count)) is logged")
        // The pack's age boundaries up to where the run got, and the birthdays that happened.
        let boundaries = pack.levels.indices.dropFirst()
            .filter { pack.levels[$0].age > pack.levels[$0 - 1].age && $0 < p.level }
        let expected = Dictionary(uniqueKeysWithValues: boundaries.map { (pack.levels[$0].age, $0 + 1) })
        check(birthdays == expected, "\(name): birthdays at "
              + expected.sorted { $0.key < $1.key }.map { "\(pack.ageLabel($0.key)) Lv \($0.value)" }.joined(separator: ", "))
        check(failures.isEmpty, "\(name): growth holds for \(answers) answers"
              + (failures.isEmpty ? "" : ": " + failures.joined(separator: " | ")))
        print("pace  " + pacing(name))
    }

    /// "ja perfect: Lv 2 0.8 d (19 h) · Lv 5 … · 2さい (Lv 16) …", in days from the run's start.
    func pacing(_ name: String) -> String {
        func days(_ d: Double?) -> String { d.map { String(format: "%.1f d", $0) } ?? "–" }
        var parts = [2, 5, 10].filter { $0 <= pack.levels.count }.map { "Lv \($0) \(days(reached[$0]))" }
        if let lv2 = reached[2] { parts[0] += String(format: " (%.0f h)", lv2 * 24) }
        parts += birthdays.keys.sorted().map { "\(pack.ageLabel($0)) (Lv \(birthdays[$0]!)) \(days(reached[birthdays[$0]!]))" }
        if let talked { parts.append("first talk \(days(talked))") }
        return "\(name): " + parts.joined(separator: " · ") + " · \(answers) answers"
    }
}
