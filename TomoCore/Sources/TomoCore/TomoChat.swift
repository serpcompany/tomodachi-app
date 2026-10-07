import AVFoundation
import Foundation
import Speech

// MARK: - Talking stage: Tomo asks, you answer in your own words (typed or spoken)

public struct TomoLine: Equatable, Sendable {
    public let say: String
    public let romanization: String?
    public let translation: String       // in the learner's language
    public var examples: [String] = []   // shown with the hint: things you could answer

    public static let empty = TomoLine(say: "", romanization: nil, translation: "")
}

extension TomoLine {
    public init(_ s: TargetPack.Starter, learner: LearnerPack) {
        self.init(say: s.say, romanization: s.romanization, translation: s.translation(learner.id),
                  examples: s.examples.map { "\($0.say) (\($0.translation(learner.id)))" })
    }
}

/// A learner-language explanation of one of Tomo's lines (the Explain panel).
public struct TomoExplanation: Sendable, Equatable {
    public struct Part: Sendable, Equatable, Hashable { public let phrase: String; public let meaning: String }
    public let translation: String
    public let parts: [Part]
    public let tip: String?
    public let usedAI: Bool
}

public struct TomoReply: Sendable {
    public let say: String
    public let romanization: String?
    public let translation: String
    public let understood: Bool
    public let mood: String              // happy | love | surprised | proud | confused
    public var wrongLanguage = false     // stopped by the language check: neutral, not a miss

    public init(say: String, romanization: String?, translation: String, understood: Bool, mood: String,
         wrongLanguage: Bool = false) {
        self.say = say; self.romanization = romanization; self.translation = translation
        self.understood = understood; self.mood = mood; self.wrongLanguage = wrongLanguage
    }

    public init(_ l: TargetPack.SpokenLine, learner: String, understood: Bool, mood: String, wrongLanguage: Bool = false) {
        self.init(say: l.say, romanization: l.romanization, translation: l.translation(learner),
                  understood: understood, mood: mood, wrongLanguage: wrongLanguage)
    }
}

// MARK: - Brain: the configured AI provider (TomoAI.swift), otherwise built-in replies

public enum TomoBrain {
    /// `transcript` alternates "Tomo: …" / "Learner: …" lines, newest last.
    public static func reply(to transcript: [String], ai: TomoAIConfig?, language: LanguageContext) async -> TomoReply {
        let answer = (transcript.last ?? "").replacingOccurrences(of: "Learner: ", with: "")
        if let gated = languageGate(answer, language: language) { return gated }
        if let ai, ai.isUsable, let r = try? await ask(ai, transcript: transcript, language: language) { return r }
        return offlineReply(to: answer, language: language)
    }

    /// Layer 1 of answer checking (docs/architecture.md): not in the target language, no credit, no AI call.
    /// The AI can be talked into accepting English ("car" once counted), so this rule lives in code.
    public static func languageGate(_ answer: String, language: LanguageContext) -> TomoReply? {
        guard !language.target.looksLikeTarget(answer, learner: language.learner.id) else { return nil }
        return TomoReply(language.target.lines.sayItInMyLanguage, learner: language.learner.id,
                         understood: false, mood: "confused", wrongLanguage: true)
    }

    /// For the AI window's Test button: the pack's first question and first example answer.
    public static func test(config: TomoAIConfig, language: LanguageContext) async -> Result<TomoReply, Error> {
        let starter = language.target.starters.first
        let transcript = ["Tomo: \(starter?.say ?? "")", "Learner: \(starter?.examples.first?.say ?? "")"]
        do { return .success(try await ask(config, transcript: transcript, language: language)) }
        catch { return .failure(error) }
    }

    /// Built from the language pair; the language-specific rules come from the pack.
    public static func systemPrompt(_ l: LanguageContext) -> String {
        let target = l.target.name("en"), learner = l.learner.name
        let romanization = l.target.romanization.map { "the \($0("en")) reading" } ?? "an empty string"
        let age = l.age
        let style: String
        switch age {
        case ...3:  style = "a real 3-year-old: very short (at most about 12 words), simple, cheerful"
        case 4...6: style = "a real \(age)-year-old: short simple sentences (at most about 20 words), curious, sometimes asks why"
        case 7...9: style = "a real \(age)-year-old: one or two short sentences (at most about 25 words), everyday words"
        default:    style = "a real \(age)-year-old: one or two natural sentences (at most about 30 words), words a \(age)-year-old knows"
        }
        let rules = l.target.aiRules(age: age).map { "- " + $0.replacingOccurrences(of: "{age}", with: "\(age)") }
        return """
        You are Tomo, \(l.target.persona(age: age)), who lives in the learner's MacBook notch. \
        The learner is an adult who speaks \(learner) and is learning \(target); \
        you are their friend, not their teacher.
        Rules:
        - Talk like \(style).
        - "say" is in \(target) only. Never use \(learner) in "say".
        \(rules.joined(separator: "\n"))
        - React to what the learner said. You may end with ONE simple follow-up question.
        - If their answer is unclear, not in \(target), or doesn't answer you, don't correct them like a teacher. \
        Be confused the way a kid your age would be, and ask again more simply. Then understood is false.
        - understood is true when their reply is understandable \(target) and fits what you asked. Small mistakes are fine.
        Answer with JSON only:
        {"say": "...", "romanization": "\(romanization)", "translation": "the meaning of say in \(learner)", \
        "understood": true, "mood": "happy|love|surprised|proud|confused"}
        """
    }

    private static func ask(_ ai: TomoAIConfig, transcript: [String], language: LanguageContext) async throws -> TomoReply {
        let user = "Conversation so far:\n" + transcript.joined(separator: "\n") + "\n\nReply as Tomo."
        let text = try await TomoAI.complete(system: systemPrompt(language), user: user, config: ai)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let say = obj["say"] as? String
        else { throw TomoAIError(message: "The model didn't answer in Tomo's JSON format: \(text.prefix(120))") }
        let rom = (obj["romanization"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TomoReply(say: say, romanization: rom,
                         translation: obj["translation"] as? String ?? "",
                         understood: obj["understood"] as? Bool ?? true,
                         mood: obj["mood"] as? String ?? "happy")
    }

    // MARK: Help: explain a line in the learner's language, or say it simpler in the target language

    public static func explain(line: TomoLine, focus: String?, ai: TomoAIConfig?, language l: LanguageContext) async -> TomoExplanation {
        let offline = TomoExplanation(translation: line.translation, parts: [], tip: nil, usedAI: false)
        guard let ai, ai.isUsable else { return offline }
        let target = l.target.name("en"), learner = l.learner.name
        let system = """
        You help an adult who speaks \(learner) understand a line said by Tomo, a \(l.age)-year-old who speaks \(target). \
        Write everything in \(learner), briefly and kindly. Quote phrases from the line exactly as Tomo said them.
        If the learner asks about a specific part, explain only that part (one item in parts). \
        Otherwise pick the 1–3 parts a beginner is most likely to miss.
        Answer with JSON only:
        {"translation": "the whole line in \(learner)", "parts": [{"phrase": "...", "meaning": "..."}], "tip": "one short tip or empty"}
        """
        let user = "Tomo said: \(line.say)\nThe learner asks: \(focus.map { $0.isEmpty ? "(nothing specific)" : $0 } ?? "(nothing specific)")"
        guard let text = try? await TomoAI.complete(system: system, user: user, config: ai),
              let obj = jsonObject(in: text) else { return offline }
        let parts = (obj["parts"] as? [[String: Any]] ?? []).compactMap { p -> TomoExplanation.Part? in
            guard let ph = p["phrase"] as? String, let m = p["meaning"] as? String else { return nil }
            return TomoExplanation.Part(phrase: ph, meaning: m)
        }
        let tip = (obj["tip"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TomoExplanation(translation: obj["translation"] as? String ?? line.translation,
                               parts: parts, tip: tip, usedAI: true)
    }

    public static func simpler(line: TomoLine, ai: TomoAIConfig?, language l: LanguageContext) async -> TomoLine? {
        guard let ai, ai.isUsable else { return nil }
        let target = l.target.name("en"), learner = l.learner.name
        let romanization = l.target.romanization.map { "the \($0("en")) reading" } ?? "an empty string"
        let system = """
        You are Tomo, \(l.target.persona(age: l.age)). The learner didn't understand your last line. \
        Say it again in simpler \(target): shorter, very common words, same meaning, still in character. Never use \(learner) in "say".
        Answer with JSON only: {"say": "...", "romanization": "\(romanization)", "translation": "the meaning in \(learner)"}
        """
        guard let text = try? await TomoAI.complete(system: system, user: "Your last line: \(line.say)", config: ai),
              let obj = jsonObject(in: text), let say = obj["say"] as? String else { return nil }
        let rom = (obj["romanization"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TomoLine(say: say, romanization: rom, translation: obj["translation"] as? String ?? "",
                        examples: line.examples)
    }

    private static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }

    // MARK: Offline replies (placeholder keyword matching from the pack; the Zenbu dictionary replaces it)

    public static func offlineReply(to answer: String, language l: LanguageContext) -> TomoReply {
        let text = answer.lowercased()
        // Pack order matters while matching is substring-based (see docs/research/answer-evaluation.md).
        for rule in l.target.offlineReplies {
            if let word = rule.keys.first(where: { text.contains($0.lowercased()) }) {
                func fill(_ s: String) -> String { s.replacingOccurrences(of: "{w}", with: word) }
                return TomoReply(say: fill(rule.say), romanization: rule.romanization.map(fill),
                                 translation: fill(rule.translation(l.learner.id)), understood: true, mood: rule.mood)
            }
        }
        return TomoReply(l.target.lines.dontUnderstand, learner: l.learner.id, understood: false, mood: "confused")
    }
}

// MARK: - Listening: on-device speech recognition in the target language, push the mic to talk

@MainActor
public final class TomoListener: ObservableObject {
    @Published public private(set) var isListening = false
    @Published public private(set) var problem: String?

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var startedAt = Date()
    private var lastHeard = Date()
    private var watchdog: Timer?
    private var onPartial: ((String) -> Void)?
    private var onDone: ((String) -> Void)?

    public func toggle(onPartial: @escaping (String) -> Void, onDone: @escaping (String) -> Void) {
        if isListening { stop(); return }
        // Spoken answers are off while talking questions are choices, and the Mac app doesn't ask for the
        // microphone then: asking without its usage text in Info.plist would crash. Bring that text (and
        // the audio-input entitlement) back before turning `talkAsChoices` off.
        guard !TomoGame.talkAsChoices else { return }
        self.onPartial = onPartial
        self.onDone = onDone
        Task { await start() }
    }

    private func start() async {
        problem = nil
        let lang = TomoLanguages.shared
        let ui = lang.learner, named = ["language": lang.targetName]
        guard await Self.authorize() else { problem = ui("mic.permission"); return }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang.target.recognitionLocale))
        guard let recognizer, recognizer.isAvailable else { problem = ui("mic.unavailable", named); return }
        // Audio never leaves the Mac: no server fallback.
        guard recognizer.supportsOnDeviceRecognition else { problem = ui("mic.notInstalled", named); return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { problem = ui("mic.none"); return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        request = req
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(req))
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            problem = TomoLanguages.shared.learner("mic.failed")
            return
        }
        transcript = ""
        startedAt = Date()
        lastHeard = Date()
        isListening = true
        task = recognizer.recognitionTask(with: req, resultHandler: Self.resultHandler { [weak self] text in
            self?.heard(text)
        })
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSilence() }
        }
    }

    private func heard(_ text: String) {
        guard isListening, !text.isEmpty, text != transcript else { return }
        transcript = text
        lastHeard = Date()
        onPartial?(text)
    }

    /// Stops after a pause once something was heard, or after 10 seconds.
    private func checkSilence() {
        let now = Date()
        if (!transcript.isEmpty && now.timeIntervalSince(lastHeard) > 1.4) || now.timeIntervalSince(startedAt) > 10 {
            stop()
        }
    }

    public func stop() {
        guard isListening else { return }
        isListening = false
        watchdog?.invalidate(); watchdog = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil; request = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onDone?(text) }
    }

    // Built outside the main actor: these run on audio / recognition threads.
    nonisolated private static func tapBlock(_ req: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let r = req
        return { buffer, _ in r.append(buffer) }
    }

    nonisolated private static func resultHandler(_ deliver: @escaping @MainActor (String) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, _ in
            let text = result?.bestTranscription.formattedString ?? ""
            Task { @MainActor in deliver(text) }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
