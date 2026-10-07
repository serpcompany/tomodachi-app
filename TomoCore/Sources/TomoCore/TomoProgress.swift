import Foundation

// MARK: - How Tomo grows: word stages, levels and ages (issue #3, docs/concepts.md)
//
// Word stages follow WaniKani's published rules, written as our own code with our own names:
//   0 new · 1–4 just heard · 5–6 knows it · 7 good at it · 8 loves it · 9 forever (never asked again)
// An item moves when it's due, or early once at least half its wait has passed (so choosing to play counts).
// Answering again sooner is practice and changes nothing, so Tomo can't be crammed. Levels are the pack's `levels`: Tomo levels up when 90% of a level's items
// reach "knows it", which unlocks the next level. Each level has an age, so the level where the age goes
// up is Tomo's birthday. New items: at most one per visit and ten a day. Level and age never go down.
// Saved through TomoStore (one Tomo per learner × target pair).

public enum TomoSRS {
    public static let knows = 5            // "knows it": counts toward the next level
    public static let forever = 9          // never asked again

    /// Hours until the next review after reaching a stage. Day-sized waits are an hour short, so a word
    /// answered at 9 am is due again by 9 am. The first two levels start faster.
    private static let hours: [Int: Double] = [1: 4, 2: 8, 3: 23, 4: 47, 5: 167, 6: 335, 7: 719, 8: 2879]
    private static let fastHours: [Int: Double] = [1: 2, 2: 4, 3: 8, 4: 23]
    public static let fastLevels = 1...2

    public static func wait(after stage: Int, level: Int) -> TimeInterval? {
        let h = (fastLevels.contains(level) ? fastHours[stage] : nil) ?? hours[stage]
        return h.map { $0 * 3600 }
    }

    /// The stage's group, for display: new · heard (1–4) · knows (5–6) · good (7) · loves (8) · forever (9).
    public static func group(_ stage: Int) -> String {
        switch stage {
        case ...0:  return "new"
        case 1...4: return "heard"
        case 5...6: return "knows"
        case 7:     return "good"
        case 8:     return "loves"
        default:    return "forever"
        }
    }

    /// The stage after a new or due item is answered right. `wrongTries`: wrong answers earlier in the round.
    public static func next(after stage: Int, wrongTries: Int, hint: Bool) -> Int {
        if stage == 0 { return 1 }                                    // first right answer: just heard it
        if wrongTries > 0 {
            let drop = (wrongTries + 1) / 2 * (stage >= knows ? 2 : 1) // ceil(tries / 2), doubled from "knows it"
            return max(1, stage - drop)
        }
        return hint ? stage : min(stage + 1, forever)                 // after the hint: stays where it was
    }
}

/// Tomo's clock. Testing can move it ahead: TOMO_TIME_TRAVEL=<hours> for a test run, or Settings → "Skip ahead a
/// day", which only ever moves a testing Tomo (`TomoGame.skipAhead`).
@MainActor
public enum TomoClock {
    /// Where the clock starts: TOMO_TIME_TRAVEL, else now. Going back to the saved Tomo (`TomoGame.start`) puts
    /// it back here.
    public static let start: TimeInterval =
        (ProcessInfo.processInfo.environment["TOMO_TIME_TRAVEL"].flatMap(Double.init) ?? 0) * 3600
    public static var offset: TimeInterval = start
    public static var now: Date { Date().addingTimeInterval(offset) }

    /// The daily new-word limit resets at 4 am, like Anki.
    public static var dayStart: Date {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 4, minute: 0, second: 0, of: now) ?? now
        return start > now ? start.addingTimeInterval(-86400) : start
    }
}

@MainActor
public final class TomoProgress {
    public typealias Item = TomoStore.ItemRow

    /// New words a day (Settings → General): 5, 10, 20 or 30.
    public static var newPerDay: Int { UserDefaults.standard.object(forKey: "tomoNewPerDay") as? Int ?? 10 }
    public static let newPerDayChoices = [5, 10, 20, 30]
    public static let newPerVisit = 1
    /// An early review counts once this share of the word's wait has passed.
    public static let earlyShare = 0.5

    public private(set) var pack: TargetPack
    public private(set) var learner: String
    public private(set) var level = 1
    public private(set) var age = 1
    public private(set) var metAt = Date()
    public private(set) var items: [String: Item] = [:]
    /// Testing ages run on an in-memory Tomo; the saved one isn't touched.
    public private(set) var isScratch = false
    private var store: TomoStore?
    private var directory: URL
    private var levelOfItem: [String: Int] = [:]
    private var roundIndex: [String: TargetPack.Round] = [:]
    private var starterIndex: [String: TargetPack.Starter] = [:]

    public init(pack: TargetPack, learner: String, directory: URL = TomoStore.directory) {
        self.pack = pack
        self.learner = learner
        self.directory = directory
        load(pack: pack, learner: learner)
    }

    /// The saved Tomo for this language pair (a new one hatches if there's none yet).
    public func load(pack: TargetPack, learner: String) {
        self.pack = pack
        self.learner = learner
        isScratch = false
        levelOfItem = Dictionary(pack.levels.enumerated().flatMap { i, l in l.itemIDs.map { ($0, i + 1) } },
                                 uniquingKeysWith: { a, _ in a })
        roundIndex = Dictionary(pack.levels.flatMap { $0.rounds ?? [] }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        starterIndex = Dictionary(pack.levels.flatMap { $0.starters ?? [] }.compactMap { s in s.id.map { ($0, s) } },
                                  uniquingKeysWith: { a, _ in a })
        store = TomoStore(learner: learner, target: pack.id, directory: directory)
        items = store?.loadItems() ?? [:]
        if let t = store?.loadTomo() {
            level = min(max(t.level, 1), max(pack.levels.count, 1))
            age = t.age
            metAt = t.metAt
        } else {
            hatch()
        }
    }

    /// Start over: a new Tomo for this pair. The answer log stays.
    public func startOver() {
        if isScratch { load(pack: pack, learner: learner) }
        store?.clear(at: TomoClock.now)
        items = [:]
        hatch()
    }

    /// Testing: an in-memory Tomo at this age, with the earlier levels known.
    public func scratch(age: Int) {
        isScratch = true
        store = nil
        level = pack.firstLevel(age: age)
        self.age = max(age, 1)
        let now = TomoClock.now, weekAgo = now.addingTimeInterval(-7 * 86400)
        items = [:]
        for id in pack.levels.prefix(level - 1).flatMap(\.itemIDs) {
            items[id] = Item(id: id, stage: TomoSRS.knows, due: now.addingTimeInterval(7 * 86400),
                             introduced: weekAgo, answered: weekAgo, right: 4, wrong: 0, peak: TomoSRS.knows)
        }
    }

    /// Testing: carry on with this Tomo in memory, as it is now. Nothing from here on is saved or synced.
    public func detach() {
        isScratch = true
        store = nil
    }

    private func hatch() {
        level = 1
        age = pack.levels.first?.age ?? 1
        metAt = TomoClock.now
        save()
    }

    private func save() {
        store?.saveTomo(.init(metAt: metAt, level: level, age: age))
    }

    // MARK: Levels

    public var current: TargetPack.Level? { pack.levels.indices.contains(level - 1) ? pack.levels[level - 1] : nil }
    public var levelItems: [String] { current?.itemIDs ?? [] }
    public var levelKnown: Int { levelItems.filter { (items[$0]?.stage ?? 0) >= TomoSRS.knows }.count }
    /// 90% of the level's items, rounded up.
    public var levelNeeded: Int { max(1, (levelItems.count * 9 + 9) / 10) }
    public var isLastLevel: Bool { level >= pack.levels.count }
    /// The experience bar: every stage a word of this level reaches counts (up to "knows it"), so each answer that
    /// counts nudges it. It uses the best stage reached, so a slip never moves it back. Full when the level is done.
    public var levelProgress: Double {
        let steps = levelItems.reduce(0) { $0 + min(items[$1]?.peak ?? 0, TomoSRS.knows) }
        let full = Double(levelNeeded * TomoSRS.knows)
        return levelKnown >= levelNeeded ? 1 : min(Double(steps) / full, 0.97)
    }
    public var isTalkLevel: Bool { !(current?.starters ?? []).isEmpty }

    /// Level up when this level is done. Returns the new level and whether it was a birthday.
    public func levelUpIfReady() -> (level: Int, birthday: Bool)? {
        guard !isLastLevel, levelKnown >= levelNeeded else { return nil }
        level += 1
        let newAge = max(age, pack.levels[level - 1].age)
        let birthday = newAge > age
        age = newAge
        save()
        let now = TomoClock.now
        store?.logGrowth(at: now, kind: "level", value: level)
        if birthday { store?.logGrowth(at: now, kind: "age", value: age) }
        return (level, birthday)
    }

    // MARK: What Tomo asks

    /// Items of this level and the ones before it.
    private var unlocked: [String] { pack.levels.prefix(level).flatMap(\.itemIDs) }

    public func isDue(_ id: String) -> Bool {
        guard let due = items[id]?.due else { return false }
        return due <= TomoClock.now
    }

    public var dueItems: [String] {
        unlocked.filter(isDue).sorted { (items[$0]?.due ?? .distantPast) < (items[$1]?.due ?? .distantPast) }
    }
    public var newItems: [String] { unlocked.filter { items[$0] == nil } }
    public var newToday: Int { items.values.filter { $0.introduced >= TomoClock.dayStart }.count }
    public var canTeachNew: Bool { newToday < Self.newPerDay && !newItems.isEmpty }

    /// Today (since 4 am): new words, answers, and answers that moved a word up. A testing Tomo has no log.
    public func today() -> (newWords: Int, answers: Int, stronger: Int) {
        let counts = store?.answerCounts(since: TomoClock.dayStart) ?? (answers: 0, stronger: 0)
        return (newToday, counts.answers, counts.stronger)
    }

    /// A visit: due items first (the longest-waiting first), then at most one new one. Empty = nothing to do.
    public func visitItems(limit: Int) -> [String] {
        var q = Array(dueItems.prefix(limit))
        if q.count < limit, canTeachNew, let n = newItems.first { q.append(n) }
        return q
    }

    /// How much of an item's wait has passed: 0 right after it was answered, 1 when it's due.
    public func waitShare(_ id: String) -> Double {
        guard let i = items[id], let due = i.due,
              let wait = TomoSRS.wait(after: i.stage, level: levelOfItem[id] ?? level) else { return 0 }
        return max(0, 1 - due.timeIntervalSince(TomoClock.now) / wait)
    }

    /// Not due yet, but far enough along that answering it now counts (an early review).
    public func isEarlyOK(_ id: String) -> Bool { !isDue(id) && waitShare(id) >= Self.earlyShare }

    /// Would a right answer to this item count now (new, due, or far enough along)?
    public func counts(_ id: String) -> Bool { items[id] == nil || isDue(id) || isEarlyOK(id) }

    /// When something counts again, if nothing does now: the soonest a word reaches half its wait, or the next day's
    /// new words (4 am) when today's are used up and the level still has some. Nil if something counts now.
    /// Is there anything a right answer would count for now (due, new, or far enough along)?
    public var somethingCounts: Bool { !dueItems.isEmpty || canTeachNew || unlocked.contains(where: isEarlyOK) }
    public var nextCountsAt: Date? {
        if somethingCounts { return nil }
        let early = unlocked.compactMap { id -> Date? in
            guard let i = items[id], let due = i.due,
                  let wait = TomoSRS.wait(after: i.stage, level: levelOfItem[id] ?? level) else { return nil }
            return due.addingTimeInterval(-wait * (1 - Self.earlyShare))
        }.min()
        let newWords = newItems.isEmpty ? nil : TomoClock.dayStart.addingTimeInterval(86400)
        return [early, newWords].compactMap { $0 }.min()
    }

    /// Free play, after a visit's items: a due item, else a new one (within the daily limit), else one that
    /// can be reviewed early. Each of these counts.
    public func nextFreePlayItem() -> String? {
        dueItems.first ?? (canTeachNew ? newItems.first : nil)
            ?? unlocked.filter(isEarlyOK).max { waitShare($0) < waitShare($1) }
    }

    /// Practice when nothing counts right now: something Tomo already heard, the closest to due first (then the
    /// weakest), not the last one asked.
    public func practiceItem(after last: String?, talk: Bool) -> String? {
        let pool = unlocked.filter {
            guard let i = items[$0], i.stage < TomoSRS.forever, $0 != last else { return false }
            return isStarter($0) == talk
        }
        // One of the few closest to due (weakest first on ties), so practice doesn't drill the same two words.
        let ranked = pool.sorted {
            (waitShare($0), -(items[$0]?.stage ?? 0)) > (waitShare($1), -(items[$1]?.stage ?? 0))
        }
        return ranked.prefix(4).randomElement()
    }

    public func round(_ id: String) -> TargetPack.Round? { roundIndex[id] }
    public func starter(_ id: String) -> TargetPack.Starter? { starterIndex[id] }
    public func isStarter(_ id: String) -> Bool { starterIndex[id] != nil }

    /// Two wrong meanings for "Pick the meaning": other words' meanings, another category first. Never the
    /// same meaning, and never a word that sounds the same (きる "cut" for きる "put on").
    public func otherMeanings(for id: String, learner: String) -> [String] {
        guard let r = roundIndex[id] else { return [] }
        let meaning = r.meaning(learner).lowercased()
        let near = levelOfItem[id] ?? level                     // words from around the same level, not the 6さい list
        let all = roundIndex.values.filter {
            $0.id != id && $0.say != r.say && $0.meaning(learner).lowercased() != meaning
        }
        let close = all.filter { abs((levelOfItem[$0.id] ?? 0) - near) <= 10 }
        let candidates = close.count >= 2 ? close : all
        let other = candidates.filter { $0.category != r.category }
        var picked: [String] = []
        for c in (other.count >= 2 ? other : candidates).shuffled() {
            let m = c.meaning(learner)
            if !picked.contains(where: { $0.lowercased() == m.lowercased() }) { picked.append(m) }
            if picked.count == 2 { break }
        }
        return picked
    }

    // MARK: Answers

    /// The round ended with a right answer. Moves the item if it was new or due; returns whether it counted.
    @discardableResult
    public func answeredRight(_ id: String, mode: String, wrongTries: Int, hint: Bool) -> Bool {
        let now = TomoClock.now
        let before = items[id]
        let counted = before == nil || isDue(id) || isEarlyOK(id)
        var row = before ?? Item(id: id, stage: 0, due: nil, introduced: now, answered: now, right: 0, wrong: 0)
        if counted {
            row.stage = TomoSRS.next(after: row.stage, wrongTries: wrongTries, hint: hint)
            row.due = TomoSRS.wait(after: row.stage, level: levelOfItem[id] ?? level).map { now.addingTimeInterval($0) }
        }
        row.peak = max(row.peak, row.stage)
        row.answered = now
        row.right += 1
        row.wrong += wrongTries
        items[id] = row
        store?.saveItem(row)
        store?.logAnswer(at: now, item: id, level: level, mode: mode, result: "right", wrongTries: wrongTries,
                         hint: hint, counted: counted, before: before?.stage, after: row.stage)
        return counted
    }

    /// A try that didn't land (wrong, help, language), or a chat reply that isn't about an item. Logged only:
    /// the round's right answer applies the wrong tries.
    public func logTry(_ id: String?, mode: String, result: String) {
        let stage = id.flatMap { items[$0]?.stage }
        store?.logAnswer(at: TomoClock.now, item: id, level: level, mode: mode, result: result, wrongTries: 0,
                         hint: false, counted: false, before: stage, after: stage)
    }

    // MARK: Self-test (TOMO_SELFTEST=1)

    /// Checks the rules and the store in a temporary folder, prints each result, returns false on a failure.
    public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        typealias S = TomoSRS
        check(S.next(after: 0, wrongTries: 2, hint: false) == 1, "a new item's first right answer → just heard (1)")
        check(S.next(after: 3, wrongTries: 0, hint: false) == 4, "right on time → up one")
        check(S.next(after: 4, wrongTries: 1, hint: false) == 3, "one wrong try below 'knows it' → down one")
        check(S.next(after: 6, wrongTries: 1, hint: false) == 4, "one wrong try from 'knows it' up → down two")
        check(S.next(after: 7, wrongTries: 3, hint: false) == 3, "three wrong tries from 'knows it' up → down four")
        check(S.next(after: 2, wrongTries: 5, hint: false) == 1, "never below 1")
        check(S.next(after: 4, wrongTries: 0, hint: true) == 4, "right after the hint → stays")
        check(S.next(after: 8, wrongTries: 0, hint: false) == 9, "8 → forever")
        check(S.wait(after: 1, level: 1) == 2 * 3600 && S.wait(after: 1, level: 3) == 4 * 3600, "levels 1–2 start faster")
        check(S.wait(after: 5, level: 1) == 167 * 3600, "'knows it' waits a week on every level")
        check(S.wait(after: 9, level: 3) == nil, "forever items never come back")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let pack = TomoLanguages.shared.targets.first(where: { $0.id == "ja" }) else {
            check(false, "the Japanese pack loads"); return false
        }
        let savedOffset = TomoClock.offset
        defer { TomoClock.offset = savedOffset }
        let p = TomoProgress(pack: pack, learner: "en", directory: dir)
        check(p.level == 1 && p.age == 1, "a new Tomo starts at level 1, age 1")
        let first = pack.levels[0].itemIDs[0]
        check(p.visitItems(limit: 3) == [first], "the first visit teaches one new item: \(first)")
        check(p.answeredRight(first, mode: "picture", wrongTries: 1, hint: false) && p.items[first]?.stage == 1,
              "teaching it → stage 1 (wrong tries don't matter the first time)")
        check(p.levelProgress > 0 && p.levelProgress < 0.1, "one counted answer moves the experience bar a little")
        let bar = p.levelProgress
        check(!p.answeredRight(first, mode: "picture", wrongTries: 0, hint: false) && p.items[first]?.stage == 1,
              "answering again right away is practice: no change")
        TomoClock.offset += 3600 + 60                                               // half of the 2 h wait
        check(p.isEarlyOK(first) && !p.isDue(first) && p.nextFreePlayItem() != nil,
              "after half the wait, free play can review it early")
        TomoClock.offset -= 3600 + 60
        check(p.visitItems(limit: 3).count == 1, "a visit brings at most one new item")
        TomoClock.offset += 2 * 3600 + 60
        check(p.isDue(first) && p.visitItems(limit: 3).first == first, "two hours later it's due and comes first")
        p.answeredRight(first, mode: "picture", wrongTries: 0, hint: false)          // → stage 2
        TomoClock.offset += 4 * 3600 + 60
        p.answeredRight(first, mode: "picture", wrongTries: 2, hint: false)          // a slip: back to 1
        check(p.items[first]?.stage == 1 && p.levelProgress > bar, "a slip moves the word back, never the bar")

        /// Teach every item of the current level and bring it to "knows it", a long wait between answers.
        func finishLevel() {
            for id in p.levelItems {
                while (p.items[id]?.stage ?? 0) < S.knows {
                    TomoClock.offset += 200 * 86400
                    p.answeredRight(id, mode: "picture", wrongTries: 0, hint: false)
                }
            }
        }
        finishLevel()
        check(p.levelKnown >= p.levelNeeded, "level 1 done: \(p.levelKnown)/\(p.levelNeeded)")
        let up1 = p.levelUpIfReady()
        check(up1?.level == 2 && up1?.birthday == (pack.levels[1].age > pack.levels[0].age),
              "→ level 2, age \(pack.levels[1].age)")
        check(p.levelUpIfReady() == nil, "no level up before level 2 is done")
        check(p.newItems.first == pack.levels[1].itemIDs.first, "level 2's items are unlocked")
        // Keep going until the first birthday: it must land on the first level with a higher age.
        let firstAge2 = (pack.levels.firstIndex { $0.age > pack.levels[0].age } ?? 0) + 1
        var birthday: (level: Int, birthday: Bool)?
        while birthday == nil, !p.isLastLevel {
            finishLevel()
            if let up = p.levelUpIfReady(), up.birthday { birthday = up }
        }
        check(birthday?.level == firstAge2 && p.age == pack.levels[firstAge2 - 1].age,
              "the first birthday is level \(firstAge2): \(p.age)さい")  // text-ok: self-test output

        if let m = pack.levels.flatMap({ $0.rounds ?? [] }).first(where: { $0.answer == nil && $0.need == nil }) {
            let others = p.otherMeanings(for: m.id, learner: "en")
            check(others.count == 2 && !others.contains(m.meaning("en")) && Set(others).count == 2,
                  "\"\(m.say)\" gets two other meanings: \(others.joined(separator: ", "))")
        }

        let reopened = TomoProgress(pack: pack, learner: "en", directory: dir)
        check(reopened.level == p.level && reopened.age == p.age && reopened.items.count == p.items.count,
              "progress survives reopening (\(reopened.items.count) items)")
        // Free play after learning a whole level in one sitting: nothing counts for a while, it says when, and then
        // free play earns experience again.
        let sitting = TomoProgress(pack: pack, learner: "es", directory: dir)
        for id in pack.levels[0].itemIDs { sitting.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) }
        let barBefore = sitting.levelProgress
        check(sitting.nextFreePlayItem() == nil && !sitting.somethingCounts
              && !sitting.levelItems.contains(where: sitting.counts),
              "right after learning a whole level, nothing counts")
        let wait = sitting.nextCountsAt.map { $0.timeIntervalSince(TomoClock.now) } ?? -1
        check(wait > 50 * 60 && wait < 70 * 60, "it says when answers count again: in \(Int(wait / 60)) min")
        TomoClock.offset += wait + 60
        check(sitting.somethingCounts && sitting.nextCountsAt == nil, "then something counts again")
        if let id = sitting.nextFreePlayItem() {
            check(sitting.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) && sitting.levelProgress > barBefore,
                  "an hour later, free play adds experience again")
        } else { check(false, "an hour later, free play has something that counts") }

        let other = TomoProgress(pack: pack, learner: "ja", directory: dir)
        check(other.level == 1 && other.items.isEmpty, "another language pair is another Tomo")

        reopened.scratch(age: 3)
        check(reopened.isScratch && reopened.age == 3 && reopened.isTalkLevel, "testing at 3さい → the talking level")  // text-ok: self-test output
        check(TomoProgress(pack: pack, learner: "en", directory: dir).level == p.level, "testing ages don't touch saved progress")
        // Settings → Skip ahead a day (TomoGame.skipAhead): the saved Tomo carries on as a copy in memory first.
        let ahead = TomoProgress(pack: pack, learner: "en", directory: dir)
        let savedItems = ahead.items
        ahead.detach()
        TomoClock.offset += 86400
        for id in ahead.levelItems.prefix(3) { ahead.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) }
        check(ahead.isScratch && ahead.items != savedItems
              && TomoProgress(pack: pack, learner: "en", directory: dir).items == savedItems,
              "skipping ahead runs on a copy: answers a day ahead aren't saved")

        reopened.startOver()
        let fresh = TomoProgress(pack: pack, learner: "en", directory: dir)
        check(fresh.level == 1 && fresh.age == 1 && fresh.items.isEmpty, "start over is saved")

        // Answers typed in romaji (TargetPack.normalizedAnswer)
        let romaji = ["shigoto shiteru", "konnichiwa", "matcha", "ra-men"].map { pack.normalizedAnswer($0) }
        check(romaji.allSatisfy { pack.looksLikeTarget($0, learner: "en") }, "romaji answers become kana: \(romaji)")
        check(!romaji[1].unicodeScalars.contains { $0.value == 0x3063 }, "konnichiwa has ん, not a small tsu")  // text-ok: self-test output
        let english = ["what are you doing", "I'm working", "car", "yes"]
        check(english.allSatisfy { pack.normalizedAnswer($0) == $0 }, "English answers stay English")
        return ok
    }
}
