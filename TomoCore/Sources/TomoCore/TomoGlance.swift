import Foundation

// MARK: - Tomo at a glance: what a widget shows
//
// The app writes one of these whenever progress changes; a widget (or anything else that can't run the
// game) reads it. All text is already in the learner's language, so the reader needs no language packs.

public struct TomoGlance: Codable, Sendable, Hashable {
    public var growth: Double           // 0 = in the shell, 1 = hatched, 2 = bigger (TomoChick)
    public var age: String              // "3さい"
    public var level: String            // "Lv 61"
    public var progress: Double         // the experience bar, 0…1
    public var waiting: Bool            // something counts now: the red dot
    public var status: String           // "3 words waiting", "All done for now"
    public var nextDue: Date?           // when something counts again, if nothing does now
    public var statusLater: String      // the status from `nextDue` on ("Tomo is waiting for you")
    public var about: String            // the widget's description in the widget gallery
    public var invite: String           // what Tomo calls out when something is waiting ("あそぼ！")
    public var nextLabel: String        // before the countdown to `nextDue` ("New words in")
    public var updated: Date

    public init(growth: Double, age: String, level: String, progress: Double, waiting: Bool, status: String,
                nextDue: Date?, statusLater: String, about: String, invite: String, nextLabel: String, updated: Date) {
        self.growth = growth; self.age = age; self.level = level; self.progress = progress; self.waiting = waiting
        self.status = status; self.nextDue = nextDue; self.statusLater = statusLater; self.about = about
        self.invite = invite; self.nextLabel = nextLabel; self.updated = updated
    }

    public static let placeholder = TomoGlance(growth: 0, age: "", level: "", progress: 0, waiting: false,
                                               status: "", nextDue: nil, statusLater: "", about: "",
                                               invite: "", nextLabel: "", updated: .distantPast)

    // Shared between the app and its widgets through an App Group.
    public static let appGroup = "group.com.zenbujapanese.tomodachi"
    private static let key = "tomoGlance"

    public static func load() -> TomoGlance? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TomoGlance.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}

extension TomoGame {
    /// Tomo right now, for a widget.
    public var glance: TomoGlance {
        let ui = TomoLanguages.shared.learner
        let due = progress.dueItems.count
        let status = due > 1 ? ui("glance.due", ["n": "\(due)"]) : due == 1 ? ui("glance.due.one")
            : progress.canTeachNew ? ui("glance.new") : ui("glance.done")
        let waiting = due > 0 || progress.canTeachNew
        let nextDue = waiting ? nil : progress.items.values.compactMap(\.due).filter { $0 > TomoClock.now }.min()
        return TomoGlance(growth: Double(min(max(stage - 1, 0), 2)), age: age, level: ui("level", ["n": "\(level)"]),
                          progress: levelProgress, waiting: waiting, status: status,
                          nextDue: nextDue.map(wallClock), statusLater: ui("glance.waiting"), about: ui("glance.about"),
                          invite: TomoLanguages.shared.target.lines.invite ?? TomoLanguages.shared.target.lines.practice,
                          nextLabel: ui("glance.next"), updated: Date())
    }
}
