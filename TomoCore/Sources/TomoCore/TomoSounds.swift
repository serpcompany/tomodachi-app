import AVFoundation

// MARK: - Tomo's sound effects
//
// Synthesized in code when first needed (no audio files; TomoSoundSynth.swift): soft blob sounds for Tomo, which
// get lower and fuller as it grows from 1さい to 6さい, and quiet blips for the island, which don't. While the
// owner picks how a blob sounds, there are three palettes (TomoSoundPalettes.swift); `TOMO_SOUND_PALETTE` picks
// one for a test run. Effects follow the same switch as Tomo's voice (`TomoGame.soundEnabled`). Triggers live in
// one place, `TomoSounds.listen()`: game outcomes, the character notifications, and the island opening.

@MainActor
public final class TomoSounds {
    public static let shared = TomoSounds()

    public enum Effect: String, CaseIterable, Sendable {
        case greet      // a visit starts
        case win        // Win
        case practice   // right, but practice: a smaller win
        case miss       // Miss: soft, never a telling-off
        case hm         // No score: a questioning "hm?"
        case levelUp    // a new level
        case hatch      // a birthday: Tomo evolves (and the first run's egg cracks)
        case boing      // poked
        case dizzy      // poked three times
        case nudge      // "over here!"
        case munch      // eating
        case trill      // love
        case yawn
        case open, close, tick   // island

        /// The island's blips stay the same at every age; they're the island, not Tomo.
        var isIsland: Bool { self == .open || self == .close || self == .tick }

        /// How loud each moment is (max momentary LUFS, before `volume`), the same in every palette: about the
        /// old chirps' levels, with Miss and eating a little louder now that they're lower sounds.
        var loudness: Double {
            switch self {
            case .levelUp: -14.5
            case .hatch, .win: -15
            case .greet: -16
            case .practice, .trill: -17
            case .dizzy: -17.5
            case .miss, .nudge, .boing: -18.5
            case .hm, .yawn: -19
            case .munch: -20
            case .open, .close: -28
            case .tick: -32
            }
        }
    }

    public var volume: Float = 0.6

    private let engine = AVAudioEngine()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.rate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Effect: Double] = [:]
    private var idleStop: DispatchWorkItem?
    private var lastGrowth: CGFloat = 0
    private var listening = false

    private init() {
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: Self.format)
            players.append(p)
        }
    }

    public func play(_ effect: Effect, force: Bool = false) {
        guard force || TomoGame.shared.soundEnabled else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[effect], now - last < 0.3 { return }   // two triggers for one moment
        lastPlayed[effect] = now
        let buffer = self.buffer(effect, age: min(max(TomoGame.shared.stage - 1, 0), SoundAge.count - 1))
        engine.mainMixerNode.outputVolume = volume
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [])
        p.play()
        // Let the audio hardware sleep when Tomo is quiet.
        idleStop?.cancel()
        let stop = DispatchWorkItem { [weak self] in self?.engine.pause() }
        idleStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: stop)
    }

    /// Wires the effects to the moments they belong to. Called once at launch.
    public func listen() {
        guard !listening else { return }
        listening = true
        let nc = NotificationCenter.default
        // Observers hand over only Sendable values (the effect, a growth step) to the main actor.
        func on(_ name: Notification.Name, _ effect: @escaping @Sendable (Notification) -> Effect?) {
            nc.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let e = effect(n) else { return }
                MainActor.assumeIsolated { TomoSounds.shared.play(e) }
            }
        }
        on(.botGreet) { _ in .greet }
        on(.botNudge) { _ in .nudge }
        on(.triggerSlap) { _ in .boing }
        on(.botGulp) { _ in .munch }
        on(.botLevelUp) { _ in .levelUp }
        on(.triggerEmote) { n in
            switch n.object as? BotEmote {
            case .love: return .trill
            case .yawn: return .yawn
            default: return nil
            }
        }
        nc.addObserver(forName: .botDizzy, object: nil, queue: .main) { _ in   // after the third poke's own sound
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated { TomoSounds.shared.play(.dizzy) }
            }
        }
        nc.addObserver(forName: .botGrow, object: nil, queue: .main) { n in
            guard let g = n.object as? CGFloat else { return }
            MainActor.assumeIsolated { TomoSounds.shared.grew(to: g) }
        }
        nc.addObserver(forName: .botSetGrowth, object: nil, queue: .main) { n in   // no fanfare
            guard let g = n.object as? CGFloat else { return }
            MainActor.assumeIsolated { TomoSounds.shared.lastGrowth = g }
        }
    }

    private func grew(to g: CGFloat) {
        if g > lastGrowth { play(.hatch) }
        lastGrowth = g
    }

    /// Every answer's result has a sound, like it has a badge.
    public func outcome(_ o: TomoOutcome) {
        switch o {
        case .win(let counted): play(counted ? .win : .practice)
        case .loss: play(.miss)
        case .neutral: play(.hm)
        }
    }

    // MARK: - Synthesis

    private func buffer(_ e: Effect, age: Int) -> AVAudioPCMBuffer {
        let key = "\(e.rawValue)-\(age)"
        if let b = buffers[key] { return b }
        let b = Self.pcm(Self.render(e, SoundAge(step: age)))
        buffers[key] = b
        return b
    }

    private static func render(_ e: Effect, _ age: SoundAge) -> [Float] {
        SoundSynth.render(SoundPalette.chosen.voices(e, e.isIsland ? SoundAge(step: 0) : age), loudness: e.loudness)
    }

    private static func pcm(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = AVAudioFrameCount(samples.count)
        for (i, v) in samples.enumerated() { b.floatChannelData![0][i] = v }
        return b
    }

    // MARK: - Debug

    /// TOMO_RENDER_SOUNDS=<dir>: writes every effect at every age (`win-age1.wav` … `win-age6.wav`) in the palette
    /// `TOMO_SOUND_PALETTE` picks, plus all-sounds.wav (each effect at 1さい, in order, with a gap), so they can be
    /// listened to without the app.
    public static func renderFiles(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var all: [Float] = []
        for e in Effect.allCases {
            for step in 0..<SoundAge.count {
                let samples = render(e, SoundAge(step: step))
                write(pcm(samples), to: dir.appendingPathComponent("\(e.rawValue)-age\(step + 1).wav"))
                if step == 0 { all += samples + [Float](repeating: 0, count: 22_050) }
            }
        }
        write(pcm(all), to: dir.appendingPathComponent("all-sounds.wav"))
        print("TomoSounds palette: \(SoundPalette.chosen.rawValue)")
        // Self-test of the playback path, silently.
        shared.volume = 0
        shared.play(.win, force: true)
        print("TomoSounds engine running: \(shared.engine.isRunning)")
    }

    /// For the self-test (TOMO_SELFTEST): every palette has a short, soft sound for every moment, lower for an older
    /// Tomo, and as loud as the other palettes'.
    public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        func list(_ names: [String]) -> String { names.isEmpty ? "" : ": " + names.joined(separator: ", ") }
        var missing: [String] = [], loud: [String] = [], long: [String] = [], higher: [String] = []
        var levels: [String: [Double]] = [:]
        for p in SoundPalette.allCases {
            for e in Effect.allCases {
                for step in [0, SoundAge.count - 1] {
                    let s = SoundSynth.render(p.voices(e, SoundAge(step: step)), loudness: e.loudness)
                    let peak = Double(s.reduce(0) { max($0, abs($1)) })
                    let name = "\(p.rawValue) \(e.rawValue) age \(step + 1)"
                    if peak == 0 { missing.append(name) }
                    if peak > SoundSynth.peakLimit + 0.001 { loud.append(name) }
                    if Double(s.count) / SoundSynth.rate > (e == .levelUp || e == .hatch ? 1.5 : 0.6) { long.append(name) }
                    levels["\(e.rawValue) \(step)", default: []].append(SoundSynth.momentaryMax(s.map(Double.init)))
                }
                let pitch = { (step: Int) in p.voices(e, SoundAge(step: step)).map { $0.pitch[0].hz }.min() ?? 0 }
                if !e.isIsland && pitch(SoundAge.count - 1) >= pitch(0) { higher.append("\(p.rawValue) \(e.rawValue)") }
            }
        }
        check(missing.isEmpty, "every palette has a sound for every moment\(list(missing))")
        check(loud.isEmpty, "no sound peaks above -3 dBFS\(list(loud))")
        check(long.isEmpty, "sounds are short: a level-up or birthday 1.5 s, the rest 0.6 s\(list(long))")
        check(higher.isEmpty, "Tomo's sounds are lower at 6 than at 1\(list(higher))")
        let spread = levels.values.map { ($0.max() ?? 0) - ($0.min() ?? 0) }.max() ?? 0
        check(spread <= 1.5, "each moment is about as loud in every palette (within \(String(format: "%.1f", spread)) dB)")
        return ok
    }

    private static func write(_ b: AVAudioPCMBuffer, to url: URL) {
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        try? file.write(from: b)
    }
}
