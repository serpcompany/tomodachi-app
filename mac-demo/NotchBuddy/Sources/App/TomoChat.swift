import AVFoundation
import Foundation
import Speech

// MARK: - Talking stage: Tomo asks, you answer in your own words (typed or spoken)

struct TomoLine: Equatable {
    let say: String
    let romanization: String?
    let translation: String       // in the learner's language
    var examples: [String] = []   // shown with the hint: things you could answer

    static let empty = TomoLine(say: "", romanization: nil, translation: "")
}

extension TomoLine {
    init(_ s: TargetPack.Starter, learner: LearnerPack) {
        self.init(say: s.say, romanization: s.romanization, translation: s.translation(learner.id),
                  examples: s.examples.map { "\($0.say) (\($0.translation(learner.id)))" })
    }
}

struct TomoReply: Sendable {
    let say: String
    let romanization: String?
    let translation: String
    let understood: Bool
    let mood: String              // happy | love | surprised | proud | confused

    init(say: String, romanization: String?, translation: String, understood: Bool, mood: String) {
        self.say = say; self.romanization = romanization; self.translation = translation
        self.understood = understood; self.mood = mood
    }

    init(_ l: TargetPack.SpokenLine, learner: String, understood: Bool, mood: String) {
        self.init(say: l.say, romanization: l.romanization, translation: l.translation(learner),
                  understood: understood, mood: mood)
    }
}

// MARK: - Brain: the configured AI provider (TomoAI.swift), otherwise built-in replies

enum TomoBrain {
    /// `transcript` alternates "Tomo: …" / "Learner: …" lines, newest last.
    static func reply(to transcript: [String], ai: TomoAIConfig?, language: LanguageContext) async -> TomoReply {
        let answer = (transcript.last ?? "").replacingOccurrences(of: "Learner: ", with: "")
        if let gated = languageGate(answer, language: language) { return gated }
        if let ai, ai.isUsable, let r = try? await ask(ai, transcript: transcript, language: language) { return r }
        return offlineReply(to: answer, language: language)
    }

    /// Layer 1 of answer checking (docs/architecture.md): not in the target language, no credit, no AI call.
    /// The AI can be talked into accepting English ("car" once counted), so this rule lives in code.
    static func languageGate(_ answer: String, language: LanguageContext) -> TomoReply? {
        guard !language.target.looksLikeTarget(answer, learner: language.learner.id) else { return nil }
        return TomoReply(language.target.lines.sayItInMyLanguage, learner: language.learner.id,
                         understood: false, mood: "confused")
    }

    /// For the AI window's Test button: the pack's first question and first example answer.
    static func test(config: TomoAIConfig, language: LanguageContext) async -> Result<TomoReply, Error> {
        let starter = language.target.starters.first
        let transcript = ["Tomo: \(starter?.say ?? "")", "Learner: \(starter?.examples.first?.say ?? "")"]
        do { return .success(try await ask(config, transcript: transcript, language: language)) }
        catch { return .failure(error) }
    }

    /// Built from the language pair; the language-specific rules come from the pack.
    static func systemPrompt(_ l: LanguageContext) -> String {
        let target = l.target.name("en"), learner = l.learner.name
        let romanization = l.target.romanization.map { "the \($0("en")) reading" } ?? "an empty string"
        return """
        You are Tomo, \(l.target.ai.persona), who lives in the learner's MacBook notch. \
        The learner is an adult who speaks \(learner) and is learning \(target); \
        you are their little friend, not their teacher.
        Rules:
        - Talk like a real 3-year-old: very short (at most about 12 words), simple, cheerful.
        - "say" is in \(target) only. Never use \(learner) in "say".
        \(l.target.ai.rules.map { "- " + $0 }.joined(separator: "\n"))
        - React to what the learner said. You may end with ONE simple follow-up question.
        - If their answer is unclear, not in \(target), or doesn't answer you, don't correct them like a teacher. \
        Be confused like a child and ask again more simply. Then understood is false.
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

    // MARK: Offline replies (placeholder keyword matching from the pack; the Zenbu dictionary replaces it)

    static func offlineReply(to answer: String, language l: LanguageContext) -> TomoReply {
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
final class TomoListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var problem: String?

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

    func toggle(onPartial: @escaping (String) -> Void, onDone: @escaping (String) -> Void) {
        if isListening { stop(); return }
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

    func stop() {
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
