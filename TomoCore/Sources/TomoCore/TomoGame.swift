import AVFoundation
import SwiftUI

// MARK: - Tomo: a small child who lives in the notch and speaks the language you're learning
//
// Age 1 speaks single baby words; age 2 speaks two-word phrases. Each round Tomo says something;
// the learner shows they understood by picking the right picture or doing what Tomo asks (feed / bed / hug).
// Age 3 talks: Tomo asks a question and you answer in your own words (TomoChat.swift).
// What Tomo asks, and how it grows (word stages, levels, ages), comes from TomoProgress.swift: a visit
// brings the items that are due, then at most one new one. All words and lines come from the language pack.

/// One answer to pick: a picture (emoji), an action (emoji + label), or a meaning (label only).
public struct TomoChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let emoji: String?
    public let label: String?
}

/// How a round is asked (issue #14): pick the picture, do what Tomo says, or pick the meaning.
/// A word without a picture or an action is asked by its meaning, so every word can be asked.
/// Talking questions (3さい) are asked by meaning or by `reply`: pick an answer that fits.
public enum TomoRoundKind: Sendable { case picture, need, meaning, reply }

public enum TomoNeed: String, CaseIterable, Sendable {
    case eat, sleep, hug
    public var emoji: String {
        switch self {
        case .eat:   "🍙"
        case .sleep: "😴"
        case .hug:   "🤗"
        }
    }
}

public struct TomoRound: Sendable {
    public let say: String          // what Tomo says (target language)
    public let romanization: String?
    public let meaning: String      // in the learner's language
    public let adult: String?       // what grown-ups say instead (target language)
    public let word: String         // item id counted toward growth ("ja:wanwan")
    public let answer: String       // id of the right choice
    public let choices: [TomoChoice]
    public let kind: TomoRoundKind
    public let need: TomoNeed?      // non-nil when the round is a need (feed / sleep / hug)
    public let praise: String       // what Tomo says when you get it

    public static let empty = TomoRound(say: "", romanization: nil, meaning: "", adult: nil, word: "",
                                 answer: "", choices: [], kind: .picture, need: nil, praise: "")
}

extension TomoRound {
    /// `otherMeanings`: two wrong meanings, for a round asked by meaning (TomoProgress.otherMeanings).
    public init(_ r: TargetPack.Round, learner: LearnerPack, otherMeanings: [String] = []) {
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

extension TomoRound {
    /// A talking question asked with choices: what Tomo's line means (`.meaning`), or a reply that fits
    /// (`.reply`). The wrong choices come from the pack's other questions, never one of this question's own
    /// replies. Falls back to the meaning when there aren't enough replies to choose from.
    public init(_ s: TargetPack.Starter, kind: TomoRoundKind, others: [TargetPack.Starter], learner: LearnerPack,
                praise: String) {
        let meaning = s.translation(learner.id)
        let pool = others.filter { $0.say != s.say }
        let own = Set(s.examples.map(\.say))
        let replies = Array(Set(pool.flatMap { $0.examples.map(\.say) }).subtracting(own)).shuffled()
        let asReply = kind == .reply && !s.examples.isEmpty && replies.count >= 2
        let answer = asReply ? s.examples.randomElement()!.say : meaning
        let wrong = asReply ? Array(replies.prefix(2))
            : Array(Set(pool.map { $0.translation(learner.id) }).subtracting([meaning]).shuffled().prefix(2))
        self.init(say: s.say, romanization: s.romanization, meaning: meaning, adult: nil, word: s.id ?? "",
                  answer: answer, choices: ([answer] + wrong).shuffled().map { TomoChoice(id: $0, emoji: nil, label: $0) },
                  kind: asReply ? .reply : .meaning, need: nil, praise: praise)
    }
}

/// What an answer earned. Shown as a badge so it's always obvious (docs/concepts.md).
public enum TomoOutcome: Equatable, Sendable {
    case win(counted: Bool)     // understood / right picture. Not counted = practice (the item wasn't due)
    case loss                   // tried, Tomo didn't get it / wrong picture: no credit
    case neutral(String)        // "language" (not in the target language) or "help": no credit, no penalty
}

extension TomoOutcome {
    /// Why an answer got this result, in the learner's language ("Not in Japanese: no score, no penalty").
    @MainActor public func why(_ lang: TomoLanguages) -> String {
        switch self {
        case .win(let counted): lang.learner(counted ? "outcome.why.win" : "outcome.why.practice")
        case .loss:            lang.learner("outcome.why.loss")
        case .neutral(let r):  lang.learner("outcome.why.\(r)", ["language": lang.targetName])
        }
    }
}

/// What the help panel below Tomo's card shows (the island grows to fit it).
public enum TomoHelp: Equatable, Sendable {
    case hint                // reading, meaning, example answers
    case explain             // meaning, key parts, tip, ask about a part, say it simpler
    case word(String)        // word card for a clicked word
}

public enum TomoPhase: Equatable, Sendable {
    case asking
    case thinking            // talking stage: waiting for Tomo's reply
    case right
    case wrong(String)       // id of the choice picked
    case leveledUp
    case grew                // a new level that's also a birthday
    /// Nothing counts right now: Tomo rests, and the card says when it's back and what's left to grow, with Practice
    /// as a button. It holds until something counts or the learner picks Practice (TomoGame.rest).
    case resting
}

// MARK: - Drop-ins: Tomo visits now and then instead of asking for study sessions

public enum DropIn {
    /// Time between visits (Settings → General). 0 = only when you click Tomo.
    /// TOMO_DROPIN_EVERY (seconds) overrides it for testing.
    public static var every: TimeInterval {
        if let e = ProcessInfo.processInfo.environment["TOMO_DROPIN_EVERY"].flatMap(TimeInterval.init) { return e }
        return UserDefaults.standard.object(forKey: "tomoVisitEvery") as? Double ?? 20 * 60
    }
    public static func setEvery(_ seconds: TimeInterval) { UserDefaults.standard.set(seconds, forKey: "tomoVisitEvery") }
    public static let choices: [(seconds: TimeInterval, key: String)] = [
        (10 * 60, "settings.visits.10m"), (20 * 60, "settings.visits.20m"), (45 * 60, "settings.visits.45m"),
        (2 * 3600, "settings.visits.2h"), (0, "settings.visits.off"),
    ]
    /// When the next visit is due, counting from now.
    public static func nextVisit() -> Date { every > 0 ? Date().addingTimeInterval(every) : .distantFuture }
    /// Tomo leaves when you haven't touched or hovered the island for this long.
    public static let ignoreAfter: TimeInterval = 10
    /// Answering in your own words takes longer than tapping a picture.
    public static let ignoreAfterChat: TimeInterval = 20
    /// Answers per visit before Tomo says bye.
    public static let roundsPerVisit = 3
    /// A scheduled visit with nothing due or new is skipped; Tomo checks again this often.
    public static let recheck: TimeInterval = 5 * 60
    /// After an unfinished visit (closed or ignored), small Tomo bounces this often until you check in.
    /// TOMO_NUDGE_EVERY (seconds) overrides it for testing.
    public static let nudgeEvery: TimeInterval = ProcessInfo.processInfo.environment["TOMO_NUDGE_EVERY"]
        .flatMap(TimeInterval.init) ?? 60
}

// MARK: - Game

@MainActor
public final class TomoGame: ObservableObject {
    public static let shared = TomoGame()

    public static let chatStage = 3
    /// Talking questions are asked with choices (pick the meaning, pick the reply), not typed answers
    /// (decisions.md, 2026-10-06). The typed conversation below stays, switched off, for when it returns.
    public static let talkAsChoices = true

    /// Tomo's age (TomoProgress keeps it; it never goes down).
    @Published public private(set) var stage = 1
    @Published public private(set) var level = 1
    @Published public private(set) var levelKnown = 0
    @Published public private(set) var levelNeeded = 1
    @Published public private(set) var levelProgress = 0.0     // the experience bar (TomoProgress.levelProgress)
    @Published public private(set) var levelStanding = 0.0     // where its words stand now (TomoProgress.levelStanding)
    /// What's left before the next level (`whatsLeft()` says it in words).
    @Published public private(set) var levelLeft = TomoProgress.Left(words: 0, nextAt: nil)
    @Published public private(set) var levelIsLast = false
    @Published public private(set) var levelIsTalk = false
    /// Testing ages run on an in-memory Tomo (Settings → Try another age).
    @Published public private(set) var isScratch = false
    /// Bumped whenever saved progress changes, so views reading `progress` (Tomo's words) refresh.
    @Published public private(set) var progressVersion = 0
    /// The card's layout: talking (a starter or chat) or a picture round. Older Tomos still review baby words.
    @Published public private(set) var talking = false
    @Published public private(set) var round: TomoRound = .empty
    @Published public private(set) var phase: TomoPhase = .asking
    @Published public var hintShown = false
    @Published public private(set) var outcome: TomoOutcome? {
        didSet { if let o = outcome { TomoSounds.shared.outcome(o) } }
    }
    /// A visit ended unfinished: red dot on small Tomo + a bounce now and then, until you open it.
    @Published public private(set) var pending = false
    private var nextNudge = Date.distantFuture

    /// Nothing counts right now (Tomo rests, or this round is practice): when answers count again. The card says so.
    @Published public private(set) var countsAgainAt: Date?
    @Published public private(set) var isPracticeRound = false
    /// Practice is a mode you pick, like WaniKani's Extra Study: until "Practice", Tomo rests instead of asking.
    private var practiceAccepted = false

    // Talking stage (age 3+)
    @Published public private(set) var line: TomoLine = .empty
    @Published public private(set) var lastAnswer: String?
    @Published public private(set) var aiLabel: String?   // nil = offline replies
    @Published public var draft = "" { didSet { if draft != oldValue { touch() } } }
    // Help panel below the card: one at a time; the shell makes room for it (`onHelpChange`)
    @Published public var help: TomoHelp? {
        didSet {
            onHelpChange?(help)
            if help != nil { touch() }
        }
    }
    @Published public private(set) var explanation: TomoExplanation?
    @Published public private(set) var explaining = false
    @Published public private(set) var simplifying = false
    // Word card (click a word in Tomo's line)
    @Published public private(set) var wordCard: TomoWordCard?
    @Published public private(set) var lookingUp = false
    /// Debug (TOMO_AUTOLOOKUP=<word index>): "click" a word in Tomo's line.
    @Published public var cardRequest: Int?
    public let listener = TomoListener()
    private var transcript: [String] = []
    private var starterIndex = 0

    // What Tomo is asking (TomoProgress.swift)
    public let progress = TomoProgress(pack: TomoLanguages.shared.target, learner: TomoLanguages.shared.learner.id)
    private var queue: [String] = []        // this visit's items, still to ask
    private var currentItem: String?        // the item being asked; nil = chat follow-up or testing-age opener
    private var lastItem: String?
    private var wrongTries = 0
    private var hintUsed = false
    private var itemCredited = false        // talking: the starter's first understood reply was recorded
    private var taughtNew = false           // this visit already brought its one new item
    private var token = 0

    /// Tomo's voice and sound effects (the speaker button, Settings → General).
    @Published public var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Shell hooks: the Mac island sets them in AppDelegate; the iPhone app sets its own (issue #52)
    public var openIsland: (@MainActor () -> Void)?
    public var closeIsland: (@MainActor () -> Void)?
    public var isIslandOpen: (@MainActor () -> Bool)?
    public var focusInput: (@MainActor () -> Void)?
    /// The pointer is over Tomo's card: a visit doesn't time out while you're there.
    public var isPointerInside: (@MainActor () -> Bool)?
    /// Tomo's state changed (asking, thinking, right, wrong…): the shell passes it to its TomoBlob.
    public var onBotState: (@MainActor (BotState) -> Void)?
    /// The help panel opened or closed: the shell makes room for it.
    public var onHelpChange: (@MainActor (TomoHelp?) -> Void)?
    /// The learner did something in Tomo's card.
    public var onActivity: (@MainActor () -> Void)?
    /// Seconds since the last key press (`typing`) or any input. Without it, a visit never waits.
    public var secondsSinceInput: (@MainActor (_ typing: Bool) -> TimeInterval)?

    // Visit state: nil = no visit (island closed, or opened by the user for free play)
    private var visitRoundsLeft: Int?
    private var visitDeadline = Date.distantFuture
    private var visitStarted = Date.distantPast
    private var nextDropIn = Date.distantFuture
    private var wasOpen = false
    private var ticker: Timer?

    private let speech = AVSpeechSynthesizer()
    private var voices: [String: VoiceBox] = [:]
    private var voicesLoading: Set<String> = []

    /// Best installed voice for the target language, once `loadVoice` has found it (nil until then).
    private var voice: AVSpeechSynthesisVoice? {
        let locale = lang.target.speechLocale
        if let box = voices[locale] { return box.voice }
        loadVoice(locale)
        return nil
    }

    /// Finds the best installed voice off the main thread: on iOS 27, `speechVoices()` on the main thread can
    /// wait forever on the speech service, freezing the app the first time Tomo speaks.
    private func loadVoice(_ locale: String) {
        guard voices[locale] == nil, voicesLoading.insert(locale).inserted else { return }
        Task.detached(priority: .userInitiated) {
            let found = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == locale }
                .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: locale)
            let box = VoiceBox(found)
            await MainActor.run { [weak self] in
                self?.voices[locale] = box
                self?.voicesLoading.remove(locale)
            }
        }
    }

    private var lang: TomoLanguages { .shared }
    public var isChat: Bool { talking }
    public var age: String { lang.target.ageLabel(stage) }
    /// Tomo's age step for drawing: 0 = 1さい … 5 = 6さい (TomoBlob).
    public var growthStep: CGFloat { CGFloat(min(max(stage - 1, 0), TomoLook.ages - 1)) }
    private var ignoreAfter: TimeInterval { isChat ? DropIn.ignoreAfterChat : DropIn.ignoreAfter }

    private init() {
        NotificationCenter.default.addObserver(forName: .triggerSlap, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.speak(TomoLanguages.shared.target.lines.ouch, slow: false) }
        }
    }

    // MARK: Flow

    /// Loads the saved Tomo for the current language pair and starts the visit clock.
    /// Call `dropIn(force: true)` to open right away.
    public func start() {
        bump()
        loadVoice(lang.target.speechLocale)        // ready before Tomo's first line
        progress.load(pack: lang.target, learner: lang.learner.id)
        syncProgress()
        TomoSync.shared.onArrived = { [weak self] pairs in self?.progressArrived(pairs) }
        TomoSync.shared.start()
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

    /// Progress from another device was merged into the store (TomoSync): show it. A testing Tomo stays.
    private func progressArrived(_ pairs: Set<TomoSync.Pair>) {
        guard !progress.isScratch, pairs.contains(.init(learner: lang.learner.id, target: lang.target.id)) else { return }
        progress.load(pack: lang.target, learner: lang.learner.id)
        syncProgress()
    }

    /// The language pair changed (or testing ended): bring that pair's saved Tomo.
    public func reload() {
        start()
        dropIn(force: true)
    }

    /// A new Tomo for this language pair. Ask first (TomoStartOver.confirm()).
    public func startOver() {
        progress.startOver()
        reload()
    }

    /// Testing: move Tomo's clock ahead, so due words come back without waiting.
    public func skipAhead(days: Double) {
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
        talking = !Self.talkAsChoices && stage >= Self.chatStage
        phase = .asking
        transcript = []
        lastAnswer = nil
        outcome = nil
        help = nil
        isPracticeRound = false
        countsAgainAt = nil
        practiceAccepted = false
    }

    private func syncProgress() {
        TomoLook.current = TomoLook(seed: TomoLook.seed(learner: lang.learner.id, target: lang.target.id,
                                                        metAt: progress.metAt))
        stage = progress.age
        level = progress.level
        levelKnown = progress.levelKnown
        levelNeeded = progress.levelNeeded
        levelProgress = progress.levelProgress
        levelStanding = progress.levelStanding
        levelLeft = progress.levelLeft
        levelIsLast = progress.isLastLevel
        levelIsTalk = progress.isTalkLevel
        isScratch = progress.isScratch
        progressVersion += 1
    }

    /// The visit frequency changed in Settings.
    public func rescheduleVisits() { nextDropIn = DropIn.nextVisit() }

    /// Demo shortcut: skip ahead to the talking stage.
    public func jumpToChat(open: Bool = true) { jump(toAge: Self.chatStage, open: open) }

    /// Testing: make Tomo any age (1–2 picture rounds, 3+ talking) on an in-memory Tomo; the saved one waits.
    public func jump(toAge age: Int, open: Bool = true) {
        bump()
        progress.scratch(age: age)
        syncProgress()
        resetRound()
        NotificationCenter.default.post(name: .botGrow, object: growthStep)
        if open { visitRoundsLeft = nil; dropIn(force: true) }
    }

    /// Tomo pops open for a short visit. Without `force`, it waits for a natural break.
    public func dropIn(force: Bool) {
        if !force {
            if isIslandOpen?() == true || visitRoundsLeft != nil {   // already together
                nextDropIn = DropIn.nextVisit(); return
            }
            if secondsSinceInput?(true) ?? .infinity < 3 {            // mid-typing: try again soon
                nextDropIn = Date().addingTimeInterval(20); return
            }
            if secondsSinceInput?(false) ?? 0 > 5 * 60 {      // nobody at the Mac
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
        // The level was finished without a level up yet (say, its last word came from another device): celebrate first.
        if let up = progress.levelUpIfReady() { celebrate(up); return }
        if !queue.isEmpty { ask(queue.removeFirst(), delay: delay); return }
        let freePlay = visitRoundsLeft == nil
        if freePlay, let id = progress.nextFreePlayItem() { ask(id, delay: delay); return }
        // A visit that hasn't brought its new item yet (say, a level up just unlocked some) can still bring one.
        if !freePlay, !taughtNew, progress.canTeachNew, let id = progress.newItems.first { ask(id, delay: delay); return }
        practice(delay: delay)
    }

    private func ask(_ id: String, delay: Double) {
        let practice = !progress.counts(id)
        // Nothing counts, and the learner hasn't picked Practice: Tomo rests instead of asking.
        if practice && !practiceAccepted { rest(delay: delay); return }
        if !practice { practiceAccepted = false }
        isPracticeRound = practice
        countsAgainAt = practice ? progress.nextCountsAt : nil
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
            if Self.talkAsChoices {
                talking = false
                // New: what it means first (understanding before answering); then it alternates with replies.
                let kind: TomoRoundKind = (progress.items[id]?.stage ?? 0) % 2 == 0 ? .meaning : .reply
                present(starterRound(s, kind: kind), delay: delay)
            } else {
                talking = true
                say(TomoLine(s, learner: lang.learner), delay: delay)
            }
        }
    }

    /// Nothing counts right now: Tomo rests, happy, and the card says when it's back and what's left to grow, with
    /// Practice as a button (like WaniKani's "0 reviews" and its Extra Study: practice is a mode you choose, never
    /// something that looks like progress). Rest holds until something counts (`tick` notices, and Tomo asks it) or
    /// the learner picks Practice. Opening Tomo again, on any device, shows the rest again, never a new offer.
    private func rest(delay: Double) {
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.currentItem = nil
            self.help = nil
            self.outcome = nil
            self.isPracticeRound = false
            self.practiceAccepted = false
            self.syncProgress()
            self.countsAgainAt = self.progress.nextCountsAt
            self.phase = .resting
            self.setBot(.idle)
            self.emote(.happy)
            self.speak(self.lang.target.lines.rest ?? self.lang.target.lines.seeYou, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if Self.autoplay { self.after(2.5, tok) { [weak self] in self?.startPractice() } }
        }
    }

    /// "Practice" on the resting card: practice rounds until something counts again. They never move the bar.
    public func startPractice() {
        guard phase == .resting else { return }
        touch()
        practiceAccepted = true
        nextItem(delay: 0.2)
    }

    /// A visit that found nothing to count was left alone: Tomo tucks back in, still resting. Nothing is waiting,
    /// so no red dot.
    private func tuckIn() {
        endVisit()
        pending = false
        closeIsland?()
        wasOpen = false
    }

    /// Something counts again (a word's wait is half over, a new day's words, progress from another device, Tomo's
    /// clock): while Tomo rests or practices on screen, it notices and asks that instead.
    private func offerWhatCounts() {
        let practicing = phase == .asking && isPracticeRound && help == nil
        guard phase == .resting || practicing, let id = progress.nextFreePlayItem() else { return }
        ask(id, delay: 0.1)
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
        // "Next at 8:37" has come: say what's left again.
        if let at = levelLeft.nextAt, at <= TomoClock.now { levelLeft = progress.levelLeft }
        if open && wasOpen && progress.somethingCounts { offerWhatCounts() }
        debugReopen(open: open, now: now)

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
        if isPointerInside?() == true || listener.isListening || help != nil {
            visitDeadline = now.addingTimeInterval(ignoreAfter)
        } else if now > visitDeadline && phase == .asking {
            leave(ignored: true)
        } else if now > visitDeadline && phase == .resting {
            tuckIn()
        }
    }

    /// Tomo was opened (clicked on the Mac, the iPhone app came to the front): pick up where it was.
    private func resumeFreePlay() {
        let asked = talking ? line.say : round.say
        let counts = progress.somethingCounts
        switch phase {
        case .resting where !counts:
            rest(delay: 0.3)                    // still nothing counts: Tomo says hi and rests, never a new offer
        case .asking where isPracticeRound && !counts:
            rest(delay: 0.3)                    // practice was for that sitting; picking it again is a click away
        case .asking where !asked.isEmpty && !isPracticeRound:
            if !talking { setBot(.question) }
            speak(asked, slow: false)
        case .asking, .right, .resting:
            nextItem(delay: 0.3)                // something counts now (or nothing was asked yet): ask it
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
    public func dismiss() {
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

    public func replay() {
        touch()
        speak(isChat ? line.say : round.say, slow: hintShown)
    }

    public func showHint() {
        touch()
        hintShown = true
        if currentItem != nil && !itemCredited { hintUsed = true }
        help = .hint
        speak(isChat ? line.say : round.say, slow: true)
    }

    // MARK: Ages 1–2: pick the picture / do what Tomo asks

    public func pick(_ choice: TomoChoice) {
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

    /// A new level: a small celebration. A new level with a new age: Tomo grows up (it evolves).
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
        let s = starters[starterIndex % starters.count]
        starterIndex += 1
        currentItem = nil
        itemCredited = false
        if Self.talkAsChoices {
            talking = false
            present(starterRound(s, kind: starterIndex % 2 == 0 ? .reply : .meaning), delay: delay)
            return
        }
        talking = true
        say(TomoLine(s, learner: lang.learner), delay: delay)
    }

    private func starterRound(_ s: TargetPack.Starter, kind: TomoRoundKind) -> TomoRound {
        TomoRound(s, kind: kind, others: lang.target.allStarters, learner: lang.learner, praise: lang.target.lines.levelUp)
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

    public func submitDraft() { answer(draft) }

    /// Explain the current line in the learner's language; `focus` is the part they're stuck on.
    public func explain(focus: String? = nil) {
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
    public func openWord(_ word: String) {
        guard !word.isEmpty else { return }
        // Looking a word up while it's asked shows its meaning: it counts like the hint (no step up).
        if phase == .asking, currentItem != nil, !itemCredited { hintUsed = true }
        help = .word(word)
        lookUp(word)
    }

    /// Open the explanation, optionally about one part ("I don't understand …").
    public func openExplain(focus: String? = nil) {
        help = .explain
        if focus != nil || explanation == nil { explain(focus: focus) }
    }

    /// Click an example answer in the hint: put it in the answer box.
    public func useExample(_ example: String) {
        draft = example.components(separatedBy: " (").first ?? example
    }

    /// Look a word up (AI meaning in context; the Mac Dictionary shows in the card).
    public func lookUp(_ word: String) {
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
    public func sayItSimpler() {
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

    public func toggleMic() {
        touch()
        listener.toggle(onPartial: { [weak self] in self?.draft = $0 },
                        onDone: { [weak self] in self?.answer($0) })
    }

    public func answer(_ text: String) {
        let text = lang.target.normalizedAnswer(text.trimmingCharacters(in: .whitespacesAndNewlines))
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

    /// Debug (TOMO_AUTOREOPEN=<seconds>): that long after Tomo first tucks back in, it opens once, the way a click on
    /// small Tomo does (free play), so a test run can see what the learner gets then.
    private static let autoReopen = ProcessInfo.processInfo.environment["TOMO_AUTOREOPEN"].flatMap(TimeInterval.init)
    private var seenOpen = false
    private var closedAt: Date?
    private var autoReopened = false

    private func debugReopen(open: Bool, now: Date) {
        guard let wait = Self.autoReopen, !autoReopened else { return }
        if open { seenOpen = true; closedAt = nil; return }
        guard seenOpen else { return }
        let closed = closedAt ?? now
        closedAt = closed
        if now.timeIntervalSince(closed) >= wait {
            autoReopened = true
            openIsland?()
        }
    }

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

    public func speak(_ text: String, slow: Bool) {
        guard soundEnabled else { return }
        guard let voice else { return }            // still being found (loadVoice): stay quiet, never guess a voice
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.pitchMultiplier = 1.6
        u.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.85)
        speech.speak(u)
        NotificationCenter.default.post(name: .botTalk, object: nil)
    }

    private func setBot(_ s: BotState) {
        onBotState?(s)
    }

    private func emote(_ e: BotEmote) {
        NotificationCenter.default.post(name: .triggerEmote, object: e)
    }

    private func touch() {
        onActivity?()
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

// MARK: - Resting, practice and what's left, in words (the card, the header and Settings, on every device)

extension TomoGame {
    /// What's left before the next level: "1 more word to Lv 2 · ready now", or "· next at 8:37" (`when: false`
    /// leaves the time out). On the last level, how many words finish it.
    public func whatsLeft(when: Bool = true) -> String {
        let ui = lang.learner, left = levelLeft, next = "\(level + 1)"
        guard left.words > 0 else { return ui(levelIsLast ? "left.lastDone" : "left.done", ["next": next]) }
        let n = "\(left.words)", one = left.words == 1
        let words = levelIsLast ? ui(one ? "left.last.one" : "left.last", ["n": n])
            : ui(one ? "left.one" : "left.many", ["n": n, "next": next])
        guard when else { return words }
        return words + " · " + (left.nextAt.map { ui("left.next", ["time": tomoTime($0, lang)]) } ?? ui("left.ready"))
    }

    /// The resting card's lines: when Tomo's back ("Back at 10:12"), and what's left to grow, with its time only when
    /// that isn't when Tomo's back anyway.
    public var restLines: (back: String, left: String) {
        let same = levelLeft.nextAt.map { abs($0.timeIntervalSince(countsAgainAt ?? .distantPast)) < 60 } ?? true
        return (timeText("rest.back", until: countsAgainAt, lang), whatsLeft(when: !same))
    }
}

/// "Back at 10:12" (`key`, with `{time}`), or the `key.now` variant when there's no time to give.
@MainActor public func timeText(_ key: String, until: Date?, _ lang: TomoLanguages) -> String {
    guard let until else { return lang.learner("\(key).now") }
    return lang.learner(key, ["time": tomoTime(until, lang)])
}

/// A time on Tomo's clock, short and for the middle of a sentence: "8:37 AM", or "tomorrow at 4:00 AM".
@MainActor public func tomoTime(_ date: Date, _ lang: TomoLanguages) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: lang.learner.id)
    f.timeStyle = .short
    f.formattingContext = .middleOfSentence
    if !Calendar.current.isDateInToday(wallClock(date)) { f.dateStyle = .short; f.doesRelativeDateFormatting = true }
    return f.string(from: wallClock(date))
}

/// A time on Tomo's clock (which testing can move ahead, TomoClock) on the device's clock.
@MainActor public func wallClock(_ d: Date) -> Date { d.addingTimeInterval(Date().timeIntervalSince(TomoClock.now)) }

/// A voice handed from the background lookup to the main actor (AVSpeechSynthesisVoice isn't marked Sendable;
/// it's read-only once found).
private final class VoiceBox: @unchecked Sendable {
    let voice: AVSpeechSynthesisVoice?
    init(_ voice: AVSpeechSynthesisVoice?) { self.voice = voice }
}
