import AVFoundation
import SwiftUI

// MARK: - Tomo: a small child who lives in the notch and speaks the language you're learning
//
// Age 1 speaks single baby words; age 2 speaks two-word phrases. Each round Tomo says something;
// the learner shows they understood by picking the right picture or doing what Tomo asks (feed / bed / hug).
// Age 3 talks: Tomo asks a question and you answer in your own words (TomoChat.swift).
// What Tomo asks, and how it grows (word stages, levels, ages), comes from TomoProgress.swift: a visit
// brings the items that are due, then at most one new one. All words and lines come from the language pack.

extension Notification.Name {
    static let botTalk = Notification.Name("tomo.botTalk")
    static let botGrow = Notification.Name("tomo.botGrow")
    static let botNudge = Notification.Name("tomo.botNudge")
    static let botLevelUp = Notification.Name("tomo.botLevelUp")
    /// Set Tomo's age step without the growing-up animation (launch, switching language pairs).
    static let botSetGrowth = Notification.Name("tomo.botSetGrowth")
}

/// One answer to pick: a picture (emoji), an action (emoji + label), or a meaning (label only).
struct TomoChoice: Identifiable, Hashable {
    let id: String
    let emoji: String?
    let label: String?
}

/// How a round is asked (issue #14): pick the picture, do what Tomo says, or pick the meaning.
/// A word without a picture or an action is asked by its meaning, so every word can be asked.
enum TomoRoundKind { case picture, need, meaning }

enum TomoNeed: String, CaseIterable {
    case eat, sleep, hug
    var emoji: String {
        switch self {
        case .eat:   "🍙"
        case .sleep: "😴"
        case .hug:   "🤗"
        }
    }
}

struct TomoRound {
    let say: String          // what Tomo says (target language)
    let romanization: String?
    let meaning: String      // in the learner's language
    let adult: String?       // what grown-ups say instead (target language)
    let word: String         // item id counted toward growth ("ja:wanwan")
    let answer: String       // id of the right choice
    let choices: [TomoChoice]
    let kind: TomoRoundKind
    let need: TomoNeed?      // non-nil when the round is a need (feed / sleep / hug)
    let praise: String       // what Tomo says when you get it

    static let empty = TomoRound(say: "", romanization: nil, meaning: "", adult: nil, word: "",
                                 answer: "", choices: [], kind: .picture, need: nil, praise: "")
}

extension TomoRound {
    /// `otherMeanings`: two wrong meanings, for a round asked by meaning (TomoProgress.otherMeanings).
    init(_ r: TargetPack.Round, learner: LearnerPack, otherMeanings: [String] = []) {
        let need = r.need.flatMap(TomoNeed.init(rawValue:))
        let meaning = r.meaning(learner.id)
        let kind: TomoRoundKind, answer: String, choices: [TomoChoice]
        if let need {
            kind = .need
            answer = need.emoji
            choices = TomoNeed.allCases.map { TomoChoice(id: $0.emoji, emoji: $0.emoji, label: learner("need.\($0.rawValue)")) }
        } else if let pic = r.answer, let pics = r.choices {
            kind = .picture
            answer = pic
            choices = pics.map { TomoChoice(id: $0, emoji: $0, label: nil) }
        } else {
            kind = .meaning
            answer = meaning
            choices = ([meaning] + otherMeanings.prefix(2)).shuffled().map { TomoChoice(id: $0, emoji: nil, label: $0) }
        }
        self.init(say: r.say, romanization: r.romanization, meaning: meaning, adult: r.grownUp, word: r.id,
                  answer: answer, choices: choices, kind: kind, need: need, praise: r.praise)
    }
}

/// What an answer earned. Shown as a badge so it's always obvious (docs/concepts.md).
enum TomoOutcome: Equatable {
    case win(counted: Bool)     // understood / right picture. Not counted = practice (the item wasn't due)
    case loss                   // tried, Tomo didn't get it / wrong picture: no credit
    case neutral(String)        // "language" (not in the target language) or "help": no credit, no penalty
}

/// What the help panel below Tomo's card shows (the island grows to fit it).
enum TomoHelp: Equatable {
    case hint                // reading, meaning, example answers
    case explain             // meaning, key parts, tip, ask about a part, say it simpler
    case word(String)        // word card for a clicked word
}

enum TomoPhase: Equatable {
    case asking
    case thinking            // talking stage: waiting for Tomo's reply
    case right
    case wrong(String)       // id of the choice picked
    case leveledUp
    case grew                // a new level that's also a birthday
    case practiceIntro       // nothing counts right now: Tomo offers practice, and the card says it won't count
}

// MARK: - Drop-ins: Tomo visits now and then instead of asking for study sessions

enum DropIn {
    /// Time between visits (Settings → General). 0 = only when you click Tomo.
    /// TOMO_DROPIN_EVERY (seconds) overrides it for testing.
    static var every: TimeInterval {
        if let e = ProcessInfo.processInfo.environment["TOMO_DROPIN_EVERY"].flatMap(TimeInterval.init) { return e }
        return UserDefaults.standard.object(forKey: "tomoVisitEvery") as? Double ?? 20 * 60
    }
    static func setEvery(_ seconds: TimeInterval) { UserDefaults.standard.set(seconds, forKey: "tomoVisitEvery") }
    static let choices: [(seconds: TimeInterval, key: String)] = [
        (10 * 60, "settings.visits.10m"), (20 * 60, "settings.visits.20m"), (45 * 60, "settings.visits.45m"),
        (2 * 3600, "settings.visits.2h"), (0, "settings.visits.off"),
    ]
    /// When the next visit is due, counting from now.
    static func nextVisit() -> Date { every > 0 ? Date().addingTimeInterval(every) : .distantFuture }
    /// Tomo leaves when you haven't touched or hovered the island for this long.
    static let ignoreAfter: TimeInterval = 10
    /// Answering in your own words takes longer than tapping a picture.
    static let ignoreAfterChat: TimeInterval = 20
    /// Answers per visit before Tomo says bye.
    static let roundsPerVisit = 3
    /// A scheduled visit with nothing due or new is skipped; Tomo checks again this often.
    static let recheck: TimeInterval = 5 * 60
    /// After an unfinished visit (closed or ignored), small Tomo bounces this often until you check in.
    /// TOMO_NUDGE_EVERY (seconds) overrides it for testing.
    static let nudgeEvery: TimeInterval = ProcessInfo.processInfo.environment["TOMO_NUDGE_EVERY"]
        .flatMap(TimeInterval.init) ?? 60
}

// MARK: - Game

@MainActor
final class TomoGame: ObservableObject {
    static let shared = TomoGame()

    static let chatStage = 3

    /// Tomo's age (TomoProgress keeps it; it never goes down).
    @Published private(set) var stage = 1
    @Published private(set) var level = 1
    @Published private(set) var levelKnown = 0
    @Published private(set) var levelNeeded = 1
    @Published private(set) var levelProgress = 0.0     // the experience bar (TomoProgress.levelProgress)
    @Published private(set) var levelIsTalk = false
    /// Testing ages run on an in-memory Tomo (Settings → Try another age).
    @Published private(set) var isScratch = false
    /// Bumped whenever saved progress changes, so views reading `progress` (Tomo's words) refresh.
    @Published private(set) var progressVersion = 0
    /// The card's layout: talking (a starter or chat) or a picture round. Older Tomos still review baby words.
    @Published private(set) var talking = false
    @Published private(set) var round: TomoRound = .empty
    @Published private(set) var phase: TomoPhase = .asking
    @Published var hintShown = false
    @Published private(set) var outcome: TomoOutcome? {
        didSet { if let o = outcome { TomoSounds.shared.outcome(o) } }
    }
    /// A visit ended unfinished: red dot on small Tomo + a bounce now and then, until you open it.
    @Published private(set) var pending = false
    private var nextNudge = Date.distantFuture

    /// This round is practice (nothing counts right now), and when answers count again: the header says so.
    @Published private(set) var practiceUntil: Date?
    @Published private(set) var isPracticeRound = false
    /// Practice is a mode you pick, like WaniKani's Extra Study: the first practice round waits for "Practice".
    private var practiceAccepted = false
    private var practiceNext: String?

    // Talking stage (age 3+)
    @Published private(set) var line: TomoLine = .empty
    @Published private(set) var lastAnswer: String?
    @Published private(set) var aiLabel: String?   // nil = offline replies
    @Published var draft = "" { didSet { if draft != oldValue { touch() } } }
    // Help panel below the card: one at a time; the island grows by TomoGrid.helpHeight
    @Published var help: TomoHelp? {
        didSet {
            AppState.shared.helpPanelHeight = help == nil ? 0 : TomoGrid.helpHeight
            if help != nil { touch() }
        }
    }
    @Published private(set) var explanation: TomoExplanation?
    @Published private(set) var explaining = false
    @Published private(set) var simplifying = false
    // Word card (click a word in Tomo's line)
    @Published private(set) var wordCard: TomoWordCard?
    @Published private(set) var lookingUp = false
    /// Debug (TOMO_AUTOLOOKUP=<word index>): "click" a word in Tomo's line.
    @Published var cardRequest: Int?
    let listener = TomoListener()
    private var transcript: [String] = []
    private var starterIndex = 0

    // What Tomo is asking (TomoProgress.swift)
    let progress = TomoProgress(pack: TomoLanguages.shared.target, learner: TomoLanguages.shared.learner.id)
    private var queue: [String] = []        // this visit's items, still to ask
    private var currentItem: String?        // the item being asked; nil = chat follow-up or testing-age opener
    private var lastItem: String?
    private var wrongTries = 0
    private var hintUsed = false
    private var itemCredited = false        // talking: the starter's first understood reply was recorded
    private var taughtNew = false           // this visit already brought its one new item
    private var token = 0

    // Island hooks, set by AppDelegate
    var openIsland: (@MainActor () -> Void)?
    var closeIsland: (@MainActor () -> Void)?
    var isIslandOpen: (@MainActor () -> Bool)?
    var focusInput: (@MainActor () -> Void)?

    // Visit state: nil = no visit (island closed, or opened by the user for free play)
    private var visitRoundsLeft: Int?
    private var visitDeadline = Date.distantFuture
    private var visitStarted = Date.distantPast
    private var nextDropIn = Date.distantFuture
    private var wasOpen = false
    private var ticker: Timer?

    private let speech = AVSpeechSynthesizer()
    private var voices: [String: AVSpeechSynthesisVoice] = [:]

    /// Best installed voice for the target language.
    private var voice: AVSpeechSynthesisVoice? {
        let locale = lang.target.speechLocale
        if let v = voices[locale] { return v }
        let v = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == locale }
            .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: locale)
        voices[locale] = v
        return v
    }

    private var lang: TomoLanguages { .shared }
    var isChat: Bool { talking }
    var age: String { lang.target.ageLabel(stage) }
    private var growthStep: CGFloat { CGFloat(min(max(stage - 1, 0), 2)) }
    private var ignoreAfter: TimeInterval { isChat ? DropIn.ignoreAfterChat : DropIn.ignoreAfter }

    private init() {
        NotificationCenter.default.addObserver(forName: .triggerSlap, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.speak(TomoLanguages.shared.target.lines.ouch, slow: false) }
        }
    }

    // MARK: Flow

    /// Loads the saved Tomo for the current language pair and starts the visit clock.
    /// Call `dropIn(force: true)` to open right away.
    func start() {
        bump()
        progress.load(pack: lang.target, learner: lang.learner.id)
        syncProgress()
        resetRound()
        visitRoundsLeft = nil
        NotificationCenter.default.post(name: .botSetGrowth, object: growthStep)
        nextDropIn = DropIn.nextVisit()
        if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        if let s = ProcessInfo.processInfo.environment["TOMO_STAGE"].flatMap(Int.init), s > 1 {
            jump(toAge: s, open: false)
        }
    }

    /// The language pair changed (or testing ended): bring that pair's saved Tomo.
    func reload() {
        start()
        dropIn(force: true)
    }

    /// A new Tomo for this language pair. Ask first (TomoStartOver.confirm()).
    func startOver() {
        progress.startOver()
        reload()
    }

    /// Testing: move Tomo's clock ahead, so due words come back without waiting.
    func skipAhead(days: Double) {
        TomoClock.offset += days * 86400
        syncProgress()
        nextDropIn = Date()
    }

    private func resetRound() {
        queue = []
        currentItem = nil
        lastItem = nil
        wrongTries = 0
        hintUsed = false
        itemCredited = false
        round = .empty
        line = .empty
        talking = stage >= Self.chatStage
        phase = .asking
        transcript = []
        lastAnswer = nil
        outcome = nil
        help = nil
        isPracticeRound = false
        practiceUntil = nil
        practiceAccepted = false
        practiceNext = nil
    }

    private func syncProgress() {
        stage = progress.age
        level = progress.level
        levelKnown = progress.levelKnown
        levelNeeded = progress.levelNeeded
        levelProgress = progress.levelProgress
        levelIsTalk = progress.isTalkLevel
        isScratch = progress.isScratch
        progressVersion += 1
    }

    /// The visit frequency changed in Settings.
    func rescheduleVisits() { nextDropIn = DropIn.nextVisit() }

    /// Demo shortcut: skip ahead to the talking stage.
    func jumpToChat(open: Bool = true) { jump(toAge: Self.chatStage, open: open) }

    /// Testing: make Tomo any age (1–2 picture rounds, 3+ talking) on an in-memory Tomo; the saved one waits.
    func jump(toAge age: Int, open: Bool = true) {
        bump()
        progress.scratch(age: age)
        syncProgress()
        resetRound()
        NotificationCenter.default.post(name: .botGrow, object: growthStep)
        if open { visitRoundsLeft = nil; dropIn(force: true) }
    }

    /// Tomo pops open for a short visit. Without `force`, it waits for a natural break.
    func dropIn(force: Bool) {
        if !force {
            if isIslandOpen?() == true || visitRoundsLeft != nil {   // already together
                nextDropIn = DropIn.nextVisit(); return
            }
            if Self.secondsSinceInput(typing: true) < 3 {            // mid-typing: try again soon
                nextDropIn = Date().addingTimeInterval(20); return
            }
            if Self.secondsSinceInput(typing: false) > 5 * 60 {      // nobody at the Mac
                nextDropIn = Date().addingTimeInterval(60); return
            }
        }
        // Due items first, then at most one new one. A scheduled visit with nothing to do is skipped;
        // a forced one (launch, "Drop in now") fills up with practice.
        queue = progress.visitItems(limit: DropIn.roundsPerVisit)
        taughtNew = false
        if !force && queue.isEmpty { nextDropIn = Date().addingTimeInterval(DropIn.recheck); return }
        let talks = queue.contains(where: progress.isStarter) || (queue.isEmpty && stage >= Self.chatStage)
        visitRoundsLeft = force || talks ? DropIn.roundsPerVisit : queue.count
        visitDeadline = Date().addingTimeInterval(ignoreAfter + 1.5)
        visitStarted = Date()
        pending = false
        openIsland?()
        wasOpen = true
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .botGreet, object: nil)
        }
        transcript = []
        lastAnswer = nil
        nextItem(delay: 1.2)
    }

    /// What to ask next: this visit's items, then (free play) due or new ones, then practice.
    private func nextItem(delay: Double) {
        if !queue.isEmpty { ask(queue.removeFirst(), delay: delay); return }
        let freePlay = visitRoundsLeft == nil
        if freePlay, let id = progress.nextFreePlayItem() { ask(id, delay: delay); return }
        // A visit that hasn't brought its new item yet (say, a level up just unlocked some) can still bring one.
        if !freePlay, !taughtNew, progress.canTeachNew, let id = progress.newItems.first { ask(id, delay: delay); return }
        practice(delay: delay)
    }

    private func ask(_ id: String, delay: Double) {
        isPracticeRound = !progress.counts(id)
        practiceUntil = isPracticeRound ? progress.nextCountsAt : nil
        if !isPracticeRound { practiceAccepted = false }
        else if !practiceAccepted { offerPractice(id, delay: delay); return }
        if progress.items[id] == nil { taughtNew = true }
        currentItem = id
        wrongTries = 0
        hintUsed = false
        itemCredited = false
        if let r = progress.round(id) {
            talking = false
            present(TomoRound(r, learner: lang.learner,
                              otherMeanings: progress.otherMeanings(for: id, learner: lang.learner.id)), delay: delay)
        } else if let s = progress.starter(id) {
            talking = true
            say(TomoLine(s, learner: lang.learner), delay: delay)
        }
    }

    /// Nothing counts right now. Before the first practice round Tomo says so and waits for "Practice" or "Later",
    /// like WaniKani's "0 reviews": practice is a mode you choose, never something that looks like progress.
    private func offerPractice(_ id: String, delay: Double) {
        practiceNext = id
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.help = nil
            self.outcome = nil
            self.phase = .practiceIntro
            self.setBot(.idle)
            self.emote(.happy)
            self.speak(self.lang.target.lines.practice, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if Self.autoplay { self.after(2.5, tok) { [weak self] in self?.startPractice() } }
        }
    }

    /// "Practice": practice rounds until something counts again.
    func startPractice() {
        guard phase == .practiceIntro, let id = practiceNext else { return }
        touch()
        practiceAccepted = true
        practiceNext = nil
        ask(id, delay: 0.2)
    }

    /// "Later" (or the offer was ignored): Tomo goes back. Nothing is waiting, so no red dot.
    func skipPractice() {
        guard phase == .practiceIntro else { return }
        endVisit()
        pending = false
        closeIsland?()
        wasOpen = false
    }

    /// Nothing due or new: something Tomo already heard. It doesn't count, and the card says so.
    private func practice(delay: Double) {
        let talk = stage >= Self.chatStage
        // Ages past the levels (testing): the age's own openers, as conversation.
        if talk && stage > (lang.target.levels.last?.age ?? Self.chatStage) { presentStarter(delay: delay); return }
        if visitRoundsLeft != nil {
            // In a visit, never the item that was just asked; with nothing else to practice, Tomo says bye.
            guard let id = progress.practiceItem(after: lastItem, talk: talk) else { leave(ignored: false); return }
            ask(id, delay: delay)
            return
        }
        if let id = progress.practiceItem(after: lastItem, talk: talk) ?? progress.practiceItem(after: nil, talk: talk)
            ?? progress.practiceItem(after: nil, talk: !talk) {
            ask(id, delay: delay)
        } else if talk {
            presentStarter(delay: delay)
        } else if let id = progress.levelItems.first {
            ask(id, delay: delay)
        }
    }

    private func tick() {
        let now = Date()
        let open = isIslandOpen?() ?? false
        defer { wasOpen = open }

        guard visitRoundsLeft != nil else {
            // User opened Tomo themselves: free play, no time limit.
            if open && !wasOpen { pending = false; resumeFreePlay() }
            if !open && pending && now >= nextNudge {
                NotificationCenter.default.post(name: .botNudge, object: nil)
                nextNudge = now.addingTimeInterval(DropIn.nudgeEvery)
            }
            if !open && now >= nextDropIn { dropIn(force: false) }
            return
        }
        // Closed mid-visit (Esc). A slow launch can take a moment to open the island, so not right after it opened.
        if !open {
            if now.timeIntervalSince(visitStarted) > 2 { markPending(); endVisit() }
            return
        }
        if AppState.shared.mouseInIsland || listener.isListening || help != nil {
            visitDeadline = now.addingTimeInterval(ignoreAfter)
        } else if now > visitDeadline && phase == .asking {
            leave(ignored: true)
        } else if now > visitDeadline && phase == .practiceIntro {
            skipPractice()
        }
    }

    private func resumeFreePlay() {
        let asked = talking ? line.say : round.say
        // Left on practice, and now something counts (or the offer is stale): pick again.
        let stale = isPracticeRound && progress.somethingCounts
        switch phase {
        case .asking where !asked.isEmpty && !stale:
            if !talking { setBot(.question) }
            speak(asked, slow: false)
        case .asking, .right, .practiceIntro:
            nextItem(delay: 0.3)
        default:
            break
        }
    }

    /// Ends the visit. Ignored: a quiet yawn. Finished: wave and say bye.
    private func leave(ignored: Bool) {
        let tok = bump()
        visitRoundsLeft = nil
        nextDropIn = DropIn.nextVisit()
        listener.stop()
        help = nil
        setBot(.idle)
        if ignored {
            emote(.yawn)
            markPending()
        } else {
            NotificationCenter.default.post(name: .botGreet, object: nil)
            speak(isChat ? lang.target.lines.seeYou : lang.target.lines.bye, slow: false)
        }
        after(1.8, tok) { [weak self] in
            self?.closeIsland?()
            self?.wasOpen = false
        }
    }

    /// × button: put Tomo away. Mid-visit, it waits beside the notch with a red dot.
    func dismiss() {
        guard isIslandOpen?() == true else { return }
        if visitRoundsLeft != nil { markPending() }
        endVisit()
        closeIsland?()
        wasOpen = false
    }

    private func markPending() {
        pending = true
        nextNudge = Date().addingTimeInterval(8)   // first bounce soon after tucking in
    }

    private func endVisit() {
        bump()
        help = nil
        visitRoundsLeft = nil
        nextDropIn = DropIn.nextVisit()
        listener.stop()
        speech.stopSpeaking(at: .immediate)
        if phase == .thinking { phase = .asking }
        setBot(.idle)
    }

    /// Counts one answer toward the visit. Returns true when the visit is over.
    private func spendVisitRound() -> Bool {
        guard let left = visitRoundsLeft else { return false }
        visitRoundsLeft = left - 1
        return left - 1 <= 0
    }

    private static func secondsSinceInput(typing: Bool) -> TimeInterval {
        let src = CGEventSourceStateID.combinedSessionState
        if typing { return CGEventSource.secondsSinceLastEventType(src, eventType: .keyDown) }
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(src, eventType: $0) }.min() ?? 0
    }

    func replay() {
        touch()
        speak(isChat ? line.say : round.say, slow: hintShown)
    }

    func showHint() {
        touch()
        hintShown = true
        if currentItem != nil && !itemCredited { hintUsed = true }
        help = .hint
        speak(isChat ? line.say : round.say, slow: true)
    }

    // MARK: Ages 1–2: pick the picture / do what Tomo asks

    func pick(_ choice: TomoChoice) {
        guard phase == .asking else { return }
        touch()
        help = nil
        let tok = bump()
        let mode = "\(round.kind)"                     // picture | need | meaning, for the answer log
        if choice.id == round.answer {
            let counted = currentItem.map {
                progress.answeredRight($0, mode: mode, wrongTries: wrongTries, hint: hintUsed)
            } ?? false
            outcome = .win(counted: counted)
            phase = .right
            if counted { syncProgress() }          // the experience bar moves right away
            react(to: round)
            after(2.2, tok) { [weak self] in self?.advance() }
        } else {
            wrongTries += 1
            progress.logTry(currentItem, mode: mode, result: "wrong")
            outcome = .loss
            phase = .wrong(choice.id)
            setBot(.error)
            speak(lang.target.lines.wrong, slow: false)
            after(1.2, tok) { [weak self] in
                guard let self else { return }
                self.setBot(.question)
                self.phase = .asking
                self.speak(self.round.say, slow: true)
            }
        }
    }

    private func react(to r: TomoRound) {
        switch r.need {
        case .eat:
            setBot(.finished)
            NotificationCenter.default.post(name: .botGulp, object: nil)
            emote(.happy)
            speak(r.praise, slow: false)
        case .sleep:
            setBot(.sleeping)
            speak(r.praise, slow: true)
        case .hug:
            setBot(.idle)
            emote(.love)
            speak(r.praise, slow: false)
        case nil:
            setBot(.finished)
            speak(r.praise, slow: false)
        }
    }

    private func advance() {
        lastItem = currentItem
        if let up = progress.levelUpIfReady() { celebrate(up); return }
        syncProgress()
        if spendVisitRound() { leave(ignored: false); return }
        nextItem(delay: 0.3)
    }

    /// A new level: a small celebration. A new level with a new age: Tomo grows up (the hatch).
    private func celebrate(_ up: (level: Int, birthday: Bool)) {
        let tok = bump()
        syncProgress()
        help = nil
        phase = up.birthday ? .grew : .leveledUp
        setBot(.finished)
        emote(.proud)
        if up.birthday {
            NotificationCenter.default.post(name: .botGrow, object: growthStep)
            speak(lang.target.lines.grew, slow: false)
        } else {
            NotificationCenter.default.post(name: .botLevelUp, object: nil)
            speak(lang.target.lines.levelUp, slow: false)
        }
        after(4.2, tok) { [weak self] in
            guard let self else { return }
            self.phase = .asking
            self.outcome = nil
            if self.spendVisitRound() { self.leave(ignored: false); return }
            self.nextItem(delay: 0)
        }
    }

    private func present(_ r: TomoRound, delay: Double) {
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.round = r
            self.hintShown = false
            self.help = nil
            self.outcome = nil
            self.phase = .asking
            self.setBot(.question)
            self.speak(r.say, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if Self.autoplay { self.autoAnswer(tok) }
            if let i = ProcessInfo.processInfo.environment["TOMO_AUTOLOOKUP"].flatMap(Int.init), !Self.autoExplained {
                Self.autoExplained = true
                self.after(1.5, tok) { [weak self] in self?.cardRequest = i }
            }
        }
    }

    // MARK: Age 3+: Tomo asks, you answer in your own words

    private func presentStarter(delay: Double) {
        let starters = lang.target.starters(age: stage)
        guard !starters.isEmpty else { return }
        let starter = TomoLine(starters[starterIndex % starters.count], learner: lang.learner)
        starterIndex += 1
        currentItem = nil
        itemCredited = false
        talking = true
        say(starter, delay: delay)
    }

    private func say(_ l: TomoLine, delay: Double) {
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.line = l
            self.outcome = nil
            self.explanation = nil
            if self.help != .hint { self.help = nil }
            self.aiLabel = TomoAI.config.isUsable ? TomoAI.config.label : nil
            self.hintShown = false
            self.phase = .asking
            self.transcript.append("Tomo: \(l.say)")
            self.setBot(.question)
            self.speak(l.say, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if let i = ProcessInfo.processInfo.environment["TOMO_AUTOLOOKUP"].flatMap(Int.init), !Self.autoExplained {
                Self.autoExplained = true
                self.after(1.5, tok) { [weak self] in self?.cardRequest = i }
            }
            if ProcessInfo.processInfo.environment["TOMO_AUTOHINT"] != nil, !Self.autoExplained {
                Self.autoExplained = true
                self.after(1.5, tok) { [weak self] in self?.showHint() }
            }
            if let focus = ProcessInfo.processInfo.environment["TOMO_AUTOEXPLAIN"], !Self.autoExplained {
                Self.autoExplained = true
                self.after(1.5, tok) { [weak self] in
                    self?.openExplain(focus: focus == "-" ? nil : focus)
                }
            }
            if let next = Self.autochat.first {
                Self.autochat.removeFirst()
                self.after(2.5, tok) { [weak self] in self?.answer(next) }
            }
        }
    }

    func submitDraft() { answer(draft) }

    /// Explain the current line in the learner's language; `focus` is the part they're stuck on.
    func explain(focus: String? = nil) {
        guard isChat, !explaining else { return }
        touch()
        explaining = true
        let ai = TomoAI.config, current = line
        var language = lang.context
        language.age = stage
        Task { @MainActor [weak self] in
            let e = await TomoBrain.explain(line: current, focus: focus, ai: ai, language: language)
            guard let self else { return }
            self.explaining = false
            if self.line == current { self.explanation = e }
        }
    }

    /// Click a word in Tomo's line: open its word card in the help panel.
    func openWord(_ word: String) {
        guard !word.isEmpty else { return }
        help = .word(word)
        lookUp(word)
    }

    /// Open the explanation, optionally about one part ("I don't understand …").
    func openExplain(focus: String? = nil) {
        help = .explain
        if focus != nil || explanation == nil { explain(focus: focus) }
    }

    /// Click an example answer in the hint: put it in the answer box.
    func useExample(_ example: String) {
        draft = example.components(separatedBy: " (").first ?? example
    }

    /// Look a word up (AI meaning in context; the Mac Dictionary shows in the card).
    func lookUp(_ word: String) {
        guard !word.isEmpty else { return }
        touch()
        lookingUp = true
        wordCard = nil
        let ai = TomoAI.config, said = isChat ? line.say : round.say, language = lang.context
        Task { @MainActor [weak self] in
            let card = await TomoBrain.define(word: word, line: said, ai: ai, language: language)
            guard let self else { return }
            self.lookingUp = false
            self.wordCard = card
        }
    }

    /// Tomo says the current line again in easier words (target language).
    func sayItSimpler() {
        guard isChat, phase == .asking, !simplifying else { return }
        touch()
        simplifying = true
        let ai = TomoAI.config, current = line
        var language = lang.context
        language.age = stage
        Task { @MainActor [weak self] in
            let easier = await TomoBrain.simpler(line: current, ai: ai, language: language)
            guard let self else { return }
            self.simplifying = false
            guard self.line == current else { return }
            if let easier {
                self.line = easier
                self.explanation = nil
                self.transcript.append("Tomo (simpler): \(easier.say)")
                self.setBot(.question)
                self.speak(easier.say, slow: true)
            } else {
                self.speak(current.say, slow: true)   // offline: just slower
            }
        }
    }

    func toggleMic() {
        touch()
        listener.toggle(onPartial: { [weak self] in self?.draft = $0 },
                        onDone: { [weak self] in self?.answer($0) })
    }

    func answer(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChat, phase == .asking, !text.isEmpty else { return }
        if lang.isHelpRequest(text) {
            progress.logTry(itemCredited ? nil : currentItem, mode: "talk", result: "help")
            outcome = .neutral("help")
            lastAnswer = text
            draft = ""
            setBot(.question)
            showHint()          // repeats slowly and shows meaning + example answers
            return
        }
        touch()
        help = nil
        let tok = bump()
        lastAnswer = text
        draft = ""
        phase = .thinking
        setBot(.thinking)
        transcript.append("Learner: \(text)")
        let ai = TomoAI.config
        aiLabel = ai.isUsable ? ai.label : nil
        let history = transcript
        var language = lang.context
        language.age = stage
        Task { @MainActor [weak self] in
            let r = await TomoBrain.reply(to: history, ai: ai, language: language)
            guard let self, self.token == tok else { return }
            self.heard(r, tok: tok)
        }
    }

    private func heard(_ r: TomoReply, tok: Int) {
        let reply = TomoLine(say: r.say, romanization: r.romanization, translation: r.translation)
        line = reply
        explanation = nil
        hintShown = false
        phase = .asking
        transcript.append("Tomo: \(r.say)")
        speak(r.say, slow: false)
        visitDeadline = Date().addingTimeInterval(ignoreAfter)

        let item = itemCredited ? nil : currentItem     // after the starter is credited, it's conversation
        guard r.understood else {
            outcome = r.wrongLanguage ? .neutral("language") : .loss
            if item != nil && !r.wrongLanguage { wrongTries += 1 }
            progress.logTry(item, mode: "talk", result: r.wrongLanguage ? "language" : "wrong")
            setBot(.question)          // head tilt + "?" : say it again
            return
        }
        var counted = false
        if let item {
            counted = progress.answeredRight(item, mode: "talk", wrongTries: wrongTries, hint: hintUsed)
            itemCredited = true
            lastItem = item
        } else {
            progress.logTry(nil, mode: "talk", result: "right")
        }
        outcome = .win(counted: counted)
        setBot(.idle)
        switch r.mood {
        case "love":      emote(.love)
        case "surprised": emote(.surprised)
        case "proud":     emote(.proud)
        default:          emote(.happy)
        }
        if counted, let up = progress.levelUpIfReady() {
            after(2.6, tok) { [weak self] in self?.celebrate(up) }
            return
        }
        syncProgress()
        if spendVisitRound() {
            after(2.6, tok) { [weak self] in self?.leave(ignored: false) }
        } else if !(r.say.contains("？") || r.say.contains("?")) {  // text-ok: matches a full-width question mark
            nextItem(delay: 2.8)        // Tomo reacted without asking anything: ask the next thing
        } else {
            setBot(.question)
        }
    }

    // MARK: Debug autoplay (TOMO_AUTOPLAY=1, TOMO_AUTOCHAT="answer|answer|…")

    private static let autoplay = ProcessInfo.processInfo.environment["TOMO_AUTOPLAY"] != nil
    private static var autochat: [String] = ProcessInfo.processInfo.environment["TOMO_AUTOCHAT"]?
        .split(separator: "|").map(String.init) ?? []
    private var autoMissed = false
    private static var autoExplained = false

    private func autoAnswer(_ tok: Int) {
        after(2.5, tok) { [weak self] in
            guard let self else { return }
            let r = self.round
            if !self.autoMissed, let wrong = r.choices.first(where: { $0.id != r.answer }) {
                self.autoMissed = true
                self.pick(wrong)
                self.after(2.0, self.token) { [weak self] in self?.autoAnswer(self?.token ?? 0) }
            } else if let right = r.choices.first(where: { $0.id == r.answer }) {
                self.pick(right)
            }
        }
    }

    // MARK: Helpers

    func speak(_ text: String, slow: Bool) {
        guard AppState.shared.soundEnabled else { return }
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.pitchMultiplier = 1.6
        u.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.85)
        speech.speak(u)
        NotificationCenter.default.post(name: .botTalk, object: nil)
    }

    private func setBot(_ s: BotState) {
        AppState.shared.updateTask(id: "tomo", state: s)
    }

    private func emote(_ e: BotEmote) {
        NotificationCenter.default.post(name: .triggerEmote, object: e)
    }

    private func touch() {
        AppState.shared.lastActivity = .now
        visitDeadline = Date().addingTimeInterval(ignoreAfter)
    }

    @discardableResult
    private func bump() -> Int { token += 1; return token }

    private func after(_ delay: Double, _ tok: Int, _ f: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.token == tok else { return }
                f()
            }
        }
    }
}
