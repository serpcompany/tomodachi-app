import AVFoundation
import SwiftUI

// MARK: - Tomo: a small child who lives in the notch and speaks the language you're learning
//
// Stage 1 (age 1) speaks single baby words; stage 2 (age 2) speaks two-word phrases.
// Each round Tomo says something; the learner shows they understood by picking the
// right picture or doing what Tomo asks (feed / put to bed / hug).
// Stage 3 (age 3) talks: Tomo asks a question and you answer in your own words (TomoChat.swift).
// All words and lines come from the language pack (TomoLanguage.swift, Resources/languages/).

extension Notification.Name {
    static let botTalk = Notification.Name("tomo.botTalk")
    static let botGrow = Notification.Name("tomo.botGrow")
    static let botNudge = Notification.Name("tomo.botNudge")
}

struct TomoChoice: Identifiable, Hashable {
    var id: String { emoji }
    let emoji: String
    let label: String?      // shown only for need actions
}

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
    let answer: String       // emoji of the right choice
    let choices: [TomoChoice]
    let need: TomoNeed?      // non-nil when the round is a need (feed / sleep / hug)
    let praise: String       // what Tomo says when you get it

    static let empty = TomoRound(say: "", romanization: nil, meaning: "", adult: nil, word: "",
                                 answer: "", choices: [], need: nil, praise: "")
}

extension TomoRound {
    init(_ r: TargetPack.Round, learner: LearnerPack) {
        let need = r.need.flatMap(TomoNeed.init(rawValue:))
        let choices = need != nil
            ? TomoNeed.allCases.map { TomoChoice(emoji: $0.emoji, label: learner("need.\($0.rawValue)")) }
            : (r.choices ?? []).map { TomoChoice(emoji: $0, label: nil) }
        self.init(say: r.say, romanization: r.romanization, meaning: r.meaning(learner.id), adult: r.grownUp,
                  word: r.id, answer: need?.emoji ?? r.answer ?? "", choices: choices, need: need, praise: r.praise)
    }
}

enum TomoPhase: Equatable {
    case asking
    case thinking            // talking stage: waiting for Tomo's reply
    case right
    case wrong(String)       // emoji picked
    case grew
}

// MARK: - Drop-ins: Tomo visits now and then instead of asking for study sessions

enum DropIn {
    /// Time between visits. TOMO_DROPIN_EVERY (seconds) overrides it for testing.
    static let every: TimeInterval = ProcessInfo.processInfo.environment["TOMO_DROPIN_EVERY"]
        .flatMap(TimeInterval.init) ?? 10 * 60
    /// Tomo leaves when you haven't touched or hovered the island for this long.
    static let ignoreAfter: TimeInterval = 10
    /// Answering in your own words takes longer than tapping a picture.
    static let ignoreAfterChat: TimeInterval = 20
    /// Answers per visit before Tomo says bye.
    static let roundsPerVisit = 3
    /// After an unfinished visit (closed or ignored), small Tomo bounces this often until you check in.
    /// TOMO_NUDGE_EVERY (seconds) overrides it for testing.
    static let nudgeEvery: TimeInterval = ProcessInfo.processInfo.environment["TOMO_NUDGE_EVERY"]
        .flatMap(TimeInterval.init) ?? 60
}

// MARK: - Game

@MainActor
final class TomoGame: ObservableObject {
    static let shared = TomoGame()

    static let stageGoal = [1: 5, 2: 5, 3: 10]   // understood answers needed to grow (age 3 → 4: later)
    static let chatStage = 3

    @Published private(set) var stage = 1
    @Published private(set) var round: TomoRound = .empty
    @Published private(set) var phase: TomoPhase = .asking
    @Published private(set) var known: Set<String> = []
    @Published var hintShown = false
    /// A visit ended unfinished: red dot on small Tomo + a bounce now and then, until you open it.
    @Published private(set) var pending = false
    private var nextNudge = Date.distantFuture

    // Talking stage (age 3+)
    @Published private(set) var line: TomoLine = .empty
    @Published private(set) var lastAnswer: String?
    @Published private(set) var goodReplies = 0
    @Published private(set) var aiLabel: String?   // nil = offline replies
    @Published var draft = "" { didSet { if draft != oldValue { touch() } } }
    let listener = TomoListener()
    private var transcript: [String] = []
    private var starterIndex = 0

    private var index = 0
    private var token = 0

    // Island hooks, set by AppDelegate
    var openIsland: (@MainActor () -> Void)?
    var closeIsland: (@MainActor () -> Void)?
    var isIslandOpen: (@MainActor () -> Bool)?
    var focusInput: (@MainActor () -> Void)?

    // Visit state: nil = no visit (island closed, or opened by the user for free play)
    private var visitRoundsLeft: Int?
    private var visitDeadline = Date.distantFuture
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
    var isChat: Bool { stage >= Self.chatStage }
    var age: String { lang.target.ageLabel(stage) }
    var goal: Int { Self.stageGoal[stage] ?? 5 }
    var progress: Int { isChat ? goodReplies : knownThisStage }
    var knownThisStage: Int { known.filter { stageWords.contains($0) }.count }
    private var rounds: [TomoRound] {
        let stages = lang.target.stages
        guard !stages.isEmpty else { return [] }
        return stages[min(stage, stages.count) - 1].map { TomoRound($0, learner: lang.learner) }
    }
    private var stageWords: Set<String> { Set(rounds.map(\.word)) }
    private var ignoreAfter: TimeInterval { isChat ? DropIn.ignoreAfterChat : DropIn.ignoreAfter }

    private init() {
        NotificationCenter.default.addObserver(forName: .triggerSlap, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.speak(TomoLanguages.shared.target.lines.ouch, slow: false) }
        }
    }

    // MARK: Flow

    /// Resets progress and starts the visit clock. Call `dropIn(force: true)` to open right away.
    func start() {
        bump()
        stage = 1
        index = 0
        known = []
        round = rounds.first ?? .empty
        phase = .asking
        goodReplies = 0
        transcript = []
        lastAnswer = nil
        visitRoundsLeft = nil
        NotificationCenter.default.post(name: .botGrow, object: CGFloat(0))
        nextDropIn = Date().addingTimeInterval(DropIn.every)
        if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        if let s = ProcessInfo.processInfo.environment["TOMO_STAGE"].flatMap(Int.init), s >= Self.chatStage {
            jumpToChat(open: false)
        }
    }

    func restart() {
        start()
        dropIn(force: true)
    }

    /// Demo shortcut: skip ahead to the talking stage.
    func jumpToChat(open: Bool = true) {
        bump()
        stage = Self.chatStage
        known = Set(lang.target.stages.flatMap { $0.map(\.id) })
        transcript = []
        lastAnswer = nil
        NotificationCenter.default.post(name: .botGrow, object: CGFloat(2))
        if open { visitRoundsLeft = nil; dropIn(force: true) }
    }

    /// Tomo pops open for a short visit. Without `force`, it waits for a natural break.
    func dropIn(force: Bool) {
        if !force {
            if isIslandOpen?() == true || visitRoundsLeft != nil {   // already together
                nextDropIn = Date().addingTimeInterval(DropIn.every); return
            }
            if Self.secondsSinceInput(typing: true) < 3 {            // mid-typing: try again soon
                nextDropIn = Date().addingTimeInterval(20); return
            }
            if Self.secondsSinceInput(typing: false) > 5 * 60 {      // nobody at the Mac
                nextDropIn = Date().addingTimeInterval(60); return
            }
        }
        visitRoundsLeft = DropIn.roundsPerVisit
        visitDeadline = Date().addingTimeInterval(ignoreAfter + 1.5)
        pending = false
        openIsland?()
        wasOpen = true
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .botGreet, object: nil)
        }
        if isChat {
            transcript = []
            lastAnswer = nil
            presentStarter(delay: 1.2)
        } else {
            if !rounds.indices.contains(index) { index = 0 }
            present(rounds[index], delay: 1.2)
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
        if !open { markPending(); endVisit(); return }       // user closed it mid-visit (Esc)
        if AppState.shared.mouseInIsland || listener.isListening {
            visitDeadline = now.addingTimeInterval(ignoreAfter)
        } else if now > visitDeadline && phase == .asking {
            leave(ignored: true)
        }
    }

    private func resumeFreePlay() {
        guard phase == .asking else { return }
        if isChat {
            if transcript.isEmpty { presentStarter(delay: 0.3) } else { speak(line.say, slow: false) }
        } else {
            setBot(.question)
            speak(round.say, slow: false)
        }
    }

    /// Ends the visit. Ignored: a quiet yawn. Finished: wave and say bye.
    private func leave(ignored: Bool) {
        let tok = bump()
        visitRoundsLeft = nil
        nextDropIn = Date().addingTimeInterval(DropIn.every)
        listener.stop()
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
        visitRoundsLeft = nil
        nextDropIn = Date().addingTimeInterval(DropIn.every)
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
        speak(isChat ? line.say : round.say, slow: true)
    }

    // MARK: Ages 1–2: pick the picture / do what Tomo asks

    func pick(_ choice: TomoChoice) {
        guard phase == .asking else { return }
        touch()
        let tok = bump()
        if choice.emoji == round.answer {
            phase = .right
            known.insert(round.word)
            react(to: round)
            after(2.2, tok) { [weak self] in self?.advance() }
        } else {
            phase = .wrong(choice.emoji)
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
        if knownThisStage >= goal {
            growUp()
            return
        }
        index = (index + 1) % rounds.count
        // Skip words already understood while unknown ones remain.
        var tries = 0
        while known.contains(rounds[index].word) && tries < rounds.count {
            index = (index + 1) % rounds.count
            tries += 1
        }
        if spendVisitRound() { leave(ignored: false); return }
        present(rounds[index], delay: 0.3)
    }

    private func growUp() {
        let tok = bump()
        let next = stage + 1
        phase = .grew
        setBot(.finished)
        emote(.proud)
        NotificationCenter.default.post(name: .botGrow, object: CGFloat(next - 1))
        speak(lang.target.lines.grew, slow: false)
        after(4.2, tok) { [weak self] in
            guard let self else { return }
            self.stage = next
            self.index = 0
            self.phase = .asking
            if !self.isChat { self.round = self.rounds.first ?? .empty }
            if self.visitRoundsLeft != nil { self.leave(ignored: false); return }
            if self.isChat { self.presentStarter(delay: 0) } else { self.present(self.round, delay: 0) }
        }
    }

    private func present(_ r: TomoRound, delay: Double) {
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.round = r
            self.hintShown = false
            self.phase = .asking
            self.setBot(.question)
            self.speak(r.say, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if Self.autoplay { self.autoAnswer(tok) }
        }
    }

    // MARK: Age 3+: Tomo asks, you answer in your own words

    private func presentStarter(delay: Double) {
        let starters = lang.target.starters
        guard !starters.isEmpty else { return }
        let starter = TomoLine(starters[starterIndex % starters.count], learner: lang.learner)
        starterIndex += 1
        say(starter, delay: delay)
    }

    private func say(_ l: TomoLine, delay: Double) {
        let tok = bump()
        after(delay, tok) { [weak self] in
            guard let self else { return }
            self.line = l
            self.aiLabel = TomoAI.config.isUsable ? TomoAI.config.label : nil
            self.hintShown = false
            self.phase = .asking
            self.transcript.append("Tomo: \(l.say)")
            self.setBot(.question)
            self.speak(l.say, slow: false)
            self.visitDeadline = Date().addingTimeInterval(self.ignoreAfter)
            if let next = Self.autochat.first {
                Self.autochat.removeFirst()
                self.after(2.5, tok) { [weak self] in self?.answer(next) }
            }
        }
    }

    func submitDraft() { answer(draft) }

    func toggleMic() {
        touch()
        listener.toggle(onPartial: { [weak self] in self?.draft = $0 },
                        onDone: { [weak self] in self?.answer($0) })
    }

    func answer(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChat, phase == .asking, !text.isEmpty else { return }
        touch()
        let tok = bump()
        lastAnswer = text
        draft = ""
        phase = .thinking
        setBot(.thinking)
        transcript.append("Learner: \(text)")
        let ai = TomoAI.config
        aiLabel = ai.isUsable ? ai.label : nil
        let history = transcript
        let language = lang.context
        Task { @MainActor [weak self] in
            let r = await TomoBrain.reply(to: history, ai: ai, language: language)
            guard let self, self.token == tok else { return }
            self.heard(r, tok: tok)
        }
    }

    private func heard(_ r: TomoReply, tok: Int) {
        let reply = TomoLine(say: r.say, romanization: r.romanization, translation: r.translation)
        line = reply
        hintShown = false
        phase = .asking
        transcript.append("Tomo: \(r.say)")
        speak(r.say, slow: false)
        visitDeadline = Date().addingTimeInterval(ignoreAfter)

        guard r.understood else {
            setBot(.question)          // head tilt + "?" : say it again
            return
        }
        goodReplies += 1
        setBot(.idle)
        switch r.mood {
        case "love":      emote(.love)
        case "surprised": emote(.surprised)
        case "proud":     emote(.proud)
        default:          emote(.happy)
        }
        if spendVisitRound() {
            after(2.6, tok) { [weak self] in self?.leave(ignored: false) }
        } else if !(r.say.contains("？") || r.say.contains("?")) {
            presentStarter(delay: 2.8)  // Tomo reacted without asking anything: ask the next question
        } else {
            setBot(.question)
        }
    }

    // MARK: Debug autoplay (TOMO_AUTOPLAY=1, TOMO_AUTOCHAT="answer|answer|…")

    private static let autoplay = ProcessInfo.processInfo.environment["TOMO_AUTOPLAY"] != nil
    private static var autochat: [String] = ProcessInfo.processInfo.environment["TOMO_AUTOCHAT"]?
        .split(separator: "|").map(String.init) ?? []
    private var autoMissed = false

    private func autoAnswer(_ tok: Int) {
        after(2.5, tok) { [weak self] in
            guard let self else { return }
            let r = self.round
            if !self.autoMissed, let wrong = r.choices.first(where: { $0.emoji != r.answer }) {
                self.autoMissed = true
                self.pick(wrong)
                self.after(2.0, self.token) { [weak self] in self?.autoAnswer(self?.token ?? 0) }
            } else if let right = r.choices.first(where: { $0.emoji == r.answer }) {
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
