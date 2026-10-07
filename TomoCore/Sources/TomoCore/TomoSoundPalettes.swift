import Foundation

// MARK: - How a blob sounds: three palettes to pick from
//
// Tomo stopped being a chick on 2026-10-07, so it no longer peeps. These are three candidate sound sets for the
// blob, each covering every moment (`TomoSounds.Effect`) and lower and fuller as Tomo grows (`SoundAge`). The
// owner picks one by ear; the other two are then deleted. A test run picks one with
// `TOMO_SOUND_PALETTE=bubbly|squishy|kalimba` (the default is below). Pitches are written for 1さい.

enum SoundPalette: String, CaseIterable, Sendable {
    case bubbly, squishy, kalimba

    static let chosen = ProcessInfo.processInfo.environment["TOMO_SOUND_PALETTE"]
        .flatMap(SoundPalette.init(rawValue:)) ?? .bubbly

    func voices(_ e: TomoSounds.Effect, _ age: SoundAge) -> [SoundVoice] {
        switch self {
        case .bubbly: Self.bubbly(e, age)
        case .squishy: Self.squishy(e, age)
        case .kalimba: Self.kalimba(e, age)
        }
    }

    // MARK: Bubbly

    /// Water-drop bloops and bubble pops: a rising bubble arpeggio for a level-up, a big bloomp and a fizz of
    /// bubbles for a birthday, a gurgle for dizzy. A bigger Tomo blows bigger, slower bubbles.
    private static func bubbly(_ e: TomoSounds.Effect, _ a: SoundAge) -> [SoundVoice] {
        let body = [SoundPartial(ratio: 2, amp: 0.06), SoundPartial(ratio: 0.5, amp: 0.3 * a.body)]
        // A drop: a round tone that jumps up in pitch as it starts, like a bubble reaching the surface.
        func bloop(_ at: Double, _ hz: Double, _ len: Double, rise: Double = 1.8, gain: Double = 1) -> SoundVoice {
            SoundVoice(at: at, len: len * a.ring, hz: hz * a.pitch, to: hz * a.pitch * rise, gain: gain).with {
                $0.ease = 3; $0.attack = 0.003; $0.decay = len * 0.5 * a.ring; $0.tail = 1.2
                $0.partials = body; $0.cutoff = 3200
            }
        }
        // A slower bubble that glides through the given pitches.
        func glub(_ at: Double, _ len: Double, _ path: [(Double, Double)], gain: Double = 1) -> SoundVoice {
            SoundVoice(at: at, len: len * a.ring, path: path.map { (u: $0.0, hz: $0.1 * a.pitch) }, gain: gain).with {
                $0.ease = 1.6; $0.attack = 0.006; $0.decay = len * 0.8 * a.ring
                $0.partials = body; $0.cutoff = 2400
            }
        }
        // Tiny bubbles fizzing up, quietly: the sparkle.
        func fizz(_ at: Double, _ n: Int, every: Double = 0.05, from hz: Double = 800) -> [SoundVoice] {
            let steps = [1.0, 1.22, 1.1, 1.36, 1.18, 1.5, 1.28, 1.6]
            return (0..<n).map { bloop(at + Double($0) * every, hz * steps[$0 % steps.count], 0.06, rise: 1.3, gain: 0.25) }
        }
        switch e {
        case .greet:
            return [bloop(0, 420, 0.14), bloop(0.13, 560, 0.18, rise: 1.9)]
        case .win:
            return [bloop(0, 392, 0.1, rise: 1.7), bloop(0.08, 494, 0.1, rise: 1.7), bloop(0.16, 588, 0.2, rise: 1.9)]
                + fizz(0.24, 3)
        case .practice:   // the win's first two bubbles, a little softer
            return [bloop(0, 392, 0.1, rise: 1.7, gain: 0.85), bloop(0.08, 494, 0.18, rise: 1.7, gain: 0.85)]
        case .miss:       // two round blubs, going down
            return [bloop(0, 330, 0.14, rise: 1.35).with { $0.cutoff = 1800 },
                    bloop(0.15, 247, 0.24, rise: 1.2, gain: 0.9).with { $0.cutoff = 1600 }]
        case .hm:         // a slow bubble that dips and rises, then a little "?" pop
            return [glub(0, 0.26, [(0, 360), (0.35, 330), (1, 560)]), bloop(0.27, 520, 0.07, rise: 1.5, gain: 0.6)]
        case .levelUp:    // a rising bubble arpeggio, a big top bubble, a fizz
            let notes = [392.0, 440, 494, 588, 660, 784]
            return notes.enumerated().map { i, hz in bloop(Double(i) * 0.065, hz, 0.12, rise: 1.6, gain: 0.75 + 0.05 * Double(i)) }
                + [bloop(0.42, 660, 0.26, rise: 1.9)] + fizz(0.5, 5, every: 0.055)
        case .hatch:      // a big bloomp, a stream of bubbles rising, a bubbly chord and a fizz
            let big = bloop(0, 200, 0.32, rise: 2).with { $0.noise = 0.25; $0.noiseHz = 600; $0.noiseDecay = 0.02 }
            let stream = (0..<8).map { i in
                bloop(0.24 + Double(i) * 0.05, 330 * pow(3, Double(i) / 7), 0.1, rise: 1.5, gain: 0.6 + 0.05 * Double(i))
            }
            return [big] + stream
                + [bloop(0.68, 523, 0.34, rise: 1.6, gain: 0.8), bloop(0.72, 660, 0.32, rise: 1.6, gain: 0.55),
                   bloop(0.76, 784, 0.3, rise: 1.6, gain: 0.4)]
                + fizz(0.8, 6, every: 0.06)
        case .boing:      // pressed like a water balloon: squeezed down, then springing back
            return [glub(0, 0.17, [(0, 520), (0.25, 300), (1, 420)]).with {
                $0.ease = 2; $0.noise = 0.15; $0.noiseHz = 1200; $0.noiseDecay = 0.01
            }]
        case .dizzy:      // a gurgle going round and round, winding down
            let notes = [520.0, 390, 490, 370, 460, 350]
            return notes.enumerated().map { i, hz in bloop(Double(i) * 0.07, hz, 0.11, rise: 1.5, gain: 1 - 0.06 * Double(i)) }
        case .nudge:
            return [bloop(0, 520, 0.1, rise: 1.6, gain: 0.9), bloop(0.11, 520, 0.12, rise: 1.7)]
        case .munch:      // glup, glup
            let gulp = { (at: Double) in
                glub(at, 0.11, [(0, 260), (0.4, 190), (1, 300)]).with {
                    $0.ease = 2; $0.noise = 0.2; $0.noiseHz = 600; $0.noiseDecay = 0.02
                }
            }
            return [gulp(0), gulp(0.15)]
        case .trill:      // giggly little bubbles, then a sweet one
            let notes = [494.0, 588, 523, 660, 588]
            return notes.enumerated().map { i, hz in bloop(Double(i) * 0.055, hz, 0.08, rise: 1.5, gain: 0.7) }
                + [bloop(0.3, 784, 0.15, rise: 1.6)]
        case .yawn:       // a slow, breathy bubble up and down, and a sleepy blub
            return [glub(0, 0.42, [(0, 300), (0.35, 400), (1, 200)]).with {
                        $0.wobble = 0.012; $0.wobbleRate = 5; $0.cutoff = 1600
                        $0.noise = 0.25; $0.noiseHz = 700; $0.noiseDecay = 0.3
                    },
                    bloop(0.43, 240, 0.08, rise: 1.5, gain: 0.5)]
        case .open:
            return [bloop(0, 520, 0.08, rise: 1.5)]
        case .close:
            return [glub(0, 0.08, [(0, 700), (1, 470)]).with { $0.ease = 3 }]
        case .tick:
            return [bloop(0, 880, 0.035, rise: 1.25)]
        }
    }

    // MARK: Squishy

    /// Soft rubbery boings and a jelly wobble: a squish for a poke, a squeeze and a bouncy boing-pop for a
    /// birthday. A bigger Tomo is a heavier jelly: lower, rounder, wobbling slower.
    private static func squishy(_ e: TomoSounds.Effect, _ a: SoundAge) -> [SoundVoice] {
        // A rubbery tone that bends through `path` with a springy wobble that dies away.
        func boing(_ at: Double, _ len: Double, _ path: [(Double, Double)], wobble: Double = 0.05, rate: Double = 14,
                   gain: Double = 1) -> SoundVoice {
            SoundVoice(at: at, len: len * a.ring, path: path.map { (u: $0.0, hz: $0.1 * a.pitch) }, gain: gain).with {
                $0.ease = 2; $0.attack = 0.008; $0.decay = len * 0.7 * a.ring
                $0.partials = [SoundPartial(ratio: 2, amp: 0.25 + 0.15 * a.body, decay: len * 0.6),
                               SoundPartial(ratio: 3, amp: 0.08 + 0.07 * a.body, decay: len * 0.4),
                               SoundPartial(ratio: 0.5, amp: 0.2 * a.body)]
                $0.wobble = wobble; $0.wobbleRate = rate * (1 - 0.25 * a.body); $0.wobbleDecay = len * 0.6
                $0.cutoff = 1800
            }
        }
        // A short boing that springs up into its note.
        func bounce(_ at: Double, _ hz: Double, _ len: Double, gain: Double = 1) -> SoundVoice {
            boing(at, len, [(0, hz * 0.82), (0.35, hz * 1.04), (1, hz)], wobble: 0.04, rate: 16, gain: gain)
        }
        // Squeezed jelly: a low tone bending down under a soft band of noise that bends with it.
        func squish(_ at: Double, _ len: Double, _ hz: Double, gain: Double = 1) -> SoundVoice {
            boing(at, len, [(0, hz), (1, hz * 0.7)], wobble: 0.04, rate: 20, gain: gain).with {
                $0.noise = 0.3; $0.noiseHz = hz * a.pitch * 3; $0.noiseFollows = true; $0.noiseDecay = len * 0.5
                $0.cutoff = 1500
            }
        }
        switch e {
        case .greet:
            return [bounce(0, 330, 0.14), bounce(0.14, 440, 0.2)]
        case .win:        // bouncing up, the last one springy
            return [bounce(0, 330, 0.11), bounce(0.1, 415, 0.11),
                    boing(0.2, 0.28, [(0, 400), (0.3, 520), (1, 495)], wobble: 0.08, rate: 12)]
        case .practice:   // the win's first two bounces, a little softer
            return [bounce(0, 330, 0.11, gain: 0.85), bounce(0.1, 415, 0.18, gain: 0.85)]
        case .miss:       // a gentle droop that settles, like jelly sitting back down
            return [boing(0, 0.32, [(0, 320), (0.5, 250), (1, 240)], wobble: 0.04, rate: 10).with {
                $0.wobbleDecay = 0.1; $0.cutoff = 1100
            }]
        case .hm:         // "mm?"
            return [boing(0, 0.3, [(0, 290), (0.45, 270), (1, 400)], wobble: 0.03, rate: 10)]
        case .levelUp:    // bouncing up the steps, then a big springy boing and two little bips
            let steps = [330.0, 392, 494, 587].enumerated().map { i, hz in bounce(Double(i) * 0.085, hz, 0.1) }
            return steps + [boing(0.36, 0.5, [(0, 500), (0.25, 700), (1, 660)], wobble: 0.1, rate: 13),
                            bounce(0.6, 990, 0.07, gain: 0.3), bounce(0.7, 1175, 0.08, gain: 0.3)]
        case .hatch:      // squeeze… boing, pop! and two happy bounces
            let pop = SoundVoice(at: 0.74, len: 0.05, hz: 900 * a.pitch, to: 600 * a.pitch, gain: 0.7).with {
                $0.noise = 0.4; $0.noiseHz = 2000; $0.noiseDecay = 0.008; $0.cutoff = 2500
            }
            return [squish(0, 0.24, 240),
                    boing(0.2, 0.55, [(0, 200), (0.3, 420), (1, 400)], wobble: 0.12, rate: 11),
                    pop, bounce(0.82, 523, 0.14), bounce(0.94, 659, 0.26)]
        case .boing:      // a squish
            return [squish(0, 0.2, 320)]
        case .dizzy:      // a jelly wobble
            return [boing(0, 0.5, [(0, 360), (1, 290)], wobble: 0.09, rate: 7).with {
                $0.wobbleDecay = .infinity; $0.tremolo = 0.35; $0.tremoloRate = $0.wobbleRate
            }]
        case .nudge:
            return [bounce(0, 440, 0.08), bounce(0.11, 440, 0.09)]
        case .munch:      // nom, nom
            return [squish(0, 0.1, 210), squish(0.15, 0.1, 200)]
        case .trill:      // a warm "mmm-wah" and a little bounce
            return [boing(0, 0.38, [(0, 300), (1, 470)], wobble: 0.04, rate: 8).with { $0.ease = 1.5 },
                    bounce(0.34, 588, 0.12, gain: 0.6)]
        case .yawn:
            return [boing(0, 0.48, [(0, 250), (0.3, 350), (1, 180)], wobble: 0.02, rate: 5).with {
                $0.cutoff = 1000; $0.noise = 0.2; $0.noiseHz = 600; $0.noiseDecay = 0.3
            }]
        case .open:
            return [bounce(0, 400, 0.08)]
        case .close:
            return [boing(0, 0.08, [(0, 520), (1, 380)], wobble: 0)]
        case .tick:
            return [boing(0, 0.035, [(0, 600), (1, 560)], wobble: 0)]
        }
    }

    // MARK: Toy kalimba

    /// Soft plucked, toy-like tones (a kalimba with a music box's sparkle): a little chord for a Win, a gentle low
    /// pluck for a Miss, a rolled chord for a birthday. A bigger Tomo is a bigger kalimba: lower, ringing longer.
    private static func kalimba(_ e: TomoSounds.Effect, _ a: SoundAge) -> [SoundVoice] {
        let C4 = 261.63, G4 = 392.0, A4 = 440.0, C5 = 523.25, D5 = 587.33, E5 = 659.26, G5 = 783.99, A5 = 880.0
        let C6 = 1046.5, E6 = 1318.51, G6 = 1567.98
        // A tine: a quick pitch settle, a bright "tink" that's gone in a moment, a warm ring.
        func pluck(_ at: Double, _ hz: Double, ring: Double = 0.3, gain: Double = 1, muted: Bool = false,
                   bend: Double = 1) -> SoundVoice {
            let f = hz * a.pitch, len = ring * a.ring
            return SoundVoice(at: at, len: len, path: [(0, f * 1.006), (0.08, f), (0.5, f * bend), (1, f * bend)],
                              gain: gain).with {
                $0.ease = 2; $0.attack = 0.002; $0.decay = len * 0.4; $0.tail = 0.7
                $0.partials = [SoundPartial(ratio: 2, amp: 0.1 + 0.08 * a.body, decay: len * 0.25),
                               SoundPartial(ratio: 5.9, amp: muted ? 0.04 : 0.2, decay: 0.012),
                               SoundPartial(ratio: 0.5, amp: f > 300 ? 0.22 * a.body : 0, decay: len * 0.35)]
                $0.noise = muted ? 0.3 : 0.12; $0.noiseHz = muted ? 800 : 2400; $0.noiseDecay = muted ? 0.01 : 0.004
                $0.cutoff = muted ? 1500 : 4200
            }
        }
        func run(_ notes: [Double], every: Double, ring: Double, from at: Double = 0, gain: Double = 1) -> [SoundVoice] {
            notes.enumerated().map { i, hz in pluck(at + Double(i) * every, hz, ring: ring, gain: gain) }
        }
        switch e {
        case .greet:      // "hel-lo!" up a fourth
            return [pluck(0, G5, ring: 0.25), pluck(0.11, C6)]
        case .win:        // a little major chord, rolled up
            return [pluck(0, C5, ring: 0.25, gain: 0.8), pluck(0.06, E5, ring: 0.25, gain: 0.85),
                    pluck(0.12, G5, ring: 0.28, gain: 0.9), pluck(0.18, C6, gain: 0.85)]
        case .practice:   // two notes of it, softer
            return [pluck(0, E5, ring: 0.25, gain: 0.85), pluck(0.08, G5, gain: 0.85)]
        case .miss:       // a gentle low pluck, muted, after a quiet one above
            return [pluck(0, D5, ring: 0.16, gain: 0.45, muted: true), pluck(0.08, G4, ring: 0.4, muted: true, bend: 0.985)]
        case .hm:         // the second note bends up, like a question
            return [pluck(0, D5, ring: 0.18, gain: 0.8), pluck(0.12, E5, ring: 0.32, bend: 1.07)]
        case .levelUp:    // a run up the scale to a ringing top, and a music-box sparkle
            return run([C5, D5, E5, G5, A5], every: 0.06, ring: 0.22, gain: 0.8)
                + [pluck(0.32, C6, ring: 0.6), pluck(0.33, E6, ring: 0.55, gain: 0.55),
                   pluck(0.5, G6, ring: 0.25, gain: 0.3), pluck(0.6, E6, ring: 0.25, gain: 0.25)]
        case .hatch:      // a run up, then a big chord rolled from the bottom, and sparkles
            let chord = [C4, G4, C5, E5, G5].enumerated().map { i, hz in
                pluck(0.26 + Double(i) * 0.04, hz, ring: 1 - 0.03 * Double(i), gain: 0.9 - 0.08 * Double(i))
            }
            return run([C5, E5, G5, C6], every: 0.05, ring: 0.2, gain: 0.7) + chord
                + [pluck(0.6, E6, ring: 0.25, gain: 0.25), pluck(0.7, G6, ring: 0.25, gain: 0.25),
                   pluck(0.8, E6, ring: 0.25, gain: 0.2)]
        case .boing:      // a pressed tine: "boink"
            return [pluck(0, A5, ring: 0.26, bend: 0.82)]
        case .dizzy:      // a wavy music-box run, winding down
            return [G5, E5, A5, D5, G5, C5].enumerated().map { i, hz in
                pluck(Double(i) * 0.065, hz, ring: 0.2, gain: 1 - 0.06 * Double(i)).with {
                    $0.wobble = 0.012; $0.wobbleRate = 9
                }
            }
        case .nudge:
            return [pluck(0, C6, ring: 0.15, gain: 0.85), pluck(0.1, C6, ring: 0.18)]
        case .munch:      // tup, tup
            return [pluck(0, C5, ring: 0.1, muted: true), pluck(0.14, A4, ring: 0.1, muted: true)]
        case .trill:      // a fluttery trill that lands up high
            return run([E5, G5, E5, G5], every: 0.05, ring: 0.18, gain: 0.7) + [pluck(0.2, C6)]
        case .yawn:       // three slow notes down, the last one sagging
            return [pluck(0, G5, ring: 0.3, gain: 0.7), pluck(0.14, E5, ring: 0.3, gain: 0.75),
                    pluck(0.28, C5, ring: 0.24, bend: 0.94)]
        case .open:
            return [pluck(0, G5, ring: 0.07, gain: 0.7), pluck(0.035, C6, ring: 0.08)]
        case .close:
            return [pluck(0, C6, ring: 0.07, gain: 0.7), pluck(0.035, G5, ring: 0.08)]
        case .tick:
            return [pluck(0, C6, ring: 0.04, muted: true)]
        }
    }
}
