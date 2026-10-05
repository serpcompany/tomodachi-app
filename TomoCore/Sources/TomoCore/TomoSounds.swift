import AVFoundation

// MARK: - Tomo's sound effects
//
// Synthesized in code when first needed (no audio files): chick peeps and chirps for Tomo, soft
// blips for the island. Tomo's peeps drop in pitch a little as it grows up. Effects follow the
// same switch as Tomo's voice (`TomoGame.soundEnabled`). Triggers live in one place,
// `TomoSounds.listen()`: game outcomes, the character notifications, and the island opening.

@MainActor
public final class TomoSounds {
    public static let shared = TomoSounds()

    public enum Effect: String, CaseIterable, Sendable {
        case greet      // "piyo piyo": a visit starts
        case win        // happy rising chirps: Win
        case miss       // soft falling boo-oop: Miss
        case hm         // questioning glide: No score
        case hatch      // pop + rising arpeggio: grew up
        case levelUp    // quick rising chirps and a sparkle: a new level
        case boing      // poked
        case nudge      // "over here!"
        case munch      // eating
        case trill      // love
        case yawn
        case open, close, tick   // island
    }

    public var volume: Float = 0.6

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
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
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
    }

    public func play(_ effect: Effect, force: Bool = false) {
        guard force || TomoGame.shared.soundEnabled else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[effect], now - last < 0.3 { return }   // two triggers for one moment
        lastPlayed[effect] = now
        let buffer = self.buffer(effect, age: min(max(TomoGame.shared.stage - 1, 0), 2))
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
        case .win: play(.win)
        case .loss: play(.miss)
        case .neutral: play(.hm)
        }
    }

    // MARK: - Synthesis

    /// One tone: an exponential pitch sweep with a quick attack and a decaying tail.
    private struct Note {
        public var start: Double
        public var length: Double
        public var from: Double            // Hz
        public var to: Double
        public var gain: Double = 1
        public var vibrato: Double = 0     // depth, as a fraction of the pitch
        public var noise: Double = 0       // breath / crunch
        public var overtone: Double = 0.25 // second harmonic, for a chick-like edge
    }

    private func buffer(_ e: Effect, age: Int) -> AVAudioPCMBuffer {
        let key = "\(e.rawValue)-\(age)"
        if let b = buffers[key] { return b }
        let b = Self.render(Self.notes(e, pitch: [1.0, 0.9, 0.82][age]), format: format)
        buffers[key] = b
        return b
    }

    private static func notes(_ e: Effect, pitch p: Double) -> [Note] {
        switch e {
        case .greet:
            return [Note(start: 0, length: 0.08, from: 2500 * p, to: 3400 * p, vibrato: 0.02),
                    Note(start: 0.12, length: 0.09, from: 2600 * p, to: 3600 * p, vibrato: 0.02)]
        case .win:
            return [Note(start: 0, length: 0.06, from: 2100 * p, to: 2700 * p),
                    Note(start: 0.07, length: 0.06, from: 2500 * p, to: 3200 * p),
                    Note(start: 0.14, length: 0.12, from: 2900 * p, to: 4000 * p, vibrato: 0.02)]
        case .miss:
            return [Note(start: 0, length: 0.12, from: 700, to: 620, gain: 0.7, overtone: 0.1),
                    Note(start: 0.13, length: 0.2, from: 560, to: 460, gain: 0.7, overtone: 0.1)]
        case .hm:
            return [Note(start: 0, length: 0.22, from: 900 * p, to: 1400 * p, gain: 0.7, vibrato: 0.03, overtone: 0.3)]
        case .hatch:
            return [Note(start: 0, length: 0.06, from: 900, to: 220, gain: 0.9, noise: 0.5, overtone: 0),
                    Note(start: 0.08, length: 0.07, from: 1800 * p, to: 2200 * p),
                    Note(start: 0.15, length: 0.07, from: 2300 * p, to: 2800 * p),
                    Note(start: 0.22, length: 0.16, from: 2800 * p, to: 3900 * p, vibrato: 0.03)]
        case .levelUp:
            return [Note(start: 0, length: 0.05, from: 2000 * p, to: 2400 * p),
                    Note(start: 0.07, length: 0.05, from: 2400 * p, to: 2900 * p),
                    Note(start: 0.14, length: 0.05, from: 2900 * p, to: 3500 * p),
                    Note(start: 0.21, length: 0.14, from: 3300 * p, to: 4300 * p, gain: 0.8, vibrato: 0.03)]
        case .boing:
            return [Note(start: 0, length: 0.26, from: 520 * p, to: 250 * p, vibrato: 0.12, overtone: 0.4)]
        case .nudge:
            return [Note(start: 0, length: 0.05, from: 3000 * p, to: 3600 * p),
                    Note(start: 0.08, length: 0.05, from: 3000 * p, to: 3700 * p)]
        case .munch:
            return [Note(start: 0, length: 0.05, from: 320, to: 180, gain: 0.8, noise: 0.35, overtone: 0),
                    Note(start: 0.11, length: 0.05, from: 340, to: 190, gain: 0.8, noise: 0.35, overtone: 0)]
        case .trill:
            return (0..<5).map { i in
                Note(start: Double(i) * 0.05, length: 0.06, from: (i % 2 == 0 ? 2400 : 2800) * p,
                     to: (i % 2 == 0 ? 2600 : 3000) * p, gain: 0.8, vibrato: 0.02)
            }
        case .yawn:
            return [Note(start: 0, length: 0.6, from: 900 * p, to: 420 * p, gain: 0.6, vibrato: 0.01, noise: 0.15, overtone: 0.2)]
        case .open:
            return [Note(start: 0, length: 0.08, from: 660, to: 990, gain: 0.45, overtone: 0.1)]
        case .close:
            return [Note(start: 0, length: 0.08, from: 990, to: 660, gain: 0.45, overtone: 0.1)]
        case .tick:
            return [Note(start: 0, length: 0.03, from: 1800, to: 1700, gain: 0.35, overtone: 0)]
        }
    }

    private static func render(_ notes: [Note], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let total = (notes.map { $0.start + $0.length }.max() ?? 0) + 0.02
        let frames = AVAudioFrameCount(total * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }
        var rng = SystemRandomNumberGenerator()
        for n in notes {
            let first = Int(n.start * rate), count = Int(n.length * rate)
            var phase = 0.0
            for k in 0..<count where first + k < Int(frames) {
                let t = Double(k) / rate, u = t / n.length
                let f = n.from * pow(n.to / n.from, u) * (1 + n.vibrato * sin(2 * .pi * 28 * t))
                phase += 2 * .pi * f / rate
                let env = min(1, t / 0.004) * pow(1 - u, 1.6)
                var s = sin(phase) + n.overtone * sin(2 * phase)
                if n.noise > 0 { s += n.noise * Double.random(in: -1...1, using: &rng) }
                out[first + k] += Float(0.5 * n.gain * env * s)
            }
        }
        var peak: Float = 0
        for i in 0..<Int(frames) { peak = max(peak, abs(out[i])) }
        if peak > 0.95 { for i in 0..<Int(frames) { out[i] *= 0.95 / peak } }   // only guard against clipping; gains set loudness
        return buffer
    }

    // MARK: - Debug

    /// TOMO_RENDER_SOUNDS=<dir>: writes every effect at every age as a WAV, plus all-sounds.wav
    /// (each effect in order with a gap), so they can be listened to without the app.
    public static func renderFiles(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        var all: [Float] = []
        for e in Effect.allCases {
            for age in 0..<3 {
                let b = render(notes(e, pitch: [1.0, 0.9, 0.82][age]), format: format)
                write(b, to: dir.appendingPathComponent("\(e.rawValue)-\(age + 1)sai.wav"), format: format)
                if age == 0 {
                    all += UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))
                    all += [Float](repeating: 0, count: 22_050)
                }
            }
        }
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(all.count))!
        b.frameLength = AVAudioFrameCount(all.count)
        for (i, v) in all.enumerated() { b.floatChannelData![0][i] = v }
        write(b, to: dir.appendingPathComponent("all-sounds.wav"), format: format)
        // Self-test of the playback path, silently.
        shared.volume = 0
        shared.play(.win, force: true)
        print("TomoSounds engine running: \(shared.engine.isRunning)")
    }

    private static func write(_ b: AVAudioPCMBuffer, to url: URL, format: AVAudioFormat) {
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        try? file.write(from: b)
    }
}
