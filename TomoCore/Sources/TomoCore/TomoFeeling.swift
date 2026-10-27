import SwiftUI

// MARK: - How Tomo feels (#257)
//
// A look Tomo can show over its own: droopy or sickly, as the states lab drew them (docs/reference/tomo/states-lab.html:
// Droopy is its Posture option, Sickly its Ill). The host passes it to TomoBlob (`feeling`); for now only the Testing
// menu sets it (`TomoGame.feeling`). Nothing in the game reads or sets it: no level, age or mood rule (#262).
//
// Each feeling is a set of amounts Tomo eases toward, about 90% of the way in a second, so it slumps or perks up rather
// than snapping. Its colours are a pass over the look (`TomoLook.tinted`), so the seed, the shape and `classic` never
// change. The sweat drop is a fixed fill worked out from the clock, so nothing emits at rest.

/// A look over Tomo's own; nil is well.
public enum TomoFeeling: String, CaseIterable, Sendable {
    /// Slumped lower and wider, ears or topper flopped, looking at the floor; it breathes slower and sighs.
    case droopy
    /// A green-grey tint, a size smaller, a sweat drop, quick shallow breaths, heavy worried lids, a shiver now and then.
    case sickly
}

extension TomoFeeling {
    /// How much of each part of a feeling is on show. `well` changes nothing.
    struct Amounts: Equatable {
        var sag: CGFloat = 0           // the body's lower part spread out (`sagged`), 0…1
        var flop: CGFloat = 0          // ears and toppers flopped down, 0…1
        var wide: CGFloat = 1, tall: CGFloat = 1, size: CGFloat = 1
        var gaze: CGFloat = 0          // how far its gaze has dropped to the floor (`floor`), 0…1
        var breathRate: CGFloat = 1, breathDepth: CGFloat = 1
        var sat: CGFloat = 1           // how much of its colour's chroma it keeps
        var green: CGFloat = 0         // how far it has turned a sickly green-grey, 0…1
        var sweat: CGFloat = 0         // the sweat drop's opacity
        var lid: CGFloat = 0           // the upper lids, this far down the eye
        var worry: CGFloat = 0         // the lids tipped down at their outer corners

        static let well = Amounts()

        /// The lab's numbers for each feeling.
        init(_ feeling: TomoFeeling?) {
            switch feeling {
            case nil: break
            case .droopy:
                sag = 0.85; flop = 1; wide = 1.05; tall = 0.94; gaze = 0.7; breathRate = 0.75
            case .sickly:
                green = 0.75; sat = 0.6; size = 0.92; sweat = 1; breathRate = 1.9; breathDepth = 0.55
                lid = 0.45; worry = 0.35
            }
        }

        init() {}

        private static var parts: [WritableKeyPath<Amounts, CGFloat>] {
            [\.sag, \.flop, \.wide, \.tall, \.size, \.gaze, \.breathRate, \.breathDepth, \.sat, \.green, \.sweat, \.lid, \.worry]
        }

        /// Part of the way to `goal` after `dt` seconds (90% in one), and there once every part is within 0.002 of it.
        mutating func ease(toward goal: Amounts, dt: CGFloat) {
            let k = 1 - pow(0.1, dt)
            var near = true
            for part in Self.parts {
                self[keyPath: part] += (goal[keyPath: part] - self[keyPath: part]) * k
                if abs(goal[keyPath: part] - self[keyPath: part]) > 0.002 { near = false }
            }
            if near { self = goal }
        }

        /// The colour pass, in 40ths: a look is repainted only when this changes (`TomoLook.tinted`).
        var tint: (sat: Int, green: Int) { (Int((sat * 40).rounded()), Int((green * 40).rounded())) }
    }

    /// Where a droopy Tomo looks: down at the floor in front of it (gaze units: x right, y up).
    static let floor = CGPoint(x: 0, y: -0.7)

    /// From hue `a` toward `b` by `t` (degrees), the short way round.
    static func hue(_ a: Double, toward b: Double, by t: Double) -> Double {
        func wrap(_ x: Double) -> Double { let r = x.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
        let d = wrap(b - a + 180) - 180
        return wrap(a + d * t)
    }

    /// The body's outline (`path`, from `top` to `bottom` in its own y) slumped: each point pushed out sideways by up to
    /// 16% × `sag` at the base, with the square of how far down it is, so the top stays put and the bottom spreads.
    /// Straight edges are split first, so a polygon's sides bow out as a round body's do.
    static func sagged(_ path: Path, top: CGFloat, bottom: CGFloat, by sag: CGFloat) -> Path {
        let span = max(bottom - top, 1e-6), steps = 6
        func warp(_ p: CGPoint) -> CGPoint {
            let v = min(1, max(0, (p.y - top) / span))
            return CGPoint(x: p.x * (1 + 0.16 * sag * v * v), y: p.y)
        }
        var out = Path(), last = CGPoint.zero, first = CGPoint.zero
        func line(to p: CGPoint) {
            for i in 1...steps {
                let u = CGFloat(i) / CGFloat(steps)
                out.addLine(to: warp(CGPoint(x: last.x + (p.x - last.x) * u, y: last.y + (p.y - last.y) * u)))
            }
            last = p
        }
        path.forEach { e in
            switch e {
            case .move(let p): out.move(to: warp(p)); last = p; first = p
            case .line(let p): line(to: p)
            case .quadCurve(let p, let c): out.addQuadCurve(to: warp(p), control: warp(c)); last = p
            case .curve(let p, let c1, let c2): out.addCurve(to: warp(p), control1: warp(c1), control2: warp(c2)); last = p
            case .closeSubpath:
                if last != first { line(to: first) }
                out.closeSubpath()
                last = first
            }
        }
        return out
    }

    /// What shows of an eye (`rw` × `rh`, centred on the origin) under an upper lid `lid` of the way down (0: none), tipped
    /// `tilt` lower at its outer corner (`side`: -1 the left eye, 1 the right).
    static func underLid(rw: CGFloat, rh: CGFloat, lid: CGFloat, tilt: CGFloat, side: CGFloat) -> Path {
        let y = -rh + 2 * rh * lid
        var p = Path()
        p.move(to: CGPoint(x: -2 * rw, y: y - side * tilt))
        p.addLine(to: CGPoint(x: 2 * rw, y: y + side * tilt))
        p.addLine(to: CGPoint(x: 2 * rw, y: 2 * rh))
        p.addLine(to: CGPoint(x: -2 * rw, y: 2 * rh))
        p.closeSubpath()
        return p
    }

    /// A sweat drop `s` across, its round end centred on `c`, with its point up.
    static func sweatDrop(at c: CGPoint, s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 1.6 * s))
        p.addQuadCurve(to: CGPoint(x: c.x + 0.9 * s, y: c.y + 0.2 * s), control: CGPoint(x: c.x + 0.9 * s, y: c.y - 0.3 * s))
        p.addArc(center: CGPoint(x: c.x, y: c.y + 0.2 * s), radius: 0.9 * s, startAngle: .zero, endAngle: .degrees(180),
                 clockwise: false)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 1.6 * s), control: CGPoint(x: c.x - 0.9 * s, y: c.y - 0.3 * s))
        p.closeSubpath()
        return p
    }

    /// The sweat drop's colour: a pale blue, the same on every Tomo.
    static let sweat = Color(red: 165 / 255, green: 214 / 255, blue: 1).opacity(0.95)
}

extension TomoLook {
    /// This Tomo under a feeling's colour pass (`TomoFeeling.tint`), repainted from its own colours (`repainted`), so its
    /// head stays clear of the notch and its eyes clear of its head.
    func tinted(sat: Double, green: Double) -> TomoLook {
        repainted(head: TomoFeeling.tint(tone, sat: sat, green: green),
                  accent: TomoFeeling.tint(accentTone, sat: sat, green: green), cheekChroma: 0.15 * max(0.25, sat))
    }
}

extension TomoFeeling {
    /// A colour under a feeling's pass: `sat` of its chroma kept, and `green` of the way to a sickly green-grey (its hue
    /// turned toward 125°, its chroma toward 0.05, a little darker).
    static func tint(_ o: TomoOklch, sat: Double, green: Double) -> TomoOklch {
        var x = TomoOklch(l: o.l, c: o.c * sat, h: o.h)
        if green > 0 {
            let t = 0.8 * green
            x = TomoOklch(l: min(1, max(0, x.l - 0.03 * green)), c: x.c + (0.05 - x.c) * t, h: hue(x.h, toward: 125, by: t))
        }
        return x
    }
}

// MARK: - Checks (TOMO_SELFTEST)

extension TomoFeeling {
    /// The colour pass (#257): it keeps the seed, the shape and the look itself, and a sickly tint repaints every Tomo;
    /// across every tone and hue a sickly Tomo is painted greener and greyer, its head at 3:1 on the notch and its eyes
    /// at 4.5:1 on it (the colours `repainted` gives the copy).
    static func colourSelfTest(_ check: (Bool, String) -> Void) {
        let sick = Amounts(.sickly), sat = Double(sick.sat), green = Double(sick.green)
        let crowd = [TomoLook.mascot] + (0..<200).map { TomoLook(seed: "feeling-\($0)") }
        let ill = crowd.map { $0.tinted(sat: sat, green: green) }
        let kept = zip(crowd, ill).allSatisfy { own, ill in
            ill.seed == own.seed && ill.forms.map(\.silhouette) == own.forms.map(\.silhouette)
                && ill.eyeStyle == own.eyeStyle && ill.topper == own.topper && ill.body != own.body
        }
        let own = crowd.dropFirst().allSatisfy { $0.body == TomoLook(seed: $0.seed).body && $0.ink == TomoLook(seed: $0.seed).ink }
        check(kept && own && TomoLook.mascot.tinted(sat: 1, green: 0).body == TomoLook.mascot.body,
              "a feeling's colour is a pass over the look: sickly repaints every Tomo, and its seed, shape and own colours never change")
        // What the pass paints (`drawnTones`), for Tomos of every tone at every 5° of hue.
        func far(_ h: Double) -> Double { let d = abs(h - 125); return min(d, 360 - d) }
        var readable = true, sicker = true, tried = 0
        for tone in [0.15, 0.45, 0.7, 0.9, 0.99] {                          // pastel, mid, bright, deep, pale
            for hue in stride(from: 0.0, to: 1, by: 1.0 / 72) {
                let tomo = TomoLook(seed: "feeling-tone", overrides: ["tone": tone, "hue": hue])
                let drawn = tomo.tinted(sat: sat, green: green).drawnTones
                tried += 1
                if drawn.head.contrast(.notch) < 3 || drawn.ink.contrast(drawn.head) < 4.5 { readable = false }
                if drawn.head.c > max(tomo.tone.c, 0.05) + 1e-9 || far(drawn.head.h) > far(tomo.tone.h) * 0.4 + 1e-6 { sicker = false }
            }
        }
        // Whatever it's repainted in, even a head too dark for the notch (no Tomo's own tone tints that far today), the
        // copy's head is lifted to 3:1 on the notch and its eyes to 4.5:1 on it.
        var guarded = true
        for l in stride(from: 0.2, through: 0.95, by: 0.05) {
            for c in [0.03, 0.09, 0.16] {
                for h in stride(from: 0.0, to: 360, by: 10) {
                    let paint = TomoOklch(l: l, c: c, h: h)
                    let drawn = TomoLook.mascot.repainted(head: paint, accent: paint, cheekChroma: 0.15).drawnTones
                    if drawn.head.contrast(.notch) < 3 || drawn.ink.contrast(drawn.head) < 4.5 { guarded = false }
                }
            }
        }
        check(tried == 360 && readable && sicker && guarded,
              "a sickly Tomo turns greener and greyer on every tone and hue, its head 3:1 on the notch and its eyes 4.5:1 on it, "
              + "as is any repainted Tomo's")
    }
}
