import Combine
import SwiftUI
import Foundation
import UserNotifications

// MARK: - Reminders: how Tomo comes to you on the iPhone (issue #88)
//
// On the Mac, Tomo drops in by the notch. On the iPhone it sends a local notification when words are ready, on
// the reference app's cadence (#83): a rhythm the learner picks (15 min to daily, hourly by default) and quiet
// hours (9 PM to 8 AM by default). The rules, all in `TomoReminders.plan`, a pure function with a self-test:
// - Only when something counts: the first reminder is when a word comes due or new words are ready, never before.
//   Without the learner answering, what's ready only grows, so every reminder after it has something too.
// - Never sooner than one rhythm after now (now is the last time the learner played, or opened the app).
// - At most one per rhythm, and never in quiet hours: a time that falls in them moves to when they end. Daily is
//   each morning, when quiet hours end.
// - Gentle when ignored: at the rhythm for two days, then once a morning, and nothing a week after the first.
// - At most 48 pending, under iOS's limit of 64.
// Each one is Tomo speaking at its age (the pack's `reminders`, with a translation) plus what's waiting.
// `TomoReminderCenter` schedules them with UNUserNotificationCenter: on launch, on every change to progress (an
// answer, a sync), and when the app comes to the front. The settings are on each device, like the others.
// The Mac has no reminders, but its quiet hours are the same setting: Tomo's visits by the notch skip them
// (`visitAllowed`, TomoGame.dropIn), while clicking Tomo still plays.

/// How often Tomo may find the learner, and when it never does. Saved on this device.
public struct TomoReminderSettings: Equatable, Sendable {
    /// Notifications: the learner said yes ("Let words find you", or Settings).
    public var on: Bool
    /// The rhythm: at most one reminder this often (`TomoReminders.choices`).
    public var every: TimeInterval
    /// Quiet hours, in minutes after midnight. Equal: no quiet hours.
    public var quietFrom: Int
    public var quietUntil: Int
    /// Tomo's Lock Screen card (a Live Activity, iPhone only). A device that never chose keeps it: it was there
    /// before the first run asked.
    public var lockScreen: Bool

    public init(on: Bool, every: TimeInterval, quietFrom: Int, quietUntil: Int, lockScreen: Bool) {
        self.on = on; self.every = every; self.quietFrom = quietFrom; self.quietUntil = quietUntil
        self.lockScreen = lockScreen
    }

    /// The reference's defaults: hourly, quiet from 9 PM to 8 AM.
    public static let standard = TomoReminderSettings(on: false, every: 3600, quietFrom: 21 * 60, quietUntil: 8 * 60,
                                                      lockScreen: true)

    public var hasQuietHours: Bool { quietFrom != quietUntil }

    public static func load(_ d: UserDefaults = .standard) -> TomoReminderSettings {
        let s = standard
        return TomoReminderSettings(on: d.object(forKey: "tomoRemindersOn") as? Bool ?? s.on,
                                    every: d.object(forKey: "tomoRemindEvery") as? Double ?? s.every,
                                    quietFrom: d.object(forKey: "tomoQuietFrom") as? Int ?? s.quietFrom,
                                    quietUntil: d.object(forKey: "tomoQuietUntil") as? Int ?? s.quietUntil,
                                    lockScreen: d.object(forKey: "tomoLockScreenCard") as? Bool ?? s.lockScreen)
    }

    public func save(_ d: UserDefaults = .standard) {
        d.set(on, forKey: "tomoRemindersOn")
        d.set(every, forKey: "tomoRemindEvery")
        d.set(quietFrom, forKey: "tomoQuietFrom")
        d.set(quietUntil, forKey: "tomoQuietUntil")
        d.set(lockScreen, forKey: "tomoLockScreenCard")
    }
}

public enum TomoReminders {
    public static let daily: TimeInterval = 86_400
    /// The rhythm choices, the reference's (#83). `key` names the texts: `reminders.every.<key>` ("Hourly"),
    /// `reminders.tag.<key>` ("The classic") and `reminders.phrase.<key>` ("every hour").
    public static let choices: [(every: TimeInterval, key: String)] = [
        (15 * 60, "15m"), (30 * 60, "30m"), (3600, "1h"), (2 * 3600, "2h"), (4 * 3600, "4h"), (daily, "daily"),
    ]
    public static func key(for every: TimeInterval) -> String {
        choices.min { abs($0.every - every) < abs($1.every - every) }?.key ?? "1h"
    }
    /// iOS keeps at most 64 pending notifications per app.
    public static let maxPending = 48
    /// Ignored for this long after the first reminder, Tomo slows down to once a morning…
    public static let rhythmFor: TimeInterval = 2 * daily
    /// …and a week after the first, it waits until the learner is back.
    public static let stopAfter: TimeInterval = 7 * daily
    /// Daily: the first morning at least this long after playing.
    public static let dailyGap: TimeInterval = 8 * 3600

    /// One reminder: when, and what's ready by then.
    public struct Slot: Equatable, Sendable {
        public let at: Date
        public let due: Int        // words due by then
        public let new: Bool       // new words ready by then
    }

    /// The reminders to schedule from `now`. `due`: when each word comes due; `newAt`: when new words are ready (now
    /// or the next day's), nil if none come without the learner answering. Rules: the top of this file.
    public static func plan(now: Date, settings s: TomoReminderSettings, due: [Date], newAt: Date?,
                            calendar: Calendar = .current) -> [Slot] {
        guard s.on, let ready = (due + [newAt].compactMap { $0 }).min() else { return [] }
        let every = max(s.every, 60)
        func slot(_ t: Date) -> Slot {
            Slot(at: t, due: due.filter { $0 <= t }.count, new: newAt.map { $0 <= t } ?? false)
        }
        func awake(_ t: Date) -> Date { isQuiet(t, s, calendar: calendar) ? next(s.quietUntil, after: t, calendar) : t }

        // Daily: each morning, when quiet hours end (at least a few hours after playing, so not right away).
        let isDaily = every >= daily
        let first = isDaily ? next(s.quietUntil, after: max(ready, now.addingTimeInterval(dailyGap)), calendar)
            : awake(max(ready, now.addingTimeInterval(every)))
        var slots: [Slot] = []
        var t = first
        // At the rhythm (a daily rhythm all week), then once a morning.
        let rhythmEnd = first.addingTimeInterval(isDaily ? stopAfter : rhythmFor)
        while t < rhythmEnd && slots.count < maxPending {
            slots.append(slot(t))
            t = isDaily ? next(s.quietUntil, after: t, calendar) : awake(t.addingTimeInterval(every))
        }
        guard !isDaily, let last = slots.last?.at else { return slots }
        var morning = next(s.quietUntil, after: max(last, rhythmEnd.addingTimeInterval(-1)), calendar)
        while morning < first.addingTimeInterval(stopAfter) && slots.count < maxPending {
            slots.append(slot(morning))
            morning = next(s.quietUntil, after: morning, calendar)
        }
        return slots
    }

    /// Inside quiet hours (which can run past midnight).
    public static func isQuiet(_ t: Date, _ s: TomoReminderSettings, calendar: Calendar = .current) -> Bool {
        guard s.hasQuietHours else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: t)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return s.quietFrom > s.quietUntil ? (m >= s.quietFrom || m < s.quietUntil) : (m >= s.quietFrom && m < s.quietUntil)
    }

    /// The Mac: may Tomo drop in on its own now? Not in quiet hours (clicking Tomo still plays).
    public static func visitAllowed(at t: Date, _ s: TomoReminderSettings, calendar: Calendar = .current) -> Bool {
        !isQuiet(t, s, calendar: calendar)
    }

    /// When quiet hours end, if `t` is in them.
    public static func quietEnds(after t: Date, _ s: TomoReminderSettings, calendar: Calendar = .current) -> Date? {
        isQuiet(t, s, calendar: calendar) ? next(s.quietUntil, after: t, calendar) : nil
    }

    /// How many reminders fit in a day at most: hourly from 8 AM to 9 PM is 13.
    public static func perDay(_ s: TomoReminderSettings) -> Int {
        if s.every >= daily { return 1 }
        let awake = s.hasQuietHours ? (s.quietFrom - s.quietUntil + 1440) % 1440 : 1440
        return Int((Double(awake) / (s.every / 60)).rounded(.up))
    }

    // MARK: Saying it

    /// "Up to 13 a day, 8:00 AM to 9:00 PM, only when a word is ready."
    @MainActor public static func summary(_ s: TomoReminderSettings) -> String {
        let ui = TomoLanguages.shared.learner
        if s.every >= daily { return ui("reminders.summary.daily", ["time": clock(s.quietUntil)]) }
        let n = "\(perDay(s))"
        guard s.hasQuietHours else { return ui("reminders.summary.allDay", ["n": n]) }
        return ui("reminders.summary", ["n": n, "from": clock(s.quietUntil), "until": clock(s.quietFrom)])
    }

    /// A time of day in the learner's language: "9:00 PM", "21:00".
    @MainActor public static func clock(_ minutes: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: TomoLanguages.shared.learner.id)
        f.timeStyle = .short
        return f.string(from: date(minutes))
    }

    /// A time of day in minutes, as a Date today, for a time picker.
    public static func timeOfDay(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { date(minutes.wrappedValue) }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    private static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    /// The next time of day `minutes` after `t`.
    private static func next(_ minutes: Int, after t: Date, _ calendar: Calendar) -> Date {
        calendar.nextDate(after: t, matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime)
            ?? t.addingTimeInterval(daily)
    }

    // MARK: Self-test (TOMO_SELFTEST=1)

    /// The scheduling rules on a fixed clock (Tokyo, so the test doesn't depend on the Mac's time zone).
    @MainActor public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m)) ?? Date()
        }
        func hm(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return c.hour! * 60 + c.minute! }
        var s = TomoReminderSettings.standard
        s.on = true
        let now = at(8, 10)                                          // Thursday 10:00, just played

        check(plan(now: now, settings: s, due: [], newAt: nil, calendar: cal).isEmpty,
              "nothing will count without the learner: no reminders")
        var off = s
        off.on = false
        check(plan(now: now, settings: off, due: [now], newAt: now, calendar: cal).isEmpty, "notifications off: none")

        let words = [at(8, 14), at(8, 14, 5), at(9, 2)]               // two due this afternoon, one at 2 am
        let p = plan(now: now, settings: s, due: words, newAt: nil, calendar: cal)
        check(p.first?.at == at(8, 14) && p.first?.due == 1, "the first reminder is when the first word comes due (14:00)")
        check(p.allSatisfy { $0.due > 0 || $0.new }, "every reminder has something waiting")
        check(!p.contains { isQuiet($0.at, s, calendar: cal) }, "never in quiet hours (9 PM to 8 AM)")
        check(zip(p, p.dropFirst()).allSatisfy { $1.at.timeIntervalSince($0.at) >= s.every },
              "never more than one per rhythm (hourly)")
        check(p.first(where: { $0.due == 3 }).map { hm($0.at) } == 8 * 60, "a word due at 2 am waits for 8 AM")
        check(p.count <= maxPending && maxPending < 64, "\(p.count) pending, under iOS's 64")
        let day1 = p.filter { $0.at < at(9, 4) }.count
        check(day1 == 7, "hourly from 14:00 to 20:00: 7 today (\(day1))")
        let late = p.filter { $0.at >= p[0].at.addingTimeInterval(rhythmFor) }
        check(!late.isEmpty && late.allSatisfy { hm($0.at) == s.quietUntil }
              && zip(late, late.dropFirst()).allSatisfy { $1.at.timeIntervalSince($0.at) >= daily - 3600 },
              "ignored for two days: once a morning (\(late.count))")
        check(p.last.map { $0.at < p[0].at.addingTimeInterval(stopAfter) } ?? false, "nothing a week after the first")

        let new = plan(now: now, settings: s, due: [], newAt: now, calendar: cal)
        check(new.first?.at == at(8, 11) && new.first?.new == true, "new words ready now: one rhythm after playing (11:00)")
        var fast = s
        fast.every = 15 * 60
        let f = plan(now: now, settings: fast, due: [], newAt: now, calendar: cal)
        check(f.count == maxPending && f.first?.at == at(8, 10, 15), "every 15 min: \(f.count) pending, the cap")
        var once = s
        once.every = daily
        let d = plan(now: at(8, 22), settings: once, due: [], newAt: at(8, 22), calendar: cal)
        check(d.count == 7 && hm(d[0].at) == 8 * 60 && zip(d, d.dropFirst()).allSatisfy { $1.at.timeIntervalSince($0.at) >= daily },
              "daily: one a day for a week, played at 10 PM → first at 8 AM")
        var noQuiet = s
        noQuiet.quietFrom = 0
        noQuiet.quietUntil = 0
        check(plan(now: at(8, 22), settings: noQuiet, due: [], newAt: at(8, 22), calendar: cal).first?.at == at(8, 23),
              "without quiet hours, nights count too")
        check(perDay(s) == 13 && perDay(fast) == 52 && perDay(once) == 1, "hourly, 8 AM to 9 PM: 13 a day")
        // The Mac's visits by the notch keep the same quiet hours.
        check(!visitAllowed(at: at(8, 23), s, calendar: cal) && !visitAllowed(at: at(9, 7, 59), s, calendar: cal)
              && visitAllowed(at: at(9, 8), s, calendar: cal) && visitAllowed(at: at(8, 20, 59), s, calendar: cal),
              "Mac: no visits from 9 PM to 8 AM, visits from 8 AM to 9 PM")
        check(quietEnds(after: at(8, 23), s, calendar: cal) == at(9, 8) && quietEnds(after: at(8, 15), s, calendar: cal) == nil,
              "Mac: a visit due at 11 PM waits for 8 AM")
        check(visitAllowed(at: at(8, 23), noQuiet, calendar: cal), "Mac: without quiet hours, visits any time")

        // From real progress: right after a whole level is learned, the first reminder is when those words are due.
        guard let pack = TomoLanguages.shared.targets.first(where: { $0.id == "ja" }) else {
            check(false, "the Japanese pack loads"); return false
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-reminders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let progress = TomoProgress(pack: pack, learner: "en", directory: dir)
        let fresh = progress.readyTimes()
        check(fresh.due.isEmpty && fresh.newAt != nil, "a new Tomo: new words are ready, nothing due")
        for id in pack.levels[0].itemIDs { progress.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) }
        let after = progress.readyTimes()
        let wait = after.due.min().map { $0.timeIntervalSince(TomoClock.now) } ?? 0
        check(after.newAt == nil && after.due.count == pack.levels[0].itemIDs.count && wait > 3600 && wait <= 2 * 3600,
              "a whole level learned: no new words until it levels up, the first due in \(Int(wait / 60)) min")
        return ok
    }
}

// MARK: - Scheduling them (iPhone)

@MainActor
public final class TomoReminderCenter: NSObject, ObservableObject {
    public static let shared = TomoReminderCenter()

    /// Changing a setting saves it and schedules again.
    @Published public var settings = TomoReminderSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if started { scheduleSoon() }
        }
    }
    /// What iOS says about notifications for this app (refreshed on each schedule).
    @Published public private(set) var permission: UNAuthorizationStatus = .notDetermined
    /// A reminder was tapped (the app opens into a round on its own: opening it is free play).
    public var onOpen: (@MainActor () -> Void)?

    private var started = false
    private var watch: AnyCancellable?
    private var work: Task<Void, Never>?
    private var center: UNUserNotificationCenter { .current() }
    private let env = ProcessInfo.processInfo.environment

    /// At launch, before the app finishes launching: a tap on a reminder can be why it launched.
    public func install() {
        center.delegate = self
    }

    /// Once Tomo's game runs (after the first run): schedule now, and again whenever progress changes.
    public func start() {
        guard !started else { scheduleSoon(); return }
        started = true
        watch = TomoGame.shared.$progressVersion.dropFirst().sink { [weak self] _ in self?.scheduleSoon() }
        scheduleSoon()
    }

    /// The iOS prompt, after the learner said why (the first run's "Let words find you", or Settings). Testing on a
    /// headless simulator, where nobody can tap Allow: TOMO_NOTIFY_PROVISIONAL asks for quiet delivery, with no prompt.
    public func askPermission() async -> Bool {
        var options: UNAuthorizationOptions = [.alert, .sound]
        if env["TOMO_NOTIFY_PROVISIONAL"] != nil { options.insert(.provisional) }
        NSLog("Tomo reminder: asking iOS for notifications")
        let granted = (try? await center.requestAuthorization(options: options)) ?? false
        permission = await Self.status()
        return granted || permission == .provisional
    }

    public func refreshPermission() async { permission = await Self.status() }

    /// Schedules again in a moment (several changes in a row schedule once).
    public func scheduleSoon() {
        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Replaces every pending reminder with the plan from Tomo's progress now. Delivered ones go too: they're about
    /// a moment that has passed.
    public func reschedule() async {
        let status = await Self.status()
        permission = status
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        let allowed = status == .authorized || status == .provisional
        let progress = TomoGame.shared.progress
        guard settings.on, allowed, !progress.isScratch else { await log(); return }
        let ready = progress.readyTimes()
        let slots = TomoReminders.plan(now: Date(), settings: settings, due: ready.due.map(wallClock),
                                       newAt: ready.newAt.map(wallClock))
        let lines = TomoLanguages.shared.target.reminderLines(age: progress.age)
        let start = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        for (i, slot) in slots.enumerated() {
            let line = lines.isEmpty ? nil : lines[(start + i) % lines.count]
            let content = Self.content(for: slot, line: line)
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slot.at)
            let request = UNNotificationRequest(identifier: "tomo.reminder.\(i)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
        await log()
    }

    /// Tomo's line at its age, then what's waiting: "あそぼ！" / "Let's play! · 3 words waiting".
    private static func content(for slot: TomoReminders.Slot, line: TargetPack.SpokenLine?) -> UNMutableNotificationContent {
        let lang = TomoLanguages.shared, ui = lang.learner
        let status = slot.due > 1 ? ui("glance.due", ["n": "\(slot.due)"]) : slot.due == 1 ? ui("glance.due.one") : ui("glance.new")
        let c = UNMutableNotificationContent()
        c.title = line?.say ?? lang.target.lines.invite ?? lang.target.lines.practice
        c.body = line.map { ui("reminder.body", ["line": $0.translation(ui.id), "status": status]) } ?? status
        c.sound = .default
        c.threadIdentifier = "tomo"
        return c
    }

    /// TOMO_REMINDERS_LOG=1: every pending reminder, as iOS holds it, in the system log ("Tomo reminder …").
    private func log() async {
        guard env["TOMO_REMINDERS_LOG"] != nil else { return }
        let pending = await withCheckedContinuation { (c: CheckedContinuation<[String], Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let f = DateFormatter()
                f.dateFormat = "EEE d MMM HH:mm"
                c.resume(returning: requests.compactMap { r -> (Date, String)? in
                    guard let next = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
                    return (next, "\(f.string(from: next)) · \(r.content.title) · \(r.content.body)")
                }.sorted { $0.0 < $1.0 }.map(\.1))
            }
        }
        NSLog("Tomo reminder: %d pending (%@)", pending.count, settings.on ? "on" : "off")
        for (i, line) in pending.enumerated() { NSLog("Tomo reminder %d: %@", i + 1, line) }
    }

    nonisolated private static func status() async -> UNAuthorizationStatus {
        await withCheckedContinuation { c in
            UNUserNotificationCenter.current().getNotificationSettings { c.resume(returning: $0.authorizationStatus) }
        }
    }
}

extension TomoReminderCenter: UNUserNotificationCenterDelegate {
    /// While the app is open, Tomo is right there: no banner.
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [] }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { TomoReminderCenter.shared.onOpen?() }
    }
}
