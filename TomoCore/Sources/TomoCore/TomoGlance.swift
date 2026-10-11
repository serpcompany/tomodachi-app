import Foundation

// MARK: - Tomo at a glance: what a widget shows
//
// The app writes one of these whenever progress changes; a widget (or anything else that can't run the
// game) reads it. All text is already in the learner's language, so the reader needs no language packs.
// It says what Tomo is doing, never how many words are waiting (decisions.md, 2026-10-11: no growing count of things
// to review or do): Tomo wants to play, lit amber like small Tomo on the Mac (`moment`, TomoMoment), or it rests until
// a time.

public struct TomoGlance: Codable, Sendable, Hashable {
    public var growth: Double           // age step: 0 = 1さい … 5 = 6さい (TomoBlob)
    public var age: String              // "3さい"
    public var level: String            // "Lv 61"
    public var progress: Double         // the experience bar, 0…1
    public var waiting: Bool            // something counts now: Tomo wants to play (its asking pose)
    public var status: String           // what Tomo is doing: "Tomo wants to play", "Tomo is resting"
    public var nextDue: Date?           // when something counts again, if nothing does now
    public var statusLater: String      // the status from `nextDue` on ("Tomo wants to play")
    public var about: String            // the widget's description in the widget gallery
    public var invite: String           // what Tomo calls out when something is waiting ("あそぼ！")
    public var nextLabel: String        // when Tomo's back ("Back at {time}"; the reader fills in `nextDue`)
    public var play: String             // the Lock Screen card's button that opens a round there ("Play")
    public var updated: Date
    /// The moment's light, as on the Mac (TomoMoment's raw value): "waiting" while Tomo wants to play, none while it
    /// rests. Optional, so a glance saved before it still reads.
    public var moment: String?

    /// The moment's light, if any (`moment`).
    public var light: TomoMoment? { moment.flatMap(TomoMoment.init(rawValue:)) }

    public init(growth: Double, age: String, level: String, progress: Double, waiting: Bool, status: String,
                nextDue: Date?, statusLater: String, about: String, invite: String, nextLabel: String, play: String,
                updated: Date, moment: TomoMoment? = nil) {
        self.growth = growth; self.age = age; self.level = level; self.progress = progress; self.waiting = waiting
        self.status = status; self.nextDue = nextDue; self.statusLater = statusLater; self.about = about
        self.invite = invite; self.nextLabel = nextLabel; self.play = play; self.updated = updated
        self.moment = moment?.rawValue
    }

    /// What a widget says Tomo is doing, and its light: while something counts, Tomo wants to play, lit amber (the rule
    /// small Tomo's glow uses on the Mac); otherwise it rests. However many words are due, the same words: never a count.
    public static func state(somethingCounts: Bool) -> (status: String, moment: TomoMoment?) {
        (somethingCounts ? "glance.wants" : "glance.resting", TomoMoment.resting(somethingCounts: somethingCounts))
    }

    /// Now that its next words have come due (a widget's later timeline entry): Tomo wants to play.
    public var cameDue: TomoGlance {
        var g = self
        g.waiting = true
        g.status = statusLater
        g.moment = TomoMoment.waiting.rawValue
        return g
    }

    public static let placeholder = TomoGlance(growth: 0, age: "", level: "", progress: 0, waiting: false,
                                               status: "", nextDue: nil, statusLater: "", about: "",
                                               invite: "", nextLabel: "", play: "", updated: .distantPast)

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
    /// state and light, never a count, in every ui pack.
    @MainActor public static func selfTest(_ check: (Bool, String) -> Void) {
        let wants = state(somethingCounts: true), rests = state(somethingCounts: false)
        check(wants.status == "glance.wants" && wants.moment == .waiting && rests.status == "glance.resting"
              && rests.moment == nil,
              "a widget says Tomo wants to play, lit amber like small Tomo on the Mac, or that it rests, unlit")
        let came = placeholder.cameDue
        check(came.waiting && came.light == .waiting && came.status == placeholder.statusLater,
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
        check((try? JSONDecoder().decode(TomoGlance.self, from: Data(old.utf8)))?.light == nil,
              "a glance saved before the light still reads, unlit")
    }
}

extension TomoGame {
    /// Tomo right now, for a widget.
    public var glance: TomoGlance {
        let ui = TomoLanguages.shared.learner
        let waiting = !progress.dueItems.isEmpty || progress.canTeachNew
        let state = TomoGlance.state(somethingCounts: waiting)
        let nextDue = waiting ? nil : progress.items.values.compactMap(\.due).filter { $0 > TomoClock.now }.min()
        return TomoGlance(growth: Double(min(max(stage - 1, 0), TomoLook.ages - 1)), age: age, level: ui("level", ["n": "\(level)"]),
                          progress: levelProgress, waiting: waiting, status: ui(state.status),
                          nextDue: nextDue.map(wallClock), statusLater: ui(TomoGlance.state(somethingCounts: true).status),
                          about: ui("glance.about"),
                          invite: TomoLanguages.shared.target.lines.invite ?? TomoLanguages.shared.target.lines.practice,
                          nextLabel: ui("rest.back"), play: ui("glance.play"), updated: Date(), moment: state.moment)
    }
}
