import Foundation

// MARK: - Tomo at a glance: what a widget shows
//
// The app writes one of these whenever progress changes; a widget (or anything else that can't run the
// game) reads it. All text is already in the learner's language, so the reader needs no language packs.
// It says what Tomo is doing, never how many words are waiting (decisions.md, 2026-10-11: no growing count of things
// to review or do): Tomo wants to play, lit amber like small Tomo on the Mac (`moment`, TomoMoment), or it rests until
// a time. It says what the app says (#192): the same rule for whether Tomo wants to play, and the app's own line for
// when it's back, on the person's own clock (`follow`).

public struct TomoGlance: Codable, Sendable, Hashable {
    public var growth: Double           // age step: 0 = 1さい … 5 = 6さい (TomoBlob)
    public var age: String              // "3さい"
    public var level: String            // "Lv 61"
    public var progress: Double         // the experience bar, 0…1
    public var waiting: Bool            // something counts now: Tomo wants to play (its asking pose)
    public var status: String           // what Tomo is doing: "Tomo wants to play", "Tomo is resting"
    public var nextDue: Date?           // when something counts again, if nothing does now (on the device's clock)
    public var statusLater: String      // the status from `nextDue` on ("Tomo wants to play")
    public var about: String            // the widget's description in the widget gallery
    public var invite: String           // what Tomo calls out when something is waiting ("あそぼ！")
    /// When Tomo's back, in the app's own words and clock ("Back at 2:57 PM", or "Back at 14:57": `backText`). The
    /// reader shows it as it is and never formats `nextDue` itself, so it can't say another time. Nil while Tomo wants
    /// to play, or with no time known (then `status`, "Tomo is resting").
    public var back: String?
    public var play: String             // the Lock Screen card's button that opens a round there ("Play")
    public var updated: Date
    /// The moment's light, as on the Mac (TomoMoment's raw value): "waiting" while Tomo wants to play, none while it
    /// rests. Optional, so a glance saved before it still reads.
    public var moment: String?

    /// The moment's light, if any (`moment`).
    public var light: TomoMoment? { moment.flatMap(TomoMoment.init(rawValue:)) }

    public init(growth: Double, age: String, level: String, progress: Double, waiting: Bool, status: String,
                nextDue: Date?, statusLater: String, about: String, invite: String, back: String?, play: String,
                updated: Date, moment: TomoMoment? = nil) {
        self.growth = growth; self.age = age; self.level = level; self.progress = progress; self.waiting = waiting
        self.status = status; self.nextDue = nextDue; self.statusLater = statusLater; self.about = about
        self.invite = invite; self.back = back; self.play = play; self.updated = updated
        self.moment = moment?.rawValue
    }

    /// What a widget says Tomo is doing, and its light: while something counts, Tomo wants to play, lit amber (the rule
    /// small Tomo's glow uses on the Mac); otherwise it rests. However many words are due, the same words: never a count.
    public static func state(somethingCounts: Bool) -> (status: String, moment: TomoMoment?) {
        (somethingCounts ? "glance.wants" : "glance.resting", TomoMoment.resting(somethingCounts: somethingCounts))
    }

    /// Tomo's state by the app's own rule and clock: while something counts (`TomoProgress.somethingCounts`, the rule
    /// the game asks or rests by: a due word, a new one, or one far enough along to review early), Tomo wants to play;
    /// otherwise it rests until something counts again (`nextCountsAt`, the time the app's resting card gives).
    @MainActor public mutating func follow(_ progress: TomoProgress, _ lang: TomoLanguages) {
        let counts = progress.somethingCounts
        set(counts: counts, until: counts ? nil : progress.nextCountsAt, lang)
    }

    /// Tomo wants to play (`counts`), lit amber; or it rests, unlit, until `until` (on Tomo's clock; nil: no time
    /// known), saying when in the app's own line.
    @MainActor public mutating func set(counts: Bool, until: Date?, _ lang: TomoLanguages) {
        let state = Self.state(somethingCounts: counts)
        waiting = counts
        status = lang.learner(state.status)
        moment = state.moment?.rawValue
        nextDue = counts ? nil : until.map(wallClock)
        back = counts ? nil : until.map { backText(until: $0, lang) }
    }

    /// Now that its next words have come due (a widget's later timeline entry): Tomo wants to play.
    public var cameDue: TomoGlance {
        var g = self
        g.waiting = true
        g.status = statusLater
        g.back = nil
        g.moment = TomoMoment.waiting.rawValue
        return g
    }

    public static let placeholder = TomoGlance(growth: 0, age: "", level: "", progress: 0, waiting: false,
                                               status: "", nextDue: nil, statusLater: "", about: "",
                                               invite: "", back: nil, play: "", updated: .distantPast)

    // Shared between the app and its widgets through an App Group, which each of them names in its Info.plist
    // (`TomoAppGroup`): the host app's identity, never TomoCore's. Nil where there's none (the Mac).
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TomoAppGroup") as? String
    private static var shared: UserDefaults? { appGroup.flatMap { UserDefaults(suiteName: $0) } }
    private static let key = "tomoGlance"

    public static func load() -> TomoGlance? {
        guard let data = shared?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TomoGlance.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.shared?.set(data, forKey: Self.key)
    }

    /// What the widgets and reminders say, checked by TOMO_SELFTEST (run by the Mac's TomoIslandSelfTest): Tomo's
    /// state and light, never a count, in every ui pack; the app's own rule and time; the person's own clock.
    @MainActor public static func selfTest(_ check: (Bool, String) -> Void) {
        let wants = state(somethingCounts: true), rests = state(somethingCounts: false)
        check(wants.status == "glance.wants" && wants.moment == .waiting && rests.status == "glance.resting"
              && rests.moment == nil,
              "a widget says Tomo wants to play, lit amber like small Tomo on the Mac, or that it rests, unlit")
        let came = placeholder.cameDue
        check(came.waiting && came.light == .waiting && came.status == placeholder.statusLater && came.back == nil,
              "when its next words come due, a widget's later entry has Tomo want to play, lit amber")
        check(TomoReminders.statusKey(due: 1) == TomoReminders.statusKey(due: 40)
              && TomoReminders.statusKey(due: 1) != TomoReminders.statusKey(due: 0),
              "a reminder says some words are back, the same words for one or forty: never how many")
        let keys = ["glance.wants", "glance.resting", "glance.back", "glance.new", "glance.about", "rest.back"]
        let packs = TomoLanguages.shared.learners
        check(packs.allSatisfy { p in keys.allSatisfy { p.strings[$0] != nil } }
              && packs.allSatisfy { p in p.strings.filter { $0.key.hasPrefix("glance.") }.values.allSatisfy { !$0.contains("{n}") } }
              && packs.allSatisfy { $0.strings["rest.back"]?.contains("{time}") == true },
              "every ui pack (\(packs.count)) says Tomo's state for the widgets, with no count in any of it")
        let old = #"{"growth":0,"age":"","level":"","progress":0,"waiting":true,"status":"","statusLater":"","about":"","#
            + #""invite":"","nextLabel":"","play":"","updated":0}"#
        check((try? JSONDecoder().decode(TomoGlance.self, from: Data(old.utf8))).map { $0.light == nil && $0.back == nil } == true,
              "a glance saved before the light and the app's line still reads, unlit")
        followsTheApp(check)
        followsTheClock(check)
        TomoGame.restLinesSelfTest(check)
    }

    /// The Lock Screen card, the Dynamic Island and the widgets say what the app says (#192), on a testing Tomo in a
    /// temporary folder that learned a whole level in one sitting: nothing counts until its words are halfway to due.
    @MainActor private static func followsTheApp(_ check: (Bool, String) -> Void) {
        let lang = TomoLanguages.shared
        guard let pack = lang.targets.first(where: { $0.id == "ja" }) else { check(false, "the Japanese pack loads"); return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-glance-\(UUID().uuidString)")
        let savedOffset = TomoClock.offset
        defer { TomoClock.offset = savedOffset; try? FileManager.default.removeItem(at: dir) }
        let p = TomoProgress(pack: pack, learner: "en", directory: dir)
        for id in pack.levels[0].itemIDs { p.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) }
        var g = placeholder
        g.follow(p, lang)
        let back = p.nextCountsAt, firstDue = p.items.values.compactMap(\.due).min()
        let sameTime = g.nextDue.flatMap { n in back.map { abs(n.timeIntervalSince(wallClock($0))) < 1 } } ?? false
        check(!p.somethingCounts && !g.waiting && g.light == nil && sameTime && g.back == backText(until: back, lang)
              && (firstDue ?? .distantPast) > (back ?? .distantFuture),
              "resting, the card gives the app's own time and line (\(g.back ?? "none")): when answers count again, "
              + "not when the first word is due, later")
        guard let back else { return }
        TomoClock.offset += back.timeIntervalSince(TomoClock.now) + 60
        g.follow(p, lang)
        check(p.dueItems.isEmpty && !p.canTeachNew && p.somethingCounts && g.waiting && g.light == .waiting
              && g.status == lang.learner("glance.wants") && g.back == nil && g.nextDue == nil,
              "a word far enough along to review early, none due: the card says Tomo wants to play, lit amber, as the "
              + "app asks it")
    }

    /// Every time Tomo shows is on the person's own 12- or 24-hour clock, in either language (`tomoClockLocale`).
    @MainActor private static func followsTheClock(_ check: (Bool, String) -> Void) {
        let lang = TomoLanguages.shared
        let wall = Calendar.current.date(bySettingHour: 15, minute: 7, second: 30, of: Date()) ?? Date()
        func time(_ language: String, _ hourCycle: Locale.HourCycle) -> String {
            let f = DateFormatter()
            f.locale = tomoClockLocale(language, hourCycle: hourCycle)
            f.timeStyle = .short
            return f.string(from: wall)
        }
        let en12 = time("en", .oneToTwelve), en24 = time("en", .zeroToTwentyThree)
        let ja12 = time("ja", .oneToTwelve), ja24 = time("ja", .zeroToTwentyThree)
        check(en24.contains("15:07") && ja24.contains("15:07") && en12.contains("3:07") && !en12.contains("15")
              && ja12.contains("3:07") && !ja12.contains("15"),
              "a time follows the person's 12- or 24-hour clock in either language: \(en12), \(en24), \(ja12), \(ja24)")
        let mine = time(lang.learner.id, Locale.current.hourCycle)
        let onTomosClock = wall.addingTimeInterval(TomoClock.now.timeIntervalSince(Date()))
        check(tomoTime(onTomosClock, lang) == mine && TomoReminders.clock(15 * 60 + 7) == mine,
              "the card's times and the reminders' are on this device's clock: \(mine)")
    }
}

extension TomoGame {
    /// Tomo right now, for a widget: what the app says (`TomoGlance.follow`).
    public var glance: TomoGlance {
        let lang = TomoLanguages.shared, ui = lang.learner
        var g = TomoGlance(growth: Double(min(max(stage - 1, 0), TomoLook.ages - 1)), age: age,
                           level: ui("level", ["n": "\(level)"]), progress: levelProgress, waiting: false, status: "",
                           nextDue: nil, statusLater: ui(TomoGlance.state(somethingCounts: true).status),
                           about: ui("glance.about"), invite: lang.target.lines.invite ?? lang.target.lines.practice,
                           back: nil, play: ui("glance.play"), updated: Date())
        g.follow(progress, lang)
        return g
    }
}
