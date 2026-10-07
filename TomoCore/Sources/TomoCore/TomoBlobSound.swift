import Foundation

// MARK: - How a blob sounds: bubbly
//
// Tomo stopped being a chick on 2026-10-07, so it no longer peeps. It sounds bubbly: every moment
// (`TomoSounds.Effect`), lower and fuller as Tomo grows (`SoundAge`). The owner picked it by ear over squishy and toy
// kalimba (decisions.md, 2026-10-08). Pitches are written for 1さい.

enum BlobSound {
    static func voices(_ e: TomoSounds.Effect, _ age: SoundAge) -> [SoundVoice] { bubbly(e, age) }

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
}
