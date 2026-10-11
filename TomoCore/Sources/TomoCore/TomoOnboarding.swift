import Combine
import SwiftUI

// MARK: - First run (issue #88): hatch Tomo, a guided first answer, and how Tomo comes to you
//
// The flow follows the reference app in #83, screen for screen where it fits Tomo: a mascot hello, the first
// word with a guide ("Try it now"), "You just understood your first Japanese", why words come back, how Tomo
// finds you, how often, and what it starts with. Its sign-in, goal question, placement test and level picker
// have nothing to set in Tomodachi (iCloud syncs on its own, every Tomo starts at 1さい), so they're left out.
// Its referral, trial and plan screens would go right before `ready` (`Step.firstRun`); not built, because
// pricing isn't decided.
//
// Who sees it is decided once at launch (`checkAtLaunch`), before anything opens the store: a data folder
// with no saved Tomo is a first run. The "seen" mark is a file in the same folder (onboarding.json), never
// UserDefaults: Debug builds share the owner's bundle ID and defaults (#54), and each test run has its own
// folder. A learner whose Tomo was saved before the first run existed doesn't see it. A device that meets the
// learner's iCloud Tomo during the first run (TomoSync joins it) gets a short "welcome back" instead.
// The guided round answers through TomoProgress, so the first word counts like any other. The views are in
// TomoOnboardingView.swift; each shell shows them its own way (the Mac: a window, TomoOnboardingWindow; the iPhone:
// full screen, TomoPhoneFirstRun).
//
// The iPhone's flow (`Shell.phone`) follows the reference further: after the first word, how Tomo comes to you on
// the iPhone (notifications, the Lock Screen, widgets), the rhythm (the reminders' cadence, TomoReminders), quiet
// hours, "Let words find you" (the only place the iOS notification prompt appears, after its reason), how to add a
// widget, and the Lock Screen card, which starts only if the learner says yes. A phone that joins the learner's
// iCloud Tomo gets "welcome back", then the same setup for this device.
//
// The Mac's flow matches it where a step applies: the rhythm is how often Tomo drops in by the notch, quiet hours
// keep those visits away at night, and "Let Tomo find you" is opening Tomodachi at login (Tomo can only come to you
// while the app runs), on by default but shown, so it's still the learner's choice. No notifications and no widgets
// on the Mac: the notch visits are how Tomo comes to you there, and the visits step says the Dock icon opens
// Tomodachi. A `preview` (the Testing menu) runs the whole flow on a copy of the learner's Tomo: it never writes
// onboarding.json or the saved Tomo, and a setting only changes if it was changed in the preview.

@MainActor
public final class TomoOnboarding: ObservableObject {
    public enum Kind: Sendable { case firstRun, welcomeBack }
    /// Which app shows it: the steps and the rhythm differ (Tomo drops in by the notch, or sends reminders).
    public enum Shell: Sendable { case mac, phone }

    public enum Step: String, CaseIterable, Sendable {
        case hatch          // an egg hatches into the learner's own Tomo
        case round          // Tomo's first word, answered with a guide
        case result         // "You just understood your first Japanese", and when the word comes back
        case visits         // Tomo comes to you: drop-ins by the notch (Mac); notifications and the Lock Screen (iPhone)
        case rhythm         // how often Tomo drops in (Mac) or may send a reminder (iPhone)
        case quiet          // quiet hours: no reminders (iPhone), no visits (Mac)
        case notify         // iPhone: "Let words find you", then the iOS notification prompt
        case login          // Mac: "Let Tomo find you": open Tomodachi at login
        case widget         // iPhone: how to add a widget
        case lockScreen     // iPhone: Tomo's Lock Screen card, yes or not now
        case ready          // what Tomo starts with; then Tomo's first real visit
        case welcomeBack    // this device joined the learner's Tomo from iCloud

        /// The Mac's first run. The reference's referral, trial and plan screens would go before `ready`.
        public static let firstRun: [Step] = [.hatch, .round, .result, .visits, .rhythm, .quiet, .login, .ready]
        /// The iPhone's. Its paywall slot is the same: before `ready`.
        public static let phoneFirstRun: [Step] = [.hatch, .round, .result, .visits, .rhythm, .quiet, .notify, .widget,
                                                   .lockScreen, .ready]
        /// What an iPhone sets up for itself, asked after "welcome back" too.
        public static let phoneSetup: [Step] = [.rhythm, .quiet, .notify, .widget, .lockScreen]
        /// What a Mac sets up for itself, asked after "welcome back" too.
        public static let macSetup: [Step] = [.rhythm, .quiet, .login]
    }

    // MARK: Who sees it

    /// What this launch shows, decided by `checkAtLaunch`.
    public private(set) static var atLaunch: Kind?
    private static var checked = false

    /// Call before anything opens the store: TomoGame hatches a new Tomo when there's none, and then there is.
    /// Test runs (TOMO_DATA_DIR) skip it unless TOMO_ONBOARDING asks: `1` checks like a real launch, a step name
    /// (hatch, round, result, visits, rhythm, quiet, login, notify, widget, lockScreen, ready) or `welcomeBack` opens
    /// there, `0` skips it, and `preview` leaves it to the shell (the Testing menu's preview, on a copy).
    @discardableResult
    public static func checkAtLaunch() -> Kind? {
        if checked { return atLaunch }
        checked = true
        let env = ProcessInfo.processInfo.environment
        let ask = env["TOMO_ONBOARDING"]
        if ask == Step.welcomeBack.rawValue { atLaunch = .welcomeBack; return atLaunch }
        if ask == "preview" { return nil }
        if let ask, Step(rawValue: ask) != nil { atLaunch = .firstRun; return atLaunch }
        if ask == "0" || (ask == nil && env["TOMO_DATA_DIR"] != nil) { return nil }
        atLaunch = needsFirstRun(in: TomoStore.directory) ? .firstRun : nil
        return atLaunch
    }

    /// A folder with no saved Tomo, or one whose first run was quit halfway, gets the first run. A Tomo saved
    /// before the first run existed is a learner who already knows Tomo.
    static func needsFirstRun(in dir: URL) -> Bool {
        if let saved = Saved.load(from: dir) { return saved.finished == nil }
        return !hasSavedTomo(in: dir)
    }

    private static func hasSavedTomo(in dir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("learner.sqlite").path),
              let store = TomoStore(learner: "", target: "", directory: dir) else { return false }
        return !store.syncPairs().isEmpty
    }

    /// onboarding.json in the data folder: when the first run started, and when it was done.
    struct Saved: Codable {
        var started: Date
        var finished: Date?

        @MainActor static func load(from dir: URL = TomoStore.directory) -> Saved? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("onboarding.json")) else { return nil }
            return try? JSONDecoder().decode(Saved.self, from: data)
        }

        @MainActor func save(to dir: URL = TomoStore.directory) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(self) {
                try? data.write(to: dir.appendingPathComponent("onboarding.json"), options: .atomic)
            }
        }
    }

    /// Who sees the first run (TOMO_SELFTEST), in a temporary folder.
    public static func selfTest() -> Bool { TomoCheck.run(selfTest(_:)) }

    /// The same checks, each reported to `check`: the self-test prints them, TomoCoreTests asserts them.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-onboarding-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        check(needsFirstRun(in: dir), "an empty data folder gets the first run")
        TomoStore(learner: "en", target: "ja", directory: dir)?.saveTomo(.init(metAt: Date(), level: 3, age: 1))
        check(!needsFirstRun(in: dir), "a Tomo saved before the first run existed: no first run")
        Saved(started: Date(), finished: nil).save(to: dir)
        check(needsFirstRun(in: dir), "a first run quit halfway shows again")
        Saved(started: Date(), finished: Date()).save(to: dir)
        check(!needsFirstRun(in: dir), "a finished first run never shows again")

        // Quiet hours (#194): the first run writes them only if the learner changed them. Off is off whatever equal
        // times were saved (the owner keeps 0:00 to 0:00 on purpose); switched on, they're the saved hours again.
        func hours(_ from: Int, _ until: Int) -> TomoReminderSettings {
            var s = TomoReminderSettings.standard
            s.quietFrom = from
            s.quietUntil = until
            return s
        }
        /// The step opened on `saved` and its switch was flipped through `flips`: what the flow writes at the end.
        func written(_ saved: TomoReminderSettings, _ flips: [Bool] = []) -> String {
            var picked = saved
            for on in flips { (picked.quietFrom, picked.quietUntil) = quietHours(on, saved: saved) }
            return quietHoursToSave(saved: saved, picked: picked).map { "\($0.from)-\($0.until)" } ?? "nothing"
        }
        let off = hours(0, 0), offAtFive = hours(300, 300), night = hours(22 * 60, 7 * 60)
        check(written(off) == "nothing" && written(off, [true, false]) == "nothing"
              && written(offAtFive) == "nothing" && written(offAtFive, [true, false]) == "nothing",
              "quiet hours saved off (0:00 to 0:00, or 5:00 to 5:00) stay off and unwritten, even switched on and off: "
              + "\(written(offAtFive, [true, false]))")
        check(written(night) == "nothing" && written(night, [false, true]) == "nothing"
              && quietHours(true, saved: night) == (22 * 60, 7 * 60),
              "saved quiet hours 22:00 to 7:00 are kept, and switched off and on again they're back: "
              + "\(written(night, [false, true]))")
        check(written(night, [false]) == "0-0" && written(off, [true]) == "1260-480",
              "quiet hours the learner changed are written: switched off, none; switched on from none, 9 PM to 8 AM")

        // Headings wrap only between their phrases (#225). Kana as escapes: Swift holds no Japanese text.
        let a = "\u{3042}", i = "\u{3044}", u = "\u{3046}", e = "\u{3048}"
        check(TomoLineBreaks.phrased("\(a)\(i) \(u)\(e)") == "\(a)\u{2060}\(i)\u{200B}\(u)\u{2060}\(e)"
              && TomoLineBreaks.phrased("Tomo \(a)\(i)") == "Tomo\u{00A0}\(a)\u{2060}\(i)"
              && TomoLineBreaks.phrased("Let words find you") == "Let words find you"
              && TomoLineBreaks.spoken("Tomo \(a)\(i) \(u)") == "Tomo \(a)\(i)\(u)",
              "a heading wraps only at its spaces: one between two Japanese phrases isn't drawn, one beside a single "
              + "Japanese character never breaks, and English is unchanged")
        // Each phrase fits an iPhone SE's line (375 pt less 24 each side: 327, so 11 kana at 28 pt, 13 at 25; a Latin
        // letter is about 0.6 of one), so a heading never needs to break inside one. The headings are found in the
        // packs, never listed here: every `onboarding.<step>.title`, the result's 「…が分かりました！」 included,
        // at the size it's drawn (`TomoOnboardingView.headingSize`), with `{language}` as each target's name.
        let langs = TomoLanguages.shared
        func isHeading(_ key: String) -> Bool {
            key.hasPrefix("onboarding.") && key.hasSuffix(".title") && key.split(separator: ".").count == 3
        }
        func ems(_ p: String) -> Double { p.reduce(0) { $0 + (TomoLineBreaks.isWide($1) ? 1 : 0.6) } }
        let found = langs.learners.map { Set($0.strings.keys.filter(isHeading)) }
        let tooLong = langs.learners.flatMap { pack in
            pack.strings.keys.filter(isHeading).sorted().flatMap { key in
                let size = TomoOnboardingView.headingSize(key)
                return langs.targets.flatMap { TomoLineBreaks.phrases(pack(key, ["language": $0.name(pack.id)])) }
                    .filter { ems($0) > (327 / size).rounded(.down) }.map { "\($0) (\(Int(size)) pt)" }
            }
        }
        check(tooLong.isEmpty && Set(found).count == 1 && !found[0].isEmpty,
              "every first-run heading in every ui pack (\(found.first?.count ?? 0) each, the same keys) wraps between "
              + "phrases that fit an iPhone SE's line at its size: \(tooLong.count) too long"
              + (tooLong.isEmpty ? "" : ": " + Set(tooLong).sorted().joined(separator: ", ")))
    }

    // MARK: The flow

    public private(set) var kind: Kind
    public private(set) var steps: [Step]
    @Published public private(set) var step: Step
    /// The egg cracked open (the hatch step's animation starts here) and Tomo is out.
    @Published public private(set) var hatchStarted: Date?
    @Published public private(set) var hatched = false
    /// The guided round: Tomo's first new word. Nil when there's nothing new to ask (the round is skipped).
    @Published public private(set) var round: TomoRound?
    @Published public private(set) var phase: TomoPhase = .asking
    @Published public private(set) var outcome: TomoOutcome?
    /// What Tomo is doing, for its TomoBlobView.
    @Published public private(set) var botState: BotState = .idle
    /// When the first word comes back (its first wait), for the result step.
    @Published public private(set) var comesBack: Date?
    /// How often Tomo drops in (`DropIn`), picked on the Mac's rhythm step; saved when the flow ends.
    @Published public var visitEvery: TimeInterval = DropIn.every
    /// iPhone: the reminders' rhythm and quiet hours, notifications and the Lock Screen card, as picked in the flow;
    /// saved when it ends (TomoReminderCenter).
    @Published public var reminders = TomoReminderSettings.load()
    /// The iOS notification prompt is up.
    @Published public private(set) var askingPermission = false
    /// The widget step shows the Home Screen's how-to (else the Lock Screen's).
    @Published public var widgetOnHomeScreen = false
    /// Mac: open Tomodachi at login, as the "Let Tomo find you" step shows it (on unless the learner turns it off; off
    /// where the shell has no login item).
    @Published public var openAtLogin = true
    /// Mac: the login item, from the shell (TomoLoginItem): whether it's on, and turning it on or off. None in a Debug
    /// build, which never opens at login (#54).
    private let loginItem: (isOn: @MainActor () -> Bool, set: @MainActor (Bool) -> Void)?
    /// "Let Tomo find you" offers the switch: the shell has a login item. Without one (a Debug build) it says why.
    public var offersLogin: Bool { loginItem != nil }
    /// The Testing menu's preview, on a copy of the learner's Tomo: nothing is marked done or saved, and a setting
    /// changes only if it was changed here.
    public let preview: Bool
    private let startSettings = TomoReminderCenter.shared.settings
    public let shell: Shell
    /// The shell puts the flow away and lets Tomo drop in.
    public var onFinish: (@MainActor () -> Void)?

    private var item: String?
    private var wrongTries = 0
    private let started = Date()
    private let metHere: Date              // this device's Tomo; an older one arriving means it joined iCloud's
    private var watch: AnyCancellable?
    private var token = 0
    private var game: TomoGame { .shared }
    private var lang: TomoLanguages { .shared }
    /// TOMO_AUTOPLAY: the flow plays itself (one miss, then right), for snapshots.
    private static let autoplay = ProcessInfo.processInfo.environment["TOMO_AUTOPLAY"] != nil

    /// `start`: open at this step (testing). Steps after the round find the first word already answered.
    /// `loginItem` (Mac): the login item's state and setter. `preview`: the Testing menu's run on a copy.
    public init(kind: Kind, shell: Shell = .mac, start: Step? = nil,
                loginItem: (isOn: @MainActor () -> Bool, set: @MainActor (Bool) -> Void)? = nil, preview: Bool = false) {
        let list = kind == .welcomeBack ? Self.welcomeBackSteps(shell, after: nil)
            : shell == .phone ? Step.phoneFirstRun : Step.firstRun
        let first = start.flatMap { list.contains($0) ? $0 : nil } ?? list[0]
        self.kind = kind
        self.shell = shell
        self.loginItem = loginItem
        self.preview = preview
        self.steps = list
        step = first
        metHere = TomoGame.shared.progress.metAt
        // The preview starts from how things are; without a login item it's off.
        if preview || loginItem == nil { openAtLogin = loginItem?.isOn() ?? false }
        if kind == .firstRun && !preview { Saved(started: started, finished: nil).save() }
        if let i = list.firstIndex(of: first), i > 0 {
            hatched = true
            hatchStarted = .distantPast
            if let r = list.firstIndex(of: .round), i > r { prepareRound(); answerQuietly() }
        }
        // Progress from another device (TomoSync): an older Tomo than the one hatched here means this device
        // joined the learner's Tomo. Before the last step, the first run becomes a welcome back.
        if !preview {
            watch = TomoGame.shared.$progressVersion.dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.checkJoined() }
            }
        }
    }

    /// The shell calls this once the flow is on screen.
    public func begin() { entered(step) }

    public var index: Int { steps.firstIndex(of: step) ?? 0 }

    /// The primary button: the step's action, or on to the next step.
    public func next() {
        switch step {
        case .hatch where !hatched: hatch()
        case .round where phase != .right: break
        default:
            if steps.contains(.round) && round == nil { prepareRound() }
            // Nothing new to ask: no round, and nothing to say about it.
            let rest = steps.drop { $0 != step }.dropFirst().filter { round != nil || ($0 != .round && $0 != .result) }
            guard let n = rest.first else { finish(); return }
            go(n)
        }
    }

    /// The flow is done (or closed): it won't show again, and Tomo drops in.
    public func finish() {
        token += 1
        watch = nil
        // Saved only when changed: Debug builds share the owner's defaults, and a test run shouldn't write them.
        if shell == .mac, visitEvery != DropIn.every {
            DropIn.setEvery(visitEvery)
            game.rescheduleVisits()
        }
        // Quiet hours: only what the learner changed (quietHoursToSave); the saved ones stay as they are otherwise.
        let center = TomoReminderCenter.shared
        let quiet = Self.quietHoursToSave(saved: startSettings, picked: reminders)
        if shell == .mac {
            if let quiet {
                var s = center.settings
                s.quietFrom = quiet.from
                s.quietUntil = quiet.until
                center.settings = s
            }
            if let item = loginItem, openAtLogin != item.isOn() { item.set(openAtLogin) }
        }
        if shell == .phone {
            var s = reminders
            if quiet == nil {
                s.quietFrom = center.settings.quietFrom
                s.quietUntil = center.settings.quietUntil
            }
            center.settings = s
        }
        if !preview { Saved(started: started, finished: Date()).save() }
        onFinish?()
        onFinish = nil
    }

    // MARK: Quiet hours

    /// The quiet hours step's switch: on brings back the hours saved before the flow (the learner chose "on", not
    /// new times), or the usual 9 PM to 8 AM when none were; off is none.
    public func setQuietHours(_ on: Bool) {
        let q = Self.quietHours(on, saved: startSettings)
        reminders.quietFrom = q.from
        reminders.quietUntil = q.until
    }

    /// Quiet hours switched `on` or off, from the ones `saved` before the flow, in minutes after midnight.
    static func quietHours(_ on: Bool, saved: TomoReminderSettings) -> (from: Int, until: Int) {
        guard on else { return (0, 0) }
        let q = saved.hasQuietHours ? saved : .standard
        return (q.quietFrom, q.quietUntil)
    }

    /// The quiet hours the flow writes when it ends, or nil to leave the saved ones alone. Off is off whichever equal
    /// times were saved (the owner keeps them off on purpose), so off at the start and at the end writes nothing,
    /// and so do the saved hours brought back; only hours the learner changed are written.
    static func quietHoursToSave(saved: TomoReminderSettings, picked: TomoReminderSettings) -> (from: Int, until: Int)? {
        if !saved.hasQuietHours && !picked.hasQuietHours { return nil }
        if picked.quietFrom == saved.quietFrom && picked.quietUntil == saved.quietUntil { return nil }
        return (picked.quietFrom, picked.quietUntil)
    }

    private func go(_ s: Step) {
        token += 1
        withAnimation(.easeInOut(duration: 0.35)) { step = s }
        entered(s)
    }

    private func entered(_ s: Step) {
        let tok = token
        NSLog("Tomo first run: %@", s.rawValue)        // the order of steps, prompts and the card (verification.md)
        switch s {
        case .hatch:
            botState = .idle
            if Self.autoplay { after(2.5, tok) { self.hatch() } }
        case .round:
            if round == nil { prepareRound() }
            guard let r = round else { return }
            phase = .asking
            outcome = nil
            after(0.6, tok) {
                self.botState = .question
                self.game.speak(r.say, slow: false)
            }
            if Self.autoplay { autoAnswer(tok) }
        case .result:
            botState = .finished
            emote(.proud)
            auto(4, tok)
        case .visits:
            botState = .idle
            // The real Tomo by the notch bounces too: "that's where it lives".
            after(0.8, tok) { NotificationCenter.default.post(name: .botNudge, object: nil) }
            auto(4, tok)
        case .rhythm:
            botState = .idle
            auto(3, tok)
        case .quiet:
            botState = .sleeping
            auto(3, tok)
        case .notify:
            botState = .idle
            emote(.happy)
            if Self.autoplay { after(3, tok) { self.turnOnNotifications() } }
        case .login:
            botState = .idle
            emote(.happy)
            auto(3, tok)
        case .widget:
            botState = .idle
            if Self.autoplay { after(2, tok) { self.widgetOnHomeScreen = true } }
            auto(4.5, tok)
        case .lockScreen:
            botState = .idle
            emote(.love)
            if Self.autoplay { after(3, tok) { self.chooseLockScreen(true) } }
        case .ready:
            botState = .idle
            emote(.happy)
            auto(3.5, tok)
        case .welcomeBack:
            hatched = true
            botState = .idle
            after(0.4, tok) {
                NotificationCenter.default.post(name: .botGreet, object: nil)
                if let line = self.lang.target.lines.welcomeBack { self.game.speak(line.say, slow: false) }
            }
            auto(4, tok)
        }
    }

    // MARK: Hatch

    /// The egg cracks, and Tomo pops out and says hello.
    public func hatch() {
        guard step == .hatch, hatchStarted == nil else { return }
        let tok = token
        hatchStarted = Date()
        TomoSounds.shared.play(.boing)
        after(TomoEgg.crackTime, tok) {
            self.hatched = true
            TomoSounds.shared.play(.hatch)
            self.emote(.surprised)
            self.after(0.7, tok) {
                NotificationCenter.default.post(name: .botGreet, object: nil)
                if let line = self.lang.target.lines.hello { self.game.speak(line.say, slow: false) }
            }
            self.auto(3.5, tok)
        }
    }

    // MARK: The guided round

    private func prepareRound() {
        let p = game.progress
        guard let id = p.newItems.first ?? p.nextFreePlayItem(), let r = p.round(id) else { return }
        item = id
        wrongTries = 0
        round = TomoRound(r, learner: lang.learner, otherMeanings: p.otherMeanings(for: id, learner: lang.learner.id))
    }

    /// Opening the flow past the round (testing): the first word is answered.
    private func answerQuietly() {
        guard let id = item, let r = round else { return }
        let counted = game.progress.answeredRight(id, mode: "\(r.kind)", wrongTries: 0, hint: false)
        outcome = .win(counted: counted)
        phase = .right
        comesBack = game.progress.items[id]?.due.map(wallClock)
    }

    public func replay() {
        guard let r = round else { return }
        game.speak(r.say, slow: true)
    }

    /// Like TomoGame.pick: a right answer counts the word, a wrong one shakes it off and asks again.
    public func pick(_ choice: TomoChoice) {
        guard step == .round, phase == .asking, let r = round, let id = item else { return }
        let tok = token
        let p = game.progress
        let mode = "\(r.kind)"
        if choice.id == r.answer {
            let counted = p.answeredRight(id, mode: mode, wrongTries: wrongTries, hint: false)
            outcome = .win(counted: counted)
            TomoSounds.shared.outcome(.win(counted: counted))
            phase = .right
            botState = .finished
            comesBack = p.items[id]?.due.map(wallClock)
            game.speak(r.praise, slow: false)
            after(2.4, tok) { self.next() }
        } else {
            wrongTries += 1
            p.logTry(id, mode: mode, result: "wrong")
            outcome = .loss
            TomoSounds.shared.outcome(.loss)
            phase = .wrong(choice.id)
            botState = .error
            game.speak(lang.target.lines.wrong, slow: false)
            after(1.3, tok) {
                self.phase = .asking
                self.botState = .question
                self.game.speak(r.say, slow: true)
            }
        }
    }

    // MARK: The iPhone's setup

    /// "Turn on notifications": now the iOS prompt, after the reason on screen. Either way, on to the next step.
    public func turnOnNotifications() {
        guard step == .notify, !askingPermission else { return }
        let tok = token
        askingPermission = true
        Task { @MainActor in
            let granted = await TomoReminderCenter.shared.askPermission()
            askingPermission = false
            reminders.on = granted
            guard token == tok else { return }
            next()
        }
    }

    /// "Not now": no reminders, no prompt. Settings can turn them on later.
    public func notificationsLater() {
        guard step == .notify else { return }
        reminders.on = false
        next()
    }

    /// Tomo's Lock Screen card: yes or not now. The shell starts it once the flow is done.
    public func chooseLockScreen(_ on: Bool) {
        guard step == .lockScreen else { return }
        reminders.lockScreen = on
        next()
    }

    // MARK: Joining the iCloud Tomo

    /// Welcome back, then this device's setup steps still to come.
    private static func welcomeBackSteps(_ shell: Shell, after current: Step?) -> [Step] {
        let setup = shell == .phone ? Step.phoneSetup : Step.macSetup
        guard let current, let i = setup.firstIndex(of: current) else { return [.welcomeBack] + setup }
        return [.welcomeBack] + setup[i...]
    }

    private func checkJoined() {
        guard kind == .firstRun, step != steps.last, game.progress.metAt < metHere.addingTimeInterval(-1) else { return }
        kind = .welcomeBack
        steps = Self.welcomeBackSteps(shell, after: step)
        go(.welcomeBack)
    }

    // MARK: Helpers

    private func emote(_ e: BotEmote) { NotificationCenter.default.post(name: .triggerEmote, object: e) }

    private func auto(_ delay: Double, _ tok: Int) {
        guard Self.autoplay else { return }
        after(delay, tok) { self.next() }
    }

    private func autoAnswer(_ tok: Int) {
        guard let r = round else { return }
        after(2.5, tok) {
            if let wrong = r.choices.first(where: { $0.id != r.answer }) { self.pick(wrong) }
            self.after(2.5, tok) {
                if let right = r.choices.first(where: { $0.id == r.answer }) { self.pick(right) }
            }
        }
    }

    private func after(_ delay: Double, _ tok: Int, _ f: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.token == tok else { return }
                f()
            }
        }
    }
}
