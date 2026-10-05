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
        public let practice: String    // nothing counts right now: Tomo asks to play anyway ("Play more?")
        public let sayItInMyLanguage: SpokenLine
        public let dontUnderstand: SpokenLine
    }
    public struct AIProfile: Codable, Sendable {
        public let persona: String     // "a {age}-year-old Japanese child"
        public let rules: [String]     // language-specific speaking rules (script, register, typical words)
        public let rulesByAge: [AgeRules]?   // replaces `rules` from an age on (older kids talk differently)
    }
    public struct AgeRules: Codable, Sendable { public let fromAge: Int; public let rules: [String] }
    public struct AgeStarters: Codable, Sendable { public let fromAge: Int; public let starters: [Starter] }
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

        let env = ProcessInfo.processInfo.environment
        let ud = UserDefaults.standard
        let tid = env["TOMO_TARGET"] ?? ud.string(forKey: "tomoTarget") ?? "ja"
        let lid = env["TOMO_LEARNER"] ?? ud.string(forKey: "tomoLearner") ?? "en"
        target = targets.first { $0.id == tid } ?? targets[0]
        learner = learners.first { $0.id == lid } ?? learners[0]
    }

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

    public func select(target id: String) {
        guard let t = targets.first(where: { $0.id == id }), t.id != target.id else { return }
        target = t
        UserDefaults.standard.set(id, forKey: "tomoTarget")
    }

    public func select(learner id: String) {
        guard let l = learners.first(where: { $0.id == id }), l.id != learner.id else { return }
        learner = l
        UserDefaults.standard.set(id, forKey: "tomoLearner")
    }
}
