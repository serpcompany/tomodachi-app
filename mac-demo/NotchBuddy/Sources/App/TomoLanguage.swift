import Foundation
import NaturalLanguage

// MARK: - Languages: what the learner speaks × what Tomo speaks
//
// Learner language: the language you speak. It drives the interface text, hints and translations.
//   File: Resources/languages/ui.<id>.json
// Target language: the language you're learning. It drives Tomo's words, voice, speech recognition,
//   the "is this the right language?" check, the AI's character rules, and (later) age data.
//   File: Resources/languages/<id>.json (a "language pack")
// Translations inside a pack are keyed by learner language: {"en": "doggy", "es": "perrito"}.
// No Swift code should contain text in a specific language. See docs/languages.md.

/// Text keyed by learner language, e.g. {"en": "doggy"}. Falls back to English, then anything.
struct Localized: Codable, Sendable, Equatable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }
    func callAsFunction(_ learner: String) -> String {
        values[learner] ?? values["en"] ?? values.values.first ?? ""
    }
}

// MARK: - Target language pack

struct TargetPack: Codable, Sendable {
    struct AgeFormat: Codable, Sendable { let one: String; let other: String }
    struct Labels: Codable, Sendable {
        let words: String, talk: String, again: String, answerPrompt: String, listening: String
    }
    struct SpokenLine: Codable, Sendable {
        let say: String
        let romanization: String?
        let translation: Localized
    }
    struct Lines: Codable, Sendable {
        let wrong: String, ouch: String, grew: String, bye: String, seeYou: String
        let sayItInMyLanguage: SpokenLine
        let dontUnderstand: SpokenLine
    }
    struct AIProfile: Codable, Sendable {
        let persona: String     // "a 3-year-old Japanese child"
        let rules: [String]     // language-specific speaking rules (script, register, typical words)
    }
    struct Round: Codable, Sendable {
        let id: String          // "ja:wanwan" (later: Language Reference IDs)
        let say: String
        let romanization: String?
        let meaning: Localized
        let grownUp: String?
        let need: String?       // "eat" | "sleep" | "hug": answer is the action, not a picture
        let answer: String?     // emoji of the right picture (picture rounds)
        let choices: [String]?  // emojis (picture rounds)
        let praise: String
    }
    struct Example: Codable, Sendable { let say: String; let translation: Localized }
    struct Starter: Codable, Sendable {
        let say: String
        let romanization: String?
        let translation: Localized
        let examples: [Example]
    }
    struct OfflineReply: Codable, Sendable {
        let keys: [String]
        let say: String         // "{w}" is replaced by the word the learner used
        let romanization: String?
        let translation: Localized
        let mood: String
    }

    let id: String                  // BCP-47: "ja", "es"
    let name: Localized             // the language's name in each learner language
    let nativeName: String          // "日本語"
    let reviewedByNativeSpeaker: Bool
    let script: String              // ISO 15924: "Jpan", "Latn"
    let speechLocale: String        // voice: "ja-JP"
    let recognitionLocale: String   // speech recognition: "ja-JP"
    let romanization: Localized?    // name of the romanization ("romaji"), nil if the script is Latin
    let age: AgeFormat              // "{n}さい", "{n} años"
    let labels: Labels
    let lines: Lines
    let ai: AIProfile
    let stages: [[Round]]           // stages[0] = 1-year-old rounds, stages[1] = 2-year-old rounds
    let starters: [Starter]         // conversation openers from the talking stage on
    let offlineReplies: [OfflineReply]
    /// Whole answers that mean "I didn't understand" in the target language (なに？, わかんない).
    let helpPhrases: [String]?

    func ageLabel(_ n: Int) -> String {
        (n == 1 ? age.one : age.other).replacingOccurrences(of: "{n}", with: "\(n)")
    }

    /// Layer 1 of answer checking: is this text in the target language at all?
    func looksLikeTarget(_ text: String, learner: String) -> Bool {
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

struct LearnerPack: Codable, Sendable {
    let id: String              // "en"
    let name: String            // "English"
    let strings: [String: String]
    /// Whole answers that mean "I didn't understand" in the learner's language ("what", "huh").
    let helpPhrases: [String]?

    /// `ui("grownUpsSay", ["x": "いぬ"])` → "grown-ups say: いぬ"
    func callAsFunction(_ key: String, _ args: [String: String] = [:]) -> String {
        var s = strings[key] ?? key
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}

/// Everything language-specific a background task needs, passed by value.
struct LanguageContext: Sendable {
    let target: TargetPack
    let learner: LearnerPack
    var targetName: String { target.name(learner.id) }
}

// MARK: - Selection

@MainActor
final class TomoLanguages: ObservableObject {
    static let shared = TomoLanguages()

    @Published private(set) var target: TargetPack
    @Published private(set) var learner: LearnerPack
    let targets: [TargetPack]
    let learners: [LearnerPack]

    var context: LanguageContext { LanguageContext(target: target, learner: learner) }
    var targetName: String { target.name(learner.id) }

    private init() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "languages") ?? []
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
    func isHelpRequest(_ text: String) -> Bool {
        let cut = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let norm = text.lowercased().components(separatedBy: cut).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        if norm.isEmpty { return text.contains("?") || text.contains("？") }
        let phrases = (learner.helpPhrases ?? []) + (target.helpPhrases ?? [])
        return phrases.contains { $0.lowercased() == norm }
    }

    func select(target id: String) {
        guard let t = targets.first(where: { $0.id == id }), t.id != target.id else { return }
        target = t
        UserDefaults.standard.set(id, forKey: "tomoTarget")
    }

    func select(learner id: String) {
        guard let l = learners.first(where: { $0.id == id }), l.id != learner.id else { return }
        learner = l
        UserDefaults.standard.set(id, forKey: "tomoLearner")
    }
}
