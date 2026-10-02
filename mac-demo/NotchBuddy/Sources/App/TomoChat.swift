import AVFoundation
import Foundation
import Speech

// MARK: - 3さい conversation: Tomo asks, you answer in your own words (typed or spoken)

struct TomoLine: Equatable {
    let say: String
    let romaji: String
    let english: String
    var examples: [String] = []   // shown with the hint: things you could answer
}

struct TomoReply: Sendable {
    let say: String
    let romaji: String
    let english: String
    let understood: Bool
    let mood: String              // happy | love | surprised | proud | confused
}

/// Questions Tomo opens a conversation with.
let tomoStarters: [TomoLine] = [
    TomoLine(say: "なに してるの？", romaji: "nani shiteru no?", english: "What are you doing?",
             examples: ["しごと してる (working)", "テレビ みてる (watching TV)", "ごはん たべてる (eating)"]),
    TomoLine(say: "おなか すいた？", romaji: "onaka suita?", english: "Are you hungry?",
             examples: ["うん、すいた (yeah, hungry)", "ううん (nope)"]),
    TomoLine(say: "きょう なに たべた？", romaji: "kyō nani tabeta?", english: "What did you eat today?",
             examples: ["ラーメン (ramen)", "パン たべた (I ate bread)"]),
    TomoLine(say: "すきな どうぶつ なあに？", romaji: "suki na dōbutsu nāni?", english: "What's your favorite animal?",
             examples: ["いぬ (dogs)", "ねこ が すき (I like cats)"]),
    TomoLine(say: "どこ いくの？", romaji: "doko iku no?", english: "Where are you going?",
             examples: ["かいしゃ (the office)", "スーパー (the supermarket)"]),
]

// MARK: - Brain: the configured AI provider (TomoAI.swift), otherwise built-in replies

enum TomoBrain {
    /// `transcript` alternates "Tomo: …" / "Learner: …" lines, newest last.
    static func reply(to transcript: [String], ai: TomoAIConfig?) async -> TomoReply {
        let answer = (transcript.last ?? "").replacingOccurrences(of: "Learner: ", with: "")
        if let gated = languageGate(answer) { return gated }
        if let ai, ai.isUsable, let r = try? await ask(ai, transcript: transcript) { return r }
        return offlineReply(to: answer)
    }

    /// Layer 1 of answer checking (docs/architecture.md): no Japanese, no credit, and no AI call.
    /// The AI can be talked into accepting English ("car" once counted), so this rule lives in code.
    static func languageGate(_ answer: String) -> TomoReply? {
        guard !containsJapanese(answer) else { return nil }
        return TomoReply(say: "ん？ にほんご で いって！", romaji: "n? nihongo de itte!",
                         english: "Hm? Say it in Japanese!", understood: false, mood: "confused")
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    /// For the AI window's Test button.
    static func test(config: TomoAIConfig) async -> Result<TomoReply, Error> {
        do { return .success(try await ask(config, transcript: ["Tomo: なに してるの？", "Learner: しごと してる"])) }
        catch { return .failure(error) }
    }

    private static let system = """
    You are Tomo, a 3-year-old Japanese child who lives in the learner's MacBook notch. \
    The learner is an adult studying Japanese; you are their little friend, not their teacher.
    Rules:
    - Talk like a real Japanese 3-year-old: very short (at most about 12 words), simple, cheerful.
    - Hiragana and katakana only. No kanji, no English, no romaji in "say".
    - Only use words a Japanese 3-year-old knows.
    - React to what the learner said. You may end with ONE simple follow-up question.
    - If their Japanese is unclear, not Japanese, or doesn't answer you, don't correct them like a teacher. \
    Be confused like a child (ん？ わかんない…) and ask again more simply. Then understood is false.
    - understood is true when their reply is understandable and fits what you asked. Small mistakes are fine.
    Answer with JSON only:
    {"say": "...", "romaji": "...", "english": "...", "understood": true, "mood": "happy|love|surprised|proud|confused"}
    """

    private static func ask(_ ai: TomoAIConfig, transcript: [String]) async throws -> TomoReply {
        let user = "Conversation so far:\n" + transcript.joined(separator: "\n") + "\n\nReply as Tomo."
        let text = try await TomoAI.complete(system: system, user: user, config: ai)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let say = obj["say"] as? String
        else { throw TomoAIError(message: "The model didn't answer in Tomo's JSON format: \(text.prefix(120))") }
        return TomoReply(say: say,
                         romaji: obj["romaji"] as? String ?? "",
                         english: obj["english"] as? String ?? "",
                         understood: obj["understood"] as? Bool ?? true,
                         mood: obj["mood"] as? String ?? "happy")
    }

    // MARK: Offline replies (keyword matching, enough for a demo)

    private struct Rule {
        let keys: [String]
        let say: String       // "{w}" is replaced by the word the learner used
        let romaji: String
        let english: String
        let mood: String
    }

    private static let rules: [Rule] = [
        // Order matters while matching is substring-based (see docs/research/answer-evaluation.md):
        // negatives first (いいえ ⊃ いえ, ううん ⊃ うん), animals before foods (パンダ ⊃ パン).
        Rule(keys: ["ううん", "いいえ", "ちがう", "いや"], say: "えー！ そうなの？",
             romaji: "ē! sō na no?", english: "Ehh! Really?", mood: "surprised"),
        Rule(keys: ["しごと", "仕事", "はたら", "働"], say: "おしごと！ えらいね！",
             romaji: "oshigoto! erai ne!", english: "Working! You're so grown-up!", mood: "proud"),
        Rule(keys: ["べんきょう", "勉強", "にほんご", "日本語"], say: "べんきょう！ トモも する！",
             romaji: "benkyō! tomo mo suru!", english: "Studying! Tomo too!", mood: "happy"),
        Rule(keys: ["パソコン", "コンピュータ", "コード", "プログラ"], say: "パソコン！ カタカタ！ すごい！",
             romaji: "pasokon! katakata! sugoi!", english: "Computer! Clickety-clack! Cool!", mood: "surprised"),
        Rule(keys: ["テレビ", "みて", "見て", "アニメ", "えいが", "映画", "ユーチューブ", "youtube"],
             say: "なに みてるの？ トモも みたい！",
             romaji: "nani miteru no? tomo mo mitai!", english: "What are you watching? Tomo wants to watch too!", mood: "love"),
        Rule(keys: ["ゲーム", "あそ", "遊"], say: "あそぶ！ トモも いっしょ！",
             romaji: "asobu! tomo mo issho!", english: "Playing! Tomo wants to join!", mood: "happy"),
        Rule(keys: ["ねむ", "眠", "ねる", "寝"], say: "ねむいね… ねんね しよ…",
             romaji: "nemui ne… nenne shiyo…", english: "Sleepy… let's go night-night…", mood: "love"),
        Rule(keys: ["いぬ", "犬", "ワンワン", "ねこ", "猫", "ニャンニャン", "うさぎ", "パンダ", "ぞう", "ライオン",
                    "きりん", "さる", "くま"],
             say: "{w}！ トモも {w} だいすき！",
             romaji: "{w}! tomo mo {w} daisuki!", english: "{w}! Tomo loves {w} too!", mood: "love"),
        Rule(keys: ["ラーメン", "らーめん", "すし", "寿司", "パン", "ぱん", "ごはん", "ご飯", "おにぎり", "カレー",
                    "りんご", "バナナ", "ばなな", "たまご", "ピザ", "うどん", "そば"],
             say: "{w}！ おいしそう！ トモも たべたい！",
             romaji: "{w}! oishisō! tomo mo tabetai!", english: "{w}! Looks yummy! Tomo wants some!", mood: "love"),
        Rule(keys: ["たべ", "食べ"], say: "なに たべてるの？ おいしい？",
             romaji: "nani tabeteru no? oishii?", english: "What are you eating? Is it yummy?", mood: "happy"),
        Rule(keys: ["がっこう", "学校", "かいしゃ", "会社", "こうえん", "公園", "スーパー", "おみせ", "うち", "いえ", "家"],
             say: "{w}！ いってらっしゃい！",
             romaji: "{w}! itterasshai!", english: "{w}! Have a good time!", mood: "happy"),
        Rule(keys: ["すいた", "ぺこぺこ", "うん", "はい", "そう"], say: "そっか！ えへへ",
             romaji: "sokka! ehehe", english: "I see! Hehe", mood: "happy"),
        Rule(keys: ["なにも", "べつに", "ひま"], say: "ひまなら トモと あそぼ！",
             romaji: "hima nara tomo to asobo!", english: "If you're bored, play with Tomo!", mood: "happy"),
    ]

    static func offlineReply(to line: String) -> TomoReply {
        let text = line.replacingOccurrences(of: "Learner: ", with: "").lowercased()
        for rule in rules {
            if let word = rule.keys.first(where: { text.contains($0.lowercased()) }) {
                func fill(_ s: String) -> String { s.replacingOccurrences(of: "{w}", with: word) }
                return TomoReply(say: fill(rule.say), romaji: fill(rule.romaji), english: fill(rule.english),
                                 understood: true, mood: rule.mood)
            }
        }
        return containsJapanese(text)
            ? TomoReply(say: "ん？ わかんない… もういっかい！", romaji: "n? wakannai… mō ikkai!",
                        english: "Hm? Tomo doesn't get it… say it again!", understood: false, mood: "confused")
            : TomoReply(say: "ん？ にほんご で いって！", romaji: "n? nihongo de itte!",
                        english: "Hm? Say it in Japanese!", understood: false, mood: "confused")
    }
}

// MARK: - Listening: on-device Japanese speech recognition, push the mic to talk

@MainActor
final class TomoListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
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
        guard await Self.authorize() else {
            problem = "Allow Microphone and Speech Recognition for Tomodachi in System Settings → Privacy & Security."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "Japanese speech recognition isn't available on this Mac."
            return
        }
        // Audio never leaves the Mac: no server fallback.
        guard recognizer.supportsOnDeviceRecognition else {
            problem = "On-device Japanese recognition isn't installed. Add Japanese in System Settings → Keyboard → Dictation, or type your answer."
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { problem = "No microphone found."; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        request = req
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(req))
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            problem = "Couldn't start the microphone."
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
