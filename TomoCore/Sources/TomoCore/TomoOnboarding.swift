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
        case quiet          // iPhone: quiet hours, no reminders
        case notify         // iPhone: "Let words find you", then the iOS notification prompt
        case widget         // iPhone: how to add a widget
        case lockScreen     // iPhone: Tomo's Lock Screen card, yes or not now
        case ready          // what Tomo starts with; then Tomo's first real visit
        case welcomeBack    // this device joined the learner's Tomo from iCloud

        /// The Mac's first run. The reference's referral, trial and plan screens would go before `ready`.
        public static let firstRun: [Step] = [.hatch, .round, .result, .visits, .rhythm, .ready]
        /// The iPhone's. Its paywall slot is the same: before `ready`.
        public static let phoneFirstRun: [Step] = [.hatch, .round, .result, .visits, .rhythm, .quiet, .notify, .widget,
                                                   .lockScreen, .ready]
        /// What an iPhone sets up for itself, asked after "welcome back" too.
        public static let phoneSetup: [Step] = [.rhythm, .quiet, .notify, .widget, .lockScreen]
    }

    // MARK: Who sees it

    /// What this launch shows, decided by `checkAtLaunch`.
    public private(set) static var atLaunch: Kind?
    private static var checked = false

    /// Call before anything opens the store: TomoGame hatches a new Tomo when there's none, and then there is.
    /// Test runs (TOMO_DATA_DIR) skip it unless TOMO_ONBOARDING asks: `1` checks like a real launch, a step name
    /// (hatch, round, result, visits, rhythm, quiet, notify, widget, lockScreen, ready) or `welcomeBack` opens there,
    /// `0` skips it.
    @discardableResult
    public static func checkAtLaunch() -> Kind? {
        if checked { return atLaunch }
        checked = true
        let env = ProcessInfo.processInfo.environment
        let ask = env["TOMO_ONBOARDING"]
        if ask == Step.welcomeBack.rawValue { atLaunch = .welcomeBack; return atLaunch }
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
    public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-onboarding-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        check(needsFirstRun(in: dir), "an empty data folder gets the first run")
        TomoStore(learner: "en", target: "ja", directory: dir)?.saveTomo(.init(metAt: Date(), level: 3, age: 1))
        check(!needsFirstRun(in: dir), "a Tomo saved before the first run existed: no first run")
        Saved(started: Date(), finished: nil).save(to: dir)
        check(needsFirstRun(in: dir), "a first run quit halfway shows again")
        Saved(started: Date(), finished: Date()).save(to: dir)
        check(!needsFirstRun(in: dir), "a finished first run never shows again")
        return ok
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
    public init(kind: Kind, shell: Shell = .mac, start: Step? = nil) {
        let list = kind == .welcomeBack ? Self.welcomeBackSteps(shell, after: nil)
            : shell == .phone ? Step.phoneFirstRun : Step.firstRun
        let first = start.flatMap { list.contains($0) ? $0 : nil } ?? list[0]
        self.kind = kind
        self.shell = shell
        self.steps = list
        step = first
        metHere = TomoGame.shared.progress.metAt
        if kind == .firstRun { Saved(started: started, finished: nil).save() }
        if let i = list.firstIndex(of: first), i > 0 {
            hatched = true
            hatchStarted = .distantPast
            if let r = list.firstIndex(of: .round), i > r { prepareRound(); answerQuietly() }
        }
        // Progress from another device (TomoSync): an older Tomo than the one hatched here means this device
        // joined the learner's Tomo. Before the last step, the first run becomes a welcome back.
        watch = TomoGame.shared.$progressVersion.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.checkJoined() }
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
        if shell == .mac, kind == .firstRun, visitEvery != DropIn.every {
            DropIn.setEvery(visitEvery)
            game.rescheduleVisits()
        }
        if shell == .phone { TomoReminderCenter.shared.settings = reminders }
        Saved(started: started, finished: Date()).save()
        onFinish?()
        onFinish = nil
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

    /// Welcome back, then (on the iPhone) this device's setup steps still to come.
    private static func welcomeBackSteps(_ shell: Shell, after current: Step?) -> [Step] {
        guard shell == .phone else { return [.welcomeBack] }
        let setup = Step.phoneSetup
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
