import Foundation
import NaturalLanguage

// MARK: - Languages: what the learner speaks × what Tomo speaks
//
// Learner language: the language you speak. It drives the interface text, hints and translations.
//   File: Resources/languages/ui.<id>.json (in this package)
// Target language: the language you're learning. It drives Tomo's words, voice, speech recognition,
//   the "is this the right language?" check, the AI's character rules, and Tomo's levels.
//   File: Resources/languages/<id>.json (a "language pack")
// Translations inside a pack are keyed by learner language: {"en": "doggy", "es": "perrito"}.
// A learner's own language is never the one they learn: the interface is never the target (`allows`, #199).
// No Swift code should contain text in a specific language. See docs/languages.md.

/// Text keyed by learner language, e.g. {"en": "doggy"}. Falls back to English, then anything.
public struct Localized: Codable, Sendable, Equatable {
    public let values: [String: String]

    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }
    public func callAsFunction(_ learner: String) -> String {
        values[learner] ?? values["en"] ?? values.values.first ?? ""
    }
}

// MARK: - Target language pack

public struct TargetPack: Codable, Sendable {
    public struct AgeFormat: Codable, Sendable { public let one: String; public let other: String }
    public struct Labels: Codable, Sendable {
        public let words: String, talk: String, again: String, answerPrompt: String, listening: String
    }
    public struct SpokenLine: Codable, Sendable {
        public let say: String
        public let romanization: String?
        public let translation: Localized
    }
    public struct Lines: Codable, Sendable {
        public let wrong: String, ouch: String, grew: String, bye: String, seeYou: String
        public let levelUp: String     // Tomo reached a new level (not a new age)
        public let practice: String    // Tomo asks to play more ("Play more?"); the widgets' fallback for `invite`
        public let rest: String?       // nothing counts right now: Tomo rests, happy ("Let's play later!"); else `seeYou`
        public let invite: String?     // something is waiting: Tomo calls you over from the Lock Screen ("Let's play!")
        public let hello: SpokenLine?        // first run: Tomo's first words out of the egg ("Boo!")
        public let welcomeBack: SpokenLine?  // first run on a device that joined the learner's Tomo ("Welcome back!")
        public let sayItInMyLanguage: SpokenLine
        public let dontUnderstand: SpokenLine
    }
    /// Tomo's words on its weekly postcard (TomoPostcard.swift): a level-up, signing off, and a week Tomo slept through
    /// (which it never says was quiet).
    public struct PostcardLines: Codable, Sendable {
        public let grew: SpokenLine
        public let bye: SpokenLine
        public let asleep: SpokenLine
    }
    /// Tomo's words in its diary (TomoDiary.swift), from an age on: after days apart (a toddler's sulk), on a run of
    /// days in a row, on a hard day, and at a birthday.
    public struct DiaryLines: Codable, Sendable {
        public let fromAge: Int
        public let missed: SpokenLine
        public let streak: SpokenLine
        public let hard: SpokenLine
        public let birthday: SpokenLine
    }
    public struct AIProfile: Codable, Sendable {
        public let persona: String     // "a {age}-year-old Japanese child"
        public let rules: [String]     // language-specific speaking rules (script, register, typical words)
        public let rulesByAge: [AgeRules]?   // replaces `rules` from an age on (older kids talk differently)
    }
    public struct AgeRules: Codable, Sendable { public let fromAge: Int; public let rules: [String] }
    public struct AgeStarters: Codable, Sendable { public let fromAge: Int; public let starters: [Starter] }
    /// What Tomo says in a reminder (iPhone notifications), from an age on: it talks at its age there too.
    public struct AgeLines: Codable, Sendable { public let fromAge: Int; public let lines: [SpokenLine] }
    public struct Round: Codable, Sendable {
        public let id: String          // "ja:wanwan" (later: Language Reference IDs)
        public let say: String
        public let romanization: String?
        public let meaning: Localized
        public let grownUp: String?
        public let need: String?       // "eat" | "sleep" | "hug": answer is the action, not a picture
        public let answer: String?     // emoji of the right picture (picture rounds)
        public let choices: [String]?  // emojis (picture rounds)
        public let category: String?   // "animals", "action_words"…: keeps "Pick the meaning" choices apart
        public let praise: String
    }
    public struct Example: Codable, Sendable { public let say: String; public let translation: Localized }
    public struct Starter: Codable, Sendable {
        public let id: String?         // "ja:talk-onaka-suita": a starter with an id is an item that grows Tomo
        public let say: String
        public let romanization: String?
        public let translation: Localized
        public let examples: [Example]
    }
    /// One level: a small set of items. Tomo levels up when most of them are known (TomoProgress.swift).
    /// `age` is the age Tomo has on this level, so a level with a higher age than the one before is a birthday.
    public struct Level: Codable, Sendable {
        public let age: Int
        public let rounds: [Round]?    // picture, need and meaning rounds
        public let starters: [Starter]?  // talking ages: opening questions

        public var itemIDs: [String] { (rounds ?? []).map(\.id) + (starters ?? []).compactMap(\.id) }
    }
    public struct OfflineReply: Codable, Sendable {
        public let keys: [String]
        public let say: String         // "{w}" is replaced by the word the learner used
        public let romanization: String?
        public let translation: Localized
        public let mood: String
    }

    public let id: String                  // BCP-47: "ja", "es"
    public let name: Localized             // the language's name in each learner language
    public let nativeName: String          // "日本語"
    public let reviewedByNativeSpeaker: Bool
    public let script: String              // ISO 15924: "Jpan", "Latn"
    public let speechLocale: String        // voice: "ja-JP"
    public let recognitionLocale: String   // speech recognition: "ja-JP"
    public let romanization: Localized?    // name of the romanization ("romaji"), nil if the script is Latin
    public let age: AgeFormat              // "{n}さい", "{n} años"
    public let labels: Labels
    public let lines: Lines
    public let reminders: [AgeLines]?      // reminders (TomoReminders), by age; none: Tomo's `invite`
    public let postcard: PostcardLines?    // Tomo's week (TomoPostcard); none: its level-up and see-you lines
    public let diary: [DiaryLines]?        // Tomo's diary (TomoDiary), by age; none: no sulks, runs or hard days
    public let calendar: TomoCalendar?     // the language's year (TomoCalendar): the seasons' weather; none: no weather
    public let ai: AIProfile
    public let levels: [Level]             // levels[0] = level 1. Each level's age marks when Tomo grows up
    public let startersByAge: [AgeStarters]?   // openers for ages past the levels (testing older Tomos)
    public let offlineReplies: [OfflineReply]
    /// Whole answers that mean "I didn't understand" in the target language (なに？, わかんない).
    public let helpPhrases: [String]?
    /// Web dictionary search for a word, "{q}" = the word (the Zenbu dictionary for Japanese).
    public let dictionarySearchURL: String?

    public func dictionaryURL(for word: String) -> URL? {
        guard let t = dictionarySearchURL, !word.isEmpty else { return nil }
        let q = (word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word)
            .replacingOccurrences(of: ".", with: "%2E")
        return URL(string: t.replacingOccurrences(of: "{q}", with: q))
    }

    public func persona(age: Int) -> String { ai.persona.replacingOccurrences(of: "{age}", with: "\(age)") }
    public func aiRules(age: Int) -> [String] {
        (ai.rulesByAge ?? []).filter { $0.fromAge <= age }.max { $0.fromAge < $1.fromAge }?.rules ?? ai.rules
    }
    /// Every opener in the levels (the talking stage's items).
    public var starters: [Starter] { levels.flatMap { $0.starters ?? [] } }
    /// Every opener in the pack (levels and older ages), once: the wrong choices for a talking question.
    public var allStarters: [Starter] {
        var seen = Set<String>()
        return (starters + (startersByAge ?? []).flatMap(\.starters)).filter { seen.insert($0.say).inserted }
    }
    /// Tomo's reminder lines at this age (the latest set that starts at or below it).
    /// Tomo's diary lines at this age (the latest set that starts at or below it).
    public func diaryLines(age: Int) -> DiaryLines? {
        (diary ?? []).filter { $0.fromAge <= age }.max { $0.fromAge < $1.fromAge }
    }
    public func reminderLines(age: Int) -> [SpokenLine] {
        (reminders ?? []).filter { $0.fromAge <= age }.max { $0.fromAge < $1.fromAge }?.lines ?? []
    }
    public func starters(age: Int) -> [Starter] {
        (startersByAge ?? []).filter { $0.fromAge <= age }.max { $0.fromAge < $1.fromAge }?.starters ?? starters
    }
    /// The first level at an age (testing jumps), or the last level if the levels stop before it.
    public func firstLevel(age: Int) -> Int {
        (levels.firstIndex { $0.age >= age } ?? max(levels.count - 1, 0)) + 1
    }

    public func ageLabel(_ n: Int) -> String {
        (n == 1 ? age.one : age.other).replacingOccurrences(of: "{n}", with: "\(n)")
    }

    /// An answer as Tomo should read it. Japanese typed in romaji ("shigoto shiteru") becomes hiragana
    /// (しごと してる), but only when every word is valid romaji, so English stays English. Other scripts:
    /// unchanged.
    public func normalizedAnswer(_ text: String) -> String {
        guard script == "Jpan", !looksLikeTarget(text, learner: ""), let kana = Self.hiragana(fromRomaji: text)
        else { return text }
        return kana
    }

    /// One romaji syllable, IME style: a vowel; a consonant (or digraph) and a vowel, maybe after a doubled
    /// consonant (kitto, matcha); ん as n, nn or n'; a dash for a long vowel.
    private static let romajiWord = try! NSRegularExpression(pattern:
        "^(?:[aiueo]|(?:([bcdfghjkmprstvz])(?=\\1)|[tc](?=ch))?(?:ky|gy|sh|sy|zy|jy|ch|cy|ty|dy|ny|hy|by|py|my|ry|ts|th|dh|fy|[kgsztdnhbpmyrwfjv])[aiueo]|n'|nn(?![aiueoy])|n(?![aiueoy])|-)+$")

    static func hiragana(fromRomaji text: String) -> String? {
        let lower = text.lowercased()
        let words = lower.split { $0.isWhitespace || ($0.isPunctuation && $0 != "'" && $0 != "-") }.map(String.init)
        guard !words.isEmpty, words.allSatisfy({
            romajiWord.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
        }) else { return nil }
        // Apple's transform reads "nni" as っに; an IME reads it as んに (konnichiwa). A lone "nn" is ん.
        let fixed = lower.replacingOccurrences(of: "n{2,3}(?=[aiueoy])", with: "n'n", options: .regularExpression)
            .replacingOccurrences(of: "nn", with: "n'")
            .replacingOccurrences(of: "-", with: "\u{30FC}")
        return fixed.applyingTransform(.latinToHiragana, reverse: false)
    }

    /// Layer 1 of answer checking: is this text in the target language at all?
    public func looksLikeTarget(_ text: String, learner: String) -> Bool {
        switch script {
        case "Jpan":
            return text.unicodeScalars.contains {
                (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
            }
        default:
            // Same-script languages: ask Apple's language identifier to choose between the two.
            let lower = text.lowercased()
            if offlineReplies.contains(where: { $0.keys.contains(where: { lower.contains($0.lowercased()) }) }) {
                return true
            }
            let r = NLLanguageRecognizer()
            r.languageConstraints = [NLLanguage(rawValue: id), NLLanguage(rawValue: learner)]
            r.processString(text)
            let p = r.languageHypotheses(withMaximum: 2)
            return (p[NLLanguage(rawValue: id)] ?? 0) >= 0.5
        }
    }
}

// MARK: - Learner language (interface text)

public struct LearnerPack: Codable, Sendable {
    public let id: String              // "en"
    public let name: String            // "English"
    public let strings: [String: String]
    /// Whole answers that mean "I didn't understand" in the learner's language ("what", "huh").
    public let helpPhrases: [String]?

    /// `ui("grownUpsSay", ["x": "いぬ"])` → "grown-ups say: いぬ"
    public func callAsFunction(_ key: String, _ args: [String: String] = [:]) -> String {
        var s = strings[key] ?? key
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}

/// Everything language-specific a background task needs, passed by value.
public struct LanguageContext: Sendable {
    public let target: TargetPack
    public let learner: LearnerPack
    public var age = 3                     // Tomo's age: shapes how it talks
    public var targetName: String { target.name(learner.id) }
}

// MARK: - Selection

@MainActor
public final class TomoLanguages: ObservableObject {
    public static let shared = TomoLanguages()

    @Published public private(set) var target: TargetPack
    @Published public private(set) var learner: LearnerPack
    public let targets: [TargetPack]
    public let learners: [LearnerPack]

    public var context: LanguageContext { LanguageContext(target: target, learner: learner) }
    public var targetName: String { target.name(learner.id) }

    private init() {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "languages") ?? []
        let decoder = JSONDecoder()
        var targets: [TargetPack] = [], learners: [LearnerPack] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            if url.lastPathComponent.hasPrefix("ui.") {
                if let l = try? decoder.decode(LearnerPack.self, from: data) { learners.append(l) }
            } else {
                do { targets.append(try decoder.decode(TargetPack.self, from: data)) }
                catch { NSLog("Tomo: couldn't load language pack \(url.lastPathComponent): \(error)") }
            }
        }
        precondition(!targets.isEmpty && !learners.isEmpty, "No language packs in Resources/languages")
        self.targets = targets
        self.learners = learners

        // The system's language is never read: an iPhone or a Mac set to Japanese gets the English interface.
        let env = ProcessInfo.processInfo.environment
        let ud = UserDefaults.standard
        let tid = env["TOMO_TARGET"] ?? ud.string(forKey: "tomoTarget") ?? "ja"
        let wanted = env["TOMO_LEARNER"] ?? ud.string(forKey: "tomoLearner") ?? "en"
        // A saved target this build has no pack for (Spanish, left out of the iPhone's) is Japanese, as by default.
        let target = targets.first { $0.id == tid } ?? targets.first { $0.id == "ja" } ?? targets[0]
        let lid = Self.settle(wanting: wanted, target: target.id, among: learners.map(\.id))
        self.target = target
        learner = learners.first { $0.id == lid } ?? learners[0]
        // Saved before the rule: Settings keeps the interface it moved to. A test run's pair leaves Settings be.
        if !Self.allows(learner: wanted, target: target.id), env["TOMO_TARGET"] == nil, env["TOMO_LEARNER"] == nil {
            ud.set(learner.id, forKey: "tomoLearner")
        }
    }

    // MARK: The pair rule (#199)

    /// A learner's own language is never the one they learn, so the interface is never the language Tomo speaks. The
    /// one place the rule lives: whatever offers or sets a pair asks it (Settings, `select`, the saved pair at launch).
    public nonisolated static func allows(learner: String, target: String) -> Bool { learner != target }

    /// The interface for learning `target`: `wanted` if the rule allows it and there's a pack for it, otherwise English,
    /// otherwise the first allowed one.
    nonisolated static func learnerID(wanting wanted: String, target: String, among ids: [String]) -> String {
        let allowed = ids.filter { allows(learner: $0, target: target) }
        if allowed.contains(wanted) { return wanted }
        return allowed.contains("en") ? "en" : allowed.first ?? ids.first ?? wanted
    }

    /// The interface at launch for the saved pair. One the rule forbids (ja:ja, saved from Settings' "I speak" before
    /// it) gets the interface it allows, and its Tomo, words and logs move there (TomoStore.move), so the learner
    /// carries on with the same Tomo.
    static func settle(wanting wanted: String, target: String, among ids: [String],
                       directory: URL = TomoStore.directory) -> String {
        let id = learnerID(wanting: wanted, target: target, among: ids)
        if !allows(learner: wanted, target: target) {
            TomoStore.move(learner: wanted, to: id, target: target, directory: directory)
        }
        return id
    }

    /// The interface languages a learner of `target` may pick, in pack order.
    public func learners(for target: String) -> [LearnerPack] {
        learners.filter { Self.allows(learner: $0.id, target: target) }
    }

    /// The interface languages Settings offers for the target now: none to pick while it's the only one (Japanese,
    /// learned from English).
    public var learnerChoices: [LearnerPack] { learners(for: target.id) }

    /// "what?", "huh", "?", "なに？", "わかんない": the learner is asking for help, not answering.
    /// Only the whole answer counts, so "なにも" (nothing) is still a real answer.
    public func isHelpRequest(_ text: String) -> Bool {
        let cut = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let norm = text.lowercased().components(separatedBy: cut).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        if norm.isEmpty { return text.contains("?") || text.contains("？") }  // text-ok: matches a full-width question mark
        let phrases = (learner.helpPhrases ?? []) + (target.helpPhrases ?? [])
        return phrases.contains { $0.lowercased() == norm }
    }

    /// Learning a language the interface is in moves the interface to one the rule allows (English, if it can).
    public func select(target id: String) {
        guard let t = targets.first(where: { $0.id == id }), t.id != target.id else { return }
        let lid = Self.learnerID(wanting: learner.id, target: t.id, among: learners.map(\.id))
        if lid != learner.id, let l = learners.first(where: { $0.id == lid }) {
            learner = l
            UserDefaults.standard.set(lid, forKey: "tomoLearner")
        }
        target = t
        UserDefaults.standard.set(id, forKey: "tomoTarget")
    }

    /// Never the language Tomo speaks (`allows`).
    public func select(learner id: String) {
        guard let l = learners.first(where: { $0.id == id }), l.id != learner.id,
              Self.allows(learner: id, target: target.id) else { return }
        learner = l
        UserDefaults.standard.set(id, forKey: "tomoLearner")
    }
}

// MARK: - Self-test: the pair rule, and a pair it forbids moving at launch (#199)

extension TomoLanguages {
    /// Checked by TOMO_SELFTEST (docs/verification.md), in temporary folders: never the learner's data or settings.
    public static func selfTest() -> Bool { TomoCheck.run(selfTest(_:)) }

    /// The same checks, each reported to `check`: the self-test prints them, TomoCoreTests asserts them.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        let ids = ["en", "ja"]
        check(allows(learner: "en", target: "ja") && allows(learner: "ja", target: "en") && !allows(learner: "ja", target: "ja"),
              "the interface is never the language Tomo speaks")
        check(learnerID(wanting: "ja", target: "ja", among: ids) == "en" && learnerID(wanting: "en", target: "en", among: ids) == "ja"
              && learnerID(wanting: "ja", target: "es", among: ids) == "ja" && learnerID(wanting: "fr", target: "ja", among: ids) == "en",
              "a pair the rule forbids gets English (Japanese while English is learned); an allowed one stays as it is")
        let lang = shared
        check(lang.learners(for: "ja").map(\.id) == ["en"],
              "learning Japanese, the interface is English: Settings has no interface language to pick")
        check(lang.learners(for: "en").map(\.id) == ["ja"] && Set(lang.learners(for: "es").map(\.id)) == ["en", "ja"],
              "the Japanese interface stays for another target: English for Japanese speakers")

        guard let pack = lang.targets.first(where: { $0.id == "ja" }), pack.levels.count >= 7 else {
            check(false, "the Japanese pack loads"); return
        }
        var folders: [URL] = []
        defer { folders.forEach { try? FileManager.default.removeItem(at: $0) } }
        func folder() -> URL {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-pair-\(UUID().uuidString)")
            folders.append(dir)
            return dir
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86400) }
        let words = pack.levels.prefix(2).flatMap(\.itemIDs)
        func word(_ n: Int, stage: Int, answered: Date) -> TomoStore.ItemRow {
            .init(id: words[n], stage: stage, due: answered.addingTimeInterval(86400), introduced: day(0), answered: answered,
                  right: stage, wrong: 0, peak: stage)
        }
        func store(_ learner: String, _ dir: URL) -> TomoStore? { TomoStore(learner: learner, target: "ja", directory: dir) }
        // A ja:ja Tomo as a learner who picked Japanese in Settings left it: level 7, two words, a day of logs.
        func seedJaJa(in dir: URL, met: Date) {
            guard let s = store("ja", dir) else { return }
            s.saveTomo(.init(metAt: met, level: 7, age: 2))
            s.saveItem(word(0, stage: 4, answered: day(4)))
            s.saveItem(word(1, stage: 3, answered: day(4)))
            s.logAnswer(at: day(4), item: words[0], level: 7, mode: "picture", result: "right", wrongTries: 0, hint: false,
                        counted: true, before: 3, after: 4)
            s.logGrowth(at: day(3), kind: "level", value: 7)
            s.logVisit(TomoVisit(started: day(4), opened: .card, cardAt: day(4), endedAt: day(4), ended: .finished))
        }
        let ownLook = TomoLook.pairSeed(learner: "ja", target: "ja", metAt: day(1))

        // The launch of a learner set up as ja:ja: English, with its Tomo.
        let only = folder()
        seedJaJa(in: only, met: day(1))
        let lid = settle(wanting: "ja", target: "ja", among: ids, directory: only)
        let moved = TomoProgress(pack: pack, learner: lid, directory: only), en = store("en", only)
        check(lid == "en" && moved.level == 7 && moved.age == 2 && moved.metAt == day(1)
              && moved.items[words[0]]?.stage == 4 && moved.items[words[1]]?.stage == 3,
              "a ja:ja learner from before opens in English with its Tomo: the same meeting, level, age and words")
        check(moved.lookSeed == ownLook, "and the same look, though its pair changed")
        check(en?.answerLog(from: day(0), to: day(9)).count == 1 && en?.growthEvents().map(\.value) == [7]
              && en?.visitLog(from: day(0), to: day(9)).count == 1,
              "its answers, growth and visits come along, so its days together and its stats stay")
        check(store("ja", only)?.loadTomo() == nil && store("ja", only)?.loadItems().isEmpty == true,
              "nothing is left under ja:ja")
        check(FileManager.default.fileExists(atPath: only.appendingPathComponent("cloud-resend").path),
              "iCloud gets it again, under en:ja, when sync starts")
        en?.saveTomo(.init(metAt: day(1).addingTimeInterval(0.4), level: 8, age: 2))
        check(en?.loadTomo()?.seed == ownLook, "saving the same Tomo keeps its look (a meeting stored a little more precisely too)")
        en?.clear(at: day(6))
        en?.saveTomo(.init(metAt: day(6), level: 1, age: 1))
        check(en?.loadTomo()?.seed == nil, "a start over hatches a Tomo with en:ja's own look")

        // A learner with an en:ja Tomo from before they switched: the two merge as two devices' Tomos do.
        let both = folder()
        if let s = store("en", both) {
            s.saveTomo(.init(metAt: day(0), level: 3, age: 1))
            s.saveItem(word(0, stage: 2, answered: day(2)))
            s.saveItem(word(2, stage: 5, answered: day(2)))
            s.logGrowth(at: day(1), kind: "level", value: 3)
        }
        seedJaJa(in: both, met: day(1))
        let merged = TomoStore.move(learner: "ja", to: "en", target: "ja", directory: both) ? store("en", both) : nil
        let tomo = merged?.loadTomo(), items = merged?.loadItems() ?? [:]
        check(tomo?.metAt == day(0) && tomo?.level == 7 && tomo?.age == 2 && tomo?.seed == nil,
              "with an en:ja Tomo too, they merge as two devices' Tomos do: the earlier meeting and its look, the higher level and age")
        check(items.count == 3 && items[words[0]]?.stage == 4 && items[words[1]]?.stage == 3 && items[words[2]]?.stage == 5,
              "every word of both, each as it was answered last")
        check(merged?.answerLog(from: day(0), to: day(9)).count == 1 && merged?.growthEvents().map(\.value) == [3],
              "the answers come along; the moved Tomo's growth log stays with the life it tells")
        let older = folder()
        store("en", older)?.saveTomo(.init(metAt: day(5), level: 2, age: 1))
        seedJaJa(in: older, met: day(1))
        TomoStore.move(learner: "ja", to: "en", target: "ja", directory: older)
        let kept = store("en", older)?.loadTomo()
        check(kept?.metAt == day(1) && kept?.level == 7 && kept?.seed == ownLook,
              "when the moved Tomo met the learner first, it's the one kept, with its look")

        // Nothing to move.
        let empty = folder()
        check(!TomoStore.move(learner: "ja", to: "en", target: "ja", directory: empty)
              && !FileManager.default.fileExists(atPath: empty.path), "with nothing saved, nothing moves and no file is made")
        let fine = folder()
        store("en", fine)?.saveTomo(.init(metAt: day(0), level: 4, age: 1))
        check(settle(wanting: "en", target: "ja", among: ids, directory: fine) == "en" && store("en", fine)?.loadTomo()?.level == 4
              && !FileManager.default.fileExists(atPath: fine.appendingPathComponent("cloud-resend").path),
              "an English speaker learning Japanese opens as before, untouched")
    }
}
