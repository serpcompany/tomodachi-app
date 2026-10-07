import Foundation

// MARK: - The synth behind Tomo's sounds
//
// A sound is a few voices. A voice is a tone gliding through pitch points, with overtones, a soft attack, a
// decaying tail, an optional wobble (pitch) and tremolo (loudness), and a puff of band-passed noise; a lowpass
// keeps it soft. The palettes (TomoSoundPalettes.swift) say which voices each moment gets. Every finished sound
// is set to its moment's loudness (K-weighted, like LUFS), so each palette and each age plays at the same level,
// and its peak stays under -3 dBFS. Noise comes from a seeded generator, so a sound renders the same every time.

/// Tomo's age as sound: light and high at 1さい, lower and fuller by 6さい.
struct SoundAge: Sendable {
    let step: Int   // 0 = 1さい … 5 = 6さい
    /// Pitch, about a fifth lower by 6さい.
    var pitch: Double { [1.0, 0.9, 0.82, 0.76, 0.71, 0.67][step] }
    /// 0 … 1: how much body a palette adds (a lower octave, more overtones, a longer ring).
    var body: Double { Double(step) / 5 }
    /// Tails ring a little longer as Tomo gets bigger.
    var ring: Double { 1 + 0.12 * body }
    static let count = 6
}

struct SoundPartial: Sendable {
    var ratio: Double               // to the voice's pitch (0.5 = an octave below)
    var amp: Double
    var decay = Double.infinity     // its own fall-off (s)
}

struct SoundVoice: Sendable {
    var at: Double                  // start (s)
    var len: Double                 // length (s); the voice fades to silence by then
    var pitch: [(u: Double, hz: Double)]   // points across the voice (0 … 1), glided between in log frequency
    var ease = 1.0                  // > 1: each glide moves fast, then settles (a bubble, a pluck)
    var gain = 1.0
    var partials: [SoundPartial] = []
    var attack = 0.005
    var decay = Double.infinity     // exponential fall-off (s)
    var tail = 1.0                  // the fade to silence at `len`: (1 - u)^tail
    var wobble = 0.0, wobbleRate = 0.0, wobbleDecay = Double.infinity   // pitch vibrato, as a fraction
    var tremolo = 0.0, tremoloRate = 0.0                               // loudness wobble, 0 … 1
    var noise = 0.0, noiseHz = 1000.0, noiseDecay = 0.01               // a band-passed puff at the start
    var noiseFollows = false        // the puff's band glides with the pitch (a squelch)
    var cutoff = 4000.0             // two-pole lowpass (Hz)

    init(at: Double, len: Double, hz: Double, to: Double? = nil, gain: Double = 1) {
        self.at = at; self.len = len; self.gain = gain
        pitch = [(0, hz), (1, to ?? hz)]
    }

    init(at: Double, len: Double, path: [(u: Double, hz: Double)], gain: Double = 1) {
        self.at = at; self.len = len; self.gain = gain
        pitch = path
    }

    /// A copy with some settings changed.
    func with(_ change: (inout SoundVoice) -> Void) -> SoundVoice {
        var v = self
        change(&v)
        return v
    }

    func hz(_ u: Double) -> Double {
        guard let next = pitch.firstIndex(where: { $0.u > u }) else { return pitch.last!.hz }
        guard next > 0 else { return pitch[0].hz }
        let a = pitch[next - 1], b = pitch[next]
        let x = (u - a.u) / (b.u - a.u)
        let g = ease == 1 ? x : 1 - pow(1 - x, ease)
        return a.hz * pow(b.hz / a.hz, g)
    }
}

enum SoundSynth {
    static let rate = 44_100.0
    static let peakLimit = 0.7      // -3.1 dBFS

    /// Mixes the voices and sets the result to `loudness` (max momentary LUFS), capped at the peak limit.
    static func render(_ voices: [SoundVoice], loudness: Double) -> [Float] {
        let total = (voices.map { $0.at + $0.len }.max() ?? 0) + 0.02
        var out = [Double](repeating: 0, count: Int(total * rate))
        for (i, v) in voices.enumerated() { add(v, seed: UInt64(i + 1), into: &out) }
        let level = momentaryMax(out)
        guard level.isFinite else { return out.map { Float($0) } }
        var scale = pow(10, (loudness - level) / 20)
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak * scale > peakLimit { scale = peakLimit / peak }
        return out.map { Float($0 * scale) }
    }

    private static func add(_ v: SoundVoice, seed: UInt64, into out: inout [Double]) {
        let first = Int(v.at * rate), count = Int(v.len * rate)
        var phase = 0.0
        var rng = seed &* 0x9E37_79B9_7F4A_7C15
        var lp1 = 0.0, lp2 = 0.0
        let a = 1 - exp(-2 * .pi * v.cutoff / rate)
        var low = 0.0, band = 0.0            // noise band-pass (state variable)
        let startHz = v.pitch[0].hz
        // Overtones below what a laptop or phone speaker plays only cost loudness: leave them out.
        let lowest = v.pitch.map(\.hz).min() ?? startHz
        let partials = v.partials.filter { $0.amp > 0 && $0.ratio * lowest >= 130 }
        for k in 0..<count where first + k < out.count {
            let t = Double(k) / rate, u = t / v.len
            var f = v.hz(u)
            let glide = f / startHz
            if v.wobble > 0 { f *= 1 + v.wobble * exp(-t / v.wobbleDecay) * sin(2 * .pi * v.wobbleRate * t) }
            phase += 2 * .pi * f / rate
            var s = sin(phase)
            for p in partials { s += p.amp * exp(-t / p.decay) * sin(p.ratio * phase) }
            if v.noise > 0 {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
                let white = Double(rng >> 11) / Double(1 << 53) * 2 - 1
                let center = min(v.noiseHz * (v.noiseFollows ? glide : 1), rate / 7)
                let g = 2 * sin(.pi * center / rate), q = 0.5
                low += g * band
                band += g * (white - low - q * band)
                // unity gain at the centre, then about as loud as a tone of the same amount
                s += v.noise * exp(-t / v.noiseDecay) * band * q * sqrt(rate / (2 * center * q))
            }
            if v.tremolo > 0 { s *= 1 - v.tremolo * (0.5 - 0.5 * cos(2 * .pi * v.tremoloRate * t)) }
            let env = min(1, t / v.attack) * exp(-t / v.decay) * pow(max(0, 1 - u), v.tail)
                * min(1, (v.len - t) / 0.006)
            lp1 += a * (v.gain * env * s - lp1)
            lp2 += a * (lp1 - lp2)
            out[first + k] += lp2
        }
    }

    // MARK: Loudness

    /// The loudest 400 ms (ITU BS.1770 momentary loudness, K-weighted), counting silence around a short sound.
    static func momentaryMax(_ x: [Double]) -> Double {
        let z = biquad(biquad(x, highShelf), highpass)
        var sums = [0.0]
        sums.reserveCapacity(z.count + 1)
        for v in z { sums.append(sums.last! + v * v) }
        let window = Int(0.4 * rate), hop = Int(0.01 * rate)
        var best = 0.0
        var end = hop
        while end < z.count + window {
            let hi = min(end, z.count), lo = max(0, end - window)
            if hi > lo { best = max(best, (sums[hi] - sums[lo]) / Double(window)) }
            end += hop
        }
        return best > 0 ? -0.691 + 10 * log10(best) : -.infinity
    }

    private typealias Coefficients = (b: [Double], a: [Double])

    /// BS.1770's two K-weighting stages, worked out for this sample rate (as pyloudnorm does).
    private static let highShelf: Coefficients = {
        let g = 3.99984385397, q = 0.7071752369554193, fc = 1681.9744509555319
        let A = pow(10, g / 40), w = 2 * .pi * fc / rate, alpha = sin(w) / (2 * q), c = cos(w), r = 2 * sqrt(A) * alpha
        return ([A * ((A + 1) + (A - 1) * c + r), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - r)],
                [(A + 1) - (A - 1) * c + r, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - r])
    }()

    private static let highpass: Coefficients = {
        let q = 0.5003270373253953, fc = 38.13547087613982
        let w = 2 * .pi * fc / rate, alpha = sin(w) / (2 * q), c = cos(w)
        return ([(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + alpha, -2 * c, 1 - alpha])
    }()

    private static func biquad(_ x: [Double], _ k: Coefficients) -> [Double] {
        let b = k.b.map { $0 / k.a[0] }, a = k.a.map { $0 / k.a[0] }
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let v = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }
}
