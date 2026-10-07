import SwiftUI

// MARK: - What one Tomo looks like
//
// Every Tomo is a blob of its own (decisions.md, 2026-10-07). A seed, made when Tomo first appears, is hashed
// into named traits: the colour and eyes are Tomo's for life; the silhouette, size and extra details are
// rolled again at every birthday from the seed plus the age, so each Tomo evolves along its own path. The
// same seed always gives the same Tomo, so the Mac and the iPhone only have to agree on the seed.
//
// The method is blobatar's (MIT, github.com/Alain00/blobatar): a murmur3-mixed hash streamed per trait key,
// weighted bands for rare finds, and colours picked in OKLCh with a contrast floor. Trait keys are an
// append-only namespace: adding a key never changes an existing Tomo. Changing a key's range, a band table
// or a `pick` list does, so those are frozen once shipped.

public struct TomoLook: Equatable, Sendable {
    public let seed: String

    public enum EyeStyle: Sendable { case bar, dot, big, lidded, bead }
    public enum Mouth: Sendable { case none, smile, cat, o, fang, flat }
    public enum Pattern: Sendable { case none, belly, cap, spots, stripes, twoTone }
    public enum Topper: Sendable { case none, cat, bunny, bear, horns, antenna, sprout }

    /// The colours, fixed for life. `accent` is the second colour its markings use.
    public let hue: Double
    public let body: Color
    public let bodyLight: Color
    public let accent: Color
    public let ink: Color
    public let cheek: Color
    /// Eyes, fixed for life: a style, width and height (in body radii), squareness, spacing, height on the face.
    /// A rare Tomo has one big eye.
    public let eyeStyle: EyeStyle
    public let cyclops: Bool
    public let eyeW: CGFloat
    public let eyeH: CGFloat
    public let eyeN: CGFloat
    public let eyeGap: CGFloat
    public let eyeY: CGFloat
    /// Its face at rest, its markings, and what grows on its head from 2さい: all for life.
    public let mouth: Mouth
    public let pattern: Pattern
    public let topper: Topper
    /// Where its markings and its mark sit, seeded.
    public let markSeed: Double
    /// How fast it breathes and how often it blinks, so a room of Tomos doesn't move in unison.
    public let breathRate: Double
    public let blinkPace: Double

    /// The form at each age step (0 = 1さい).
    public let forms: [TomoForm]

    public static func == (a: TomoLook, b: TomoLook) -> Bool { a.seed == b.seed }

    /// Age steps a Tomo can reach (Japanese goes to 6さい).
    public static let ages = 6

    /// `newShapeEachAge`: off for the mascot, which keeps its one shape and only grows.
    /// How different Tomos are from one another. 1 is the shipped mix; lower pulls every Tomo toward the
    /// common middle (warm colours, everyday shapes, rare traits rarer), higher widens every range and makes
    /// rare traits commoner. Changing it changes every learner's Tomo, so it's fixed once shipped.
    public static let variety = 1.0

    /// `newShapeEachAge`: off for the mascot, which keeps its one shape and only grows.
    public init(seed: String, overrides: [String: Double] = [:], newShapeEachAge: Bool = true, variety: Double = TomoLook.variety) {
        self.seed = seed
        let t = TomoTraits(seed: seed, overrides: overrides, spread: variety)

        // Colour: any hue, in one of a few authored tones, so every Tomo looks like it came from one designer.
        // Centred on a warm yellow, so a low variety means warm Tomos rather than one arbitrary colour.
        let h = 85 + (t("hue") - 0.5) * 360 * min(1, variety)
        hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let tone = t.band("tone", Self.tones)
        var head = TomoOklch(l: tone.l, c: tone.c, h: hue)
        head = head.ensuringContrast(against: .notch, min: 3)          // always visible on the black notch
        let eye = head.l >= 0.5 ? TomoOklch(l: 0.2, c: 0.03, h: hue) : TomoOklch(l: 0.97, c: 0.012, h: hue)
        body = head.color
        bodyLight = TomoOklch(l: min(1, head.l + 0.07), c: head.c * 0.85, h: hue).color
        ink = eye.ensuringContrast(against: head, min: 4.5).color
        cheek = TomoOklch(l: 0.72, c: 0.15, h: 12).color

        pattern = t.band("pattern", [(Pattern.none, 0.3), (.belly, 0.46), (.cap, 0.6), (.spots, 0.74), (.stripes, 0.86), (.twoTone, 1)])
        let shift = t.numD("accent.hue", 40, 160) * (t("accent.dir") < 0.5 ? -1 : 1)
        let darker = head.l > 0.6 ? -0.13 : 0.13
        switch pattern {
        case .belly: accent = TomoOklch(l: min(0.97, head.l + 0.1), c: head.c * 0.35, h: hue).color
        case .twoTone: accent = TomoOklch(l: head.l, c: max(head.c, 0.1), h: hue + shift * 0.45).color   // neighbours, never muddy
        default: accent = TomoOklch(l: head.l + darker, c: max(head.c, 0.11), h: hue + shift * 0.5).color
        }

        eyeStyle = t.band("eye.style", [(EyeStyle.bar, 0.3), (.dot, 0.55), (.big, 0.72), (.lidded, 0.87), (.bead, 1)])
        cyclops = t.chance("eye.cyclops", 0.05)
        switch eyeStyle {
        case .bar:
            eyeW = t.num("eye.w", 0.085, 0.11); eyeH = eyeW * t.num("eye.ratio", 1.7, 2.6); eyeN = t.num("eye.n", 3.5, 6)
        case .dot:
            eyeW = t.num("eye.w", 0.085, 0.115); eyeH = eyeW * t.num("eye.ratio", 1, 1.15); eyeN = 2
        case .big:
            eyeW = t.num("eye.w", 0.13, 0.16); eyeH = eyeW * t.num("eye.ratio", 1.15, 1.35); eyeN = 2
        case .lidded:
            eyeW = t.num("eye.w", 0.11, 0.14); eyeH = eyeW * t.num("eye.ratio", 1, 1.2); eyeN = 2
        case .bead:
            eyeW = t.num("eye.w", 0.05, 0.065); eyeH = eyeW * t.num("eye.ratio", 1, 1.2); eyeN = 2
        }
        eyeGap = max(t.num("eye.gap", 0.2, 0.42), eyeW * 1.7)
        eyeY = t.num("eye.y", -0.16, 0.1)
        mouth = t.band("mouth", [(Mouth.none, 0.35), (.smile, 0.58), (.cat, 0.74), (.o, 0.84), (.fang, 0.93), (.flat, 1)])
        topper = t.band("topper", [(Topper.none, 0.3), (.cat, 0.44), (.bunny, 0.56), (.bear, 0.7), (.horns, 0.8), (.antenna, 0.9), (.sprout, 1)])
        markSeed = t("mark")
        breathRate = t.numD("motion.breath", 1.45, 1.95)
        blinkPace = t.numD("motion.blink", 0.8, 1.25)

        // The extras it gains with age, three of four in this Tomo's own order: at 2, 4 and 6さい.
        var pool = TomoForm.Detail.allCases
        var order: [TomoForm.Detail] = []
        for i in 0..<pool.count {
            let k = Int(t("detail.\(i)") * Double(pool.count))
            order.append(pool.remove(at: min(k, pool.count - 1)))
        }
        var forms: [TomoForm] = []
        for age in 0..<Self.ages {
            forms.append(TomoForm(age: age, traits: t, details: Set(order.prefix(min(3, (age + 1) / 2))),
                                   after: newShapeEachAge ? forms.last?.silhouette : nil))
        }
        self.forms = forms
    }

    public func form(_ age: Int) -> TomoForm { forms[min(max(age, 0), forms.count - 1)] }

    private struct Tone { let l: Double; let c: Double }
    /// pastel, mid, bright, deep, then pale (a rare near-white Tomo).
    private static let tones: [(Tone, Double)] = [
        (Tone(l: 0.86, c: 0.09), 0.3), (Tone(l: 0.75, c: 0.13), 0.6), (Tone(l: 0.87, c: 0.16), 0.82),
        (Tone(l: 0.66, c: 0.16), 0.97), (Tone(l: 0.93, c: 0.03), 1),
    ]

    /// The Tomodachi mascot: the one Tomo everyone sees where a learner's own can't be drawn (widgets, the
    /// Lock Screen, the app icon). Pinned traits, so it never changes with the hash.
    public static let mascot = TomoLook(seed: "tomodachi", overrides: [
        "hue": 0.5, "tone": 0.7, "eye.style": 0.1, "eye.cyclops": 0.9, "eye.w": 0.8, "eye.ratio": 0.5,
        "eye.n": 0.4, "eye.gap": 0.5, "eye.y": 0.4, "mouth": 0.1, "pattern": 0.1, "topper": 0.1,
        "age0.body.ratio": 0.45, "age1.body.ratio": 0.45, "age2.body.ratio": 0.45, "age3.body.ratio": 0.45,
        "age4.body.ratio": 0.45, "age5.body.ratio": 0.45,
        "age0.shape": 0.1, "age1.shape": 0.1, "age2.shape": 0.1, "age3.shape": 0.1, "age4.shape": 0.1, "age5.shape": 0.1,
    ], newShapeEachAge: false, variety: 1)

    /// The learner's Tomo, set by TomoGame when the saved Tomo loads or changes (each TomoBlob that follows
    /// the learner picks it up on its next frame). The mascot until then.
    @MainActor public static var current = TomoLook.mascot

    /// The seed for a saved Tomo: the second it first appeared, in this language pair. Saved and synced with
    /// the Tomo already, and new when the learner starts over (a new Tomo hatches).
    /// TOMO_SEED=<text> pins it, for snapshots of a known Tomo.
    public static func seed(learner: String, target: String, metAt: Date) -> String {
        if let s = ProcessInfo.processInfo.environment["TOMO_SEED"] { return s }
        return "\(learner)-\(target)-\(Int(metAt.timeIntervalSince1970.rounded(.down)))"
    }
}

extension TomoLook {
    /// The look rules, checked by TOMO_SELFTEST (docs/verification.md).
    public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        let a = TomoLook(seed: "selftest-1"), b = TomoLook(seed: "selftest-1"), c = TomoLook(seed: "selftest-2")
        check(a.forms.map(\.silhouette) == b.forms.map(\.silhouette) && a.eyeW == b.eyeW && a.body == b.body,
              "the same seed gives the same Tomo")
        check(a.body != c.body || a.eyeW != c.eyeW, "a different seed gives a different Tomo")
        let met = Date(timeIntervalSince1970: 1_800_000_000)
        check(seed(learner: "en", target: "ja", metAt: met.addingTimeInterval(0.2))
              == seed(learner: "en", target: "ja", metAt: met.addingTimeInterval(0.9)),
              "the seed ignores fractions of a second (devices may store the time more or less precisely)")
        let crowd = (0..<300).map { TomoLook(seed: "selftest-crowd-\($0)") }
        check(crowd.allSatisfy { l in zip(l.forms, l.forms.dropFirst()).allSatisfy { $0.silhouette != $1.silhouette } },
              "every birthday changes the shape")
        check(crowd.allSatisfy { [.round, .organic, .nub].contains($0.form(0).silhouette) }, "age 1 is always a soft shape")
        check(Set(crowd.map { $0.form(3).silhouette.rawValue }).count == 10, "every shape turns up in a crowd")
        check(crowd.allSatisfy { $0.form(5).details.count == 3 && $0.form(0).details.isEmpty },
              "three extras come with age, at ages 2, 4 and 6")
        let kinds = Set(crowd.map { l in
            "\(Int(l.hue / 20)) \(l.eyeStyle) \(l.cyclops) \(l.mouth) \(l.pattern) \(l.topper) \(l.form(0).silhouette)"
        })
        check(kinds.count >= 295, "a crowd of 300 Tomos has almost no lookalikes (\(kinds.count) different)")
        check(mascot.forms.allSatisfy { $0.silhouette == .round }, "the mascot stays round at every age")
        var readable = true
        for (tone, _) in tones {
            for hue in stride(from: 0.0, to: 360, by: 5) {
                let head = TomoOklch(l: tone.l, c: tone.c, h: hue).ensuringContrast(against: .notch, min: 3)
                let eye = head.l >= 0.5 ? TomoOklch(l: 0.2, c: 0.03, h: hue) : TomoOklch(l: 0.97, c: 0.012, h: hue)
                if head.contrast(.notch) < 3 || eye.ensuringContrast(against: head, min: 4.5).contrast(head) < 4.5 {
                    readable = false
                }
            }
        }
        check(readable, "every colour stands out on the notch, and its eyes on it")
        return ok
    }
}

/// One age's shape: the silhouette and the extra details Tomo has at that age.
public struct TomoForm: Sendable {
    public enum Silhouette: String, Sendable { case round, organic, boxy, capsule, nub, cloud, droplet, hexagon, sun, triangle }
    public enum Detail: CaseIterable, Sendable { case cheeks, freckles, sheen, mark }

    public let silhouette: Silhouette
    /// Size, growing with age (1 at 1さい).
    public let scale: CGFloat
    /// Body radii, in units of R: rx, ry, and squareness.
    public let rx: CGFloat
    public let ry: CGFloat
    public let n: CGFloat
    public let rot: CGFloat
    /// Per-vertex radius multipliers, for the organic and cloud outlines.
    public let radii: [CGFloat]
    /// Circles unioned with the body (cloud lobes, sun rays, nubs, capsule ends), in units of R.
    public let petals: [(x: CGFloat, y: CGFloat, r: CGFloat)]
    public let sides: Int
    public let corner: CGFloat
    public let tip: CGFloat
    /// Where the eyes sit (centre y) and how much room they have, in units of R.
    public let faceY: CGFloat
    public let faceW: CGFloat
    public let details: Set<Detail>
    /// How its topper leans, seeded too.
    public let sproutLean: CGFloat

    /// The everyday shapes come up often; the loud ones are finds. Babies (1さい) are always soft shapes.
    private static let bands: [(Silhouette, Double)] = [
        (.round, 0.22), (.organic, 0.46), (.boxy, 0.58), (.capsule, 0.68), (.nub, 0.78),
        (.cloud, 0.86), (.droplet, 0.915), (.hexagon, 0.95), (.sun, 0.98), (.triangle, 1),
    ]
    private static let babyBands: [(Silhouette, Double)] = [(.round, 0.45), (.organic, 0.8), (.nub, 1)]

    /// `after`: last age's silhouette. A birthday always changes the shape, so a repeat rolls once more (then
    /// takes the next band along).
    init(age: Int, traits t: TomoTraits, details: Set<Detail>, after: Silhouette? = nil) {
        let k = "age\(age)."
        let bands = age == 0 ? Self.babyBands : Self.bands
        var shape = t.band(k + "shape", bands)
        if shape == after { shape = t.band(k + "shape.again", bands) }
        if shape == after, let i = bands.firstIndex(where: { $0.0 == shape }) { shape = bands[(i + 1) % bands.count].0 }
        silhouette = shape
        scale = 1 + 0.07 * CGFloat(age)
        self.details = details
        sproutLean = t.jitter(k + "sprout", 0.35)

        let ratio = t.num(k + "body.ratio", 0.78, 1.22)
        var rx: CGFloat = 1, ry: CGFloat = ratio, n = t.num(k + "body.n", 1.9, 2.5), rot: CGFloat = 0
        var radii: [CGFloat] = []
        var petals: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []
        var sides = 0, corner: CGFloat = 0, tip: CGFloat = 0
        var faceY: CGFloat = -0.05, faceW: CGFloat = 1

        switch silhouette {
        case .round:
            break
        case .organic:
            let count = Int(t.num(k + "body.pts", 6, 8.99))
            radii = (0..<count).map { 1 + t.jitter(k + "body.r\($0)", 0.14) }
            faceW = (radii.min() ?? 1) * 0.95
        case .boxy:
            rx = 0.9; ry = 0.9 * ratio; n = t.num(k + "boxy.n", 3.4, 6); rot = t.jitter(k + "boxy.rot", 0.25)
        case .capsule:
            rx = 1.05; ry = 1.05 * t.num(k + "capsule.squat", 0.6, 0.72)
            petals = [(-(rx - ry), 0, ry), (rx - ry, 0, ry)]
            faceY = 0
        case .nub:
            rx = 0.9; ry = 0.9 * ratio
            for i in 0..<(t(k + "nub.count") < 0.5 ? 1 : 2) {
                let a = -Double.pi / 2 + Double(t.jitter(k + "nub.a\(i)", 1.3))
                petals.append((rx * 0.85 * CGFloat(cos(a)), ry * 0.85 * CGFloat(sin(a)), rx * t.num(k + "nub.r\(i)", 0.24, 0.36)))
            }
        case .cloud:
            rx = 0.85; ry = 0.8
            let count = Int(t.num(k + "cloud.n", 4, 6.99))
            radii = (0..<8).map { 1 + t.jitter(k + "body.r\($0)", 0.08) }
            for i in 0..<count {
                let a = Double.pi + Double.pi * (Double(i) + 0.5) / Double(count)
                petals.append((rx * 0.8 * CGFloat(cos(a)), ry * 0.55 * CGFloat(sin(a)), rx * t.num(k + "cloud.r\(i)", 0.4, 0.56)))
            }
            faceY = 0.05; faceW = 0.85
        case .droplet:
            rx = 0.82; ry = 0.82; n = 2; tip = t.num(k + "droplet.tip", 1.4, 1.65)
            faceY = 0.04; faceW = 0.88
        case .hexagon:
            rx = 1.04; ry = 1.04 * ratio; sides = 6; corner = t.num(k + "poly.round", 0.25, 0.5)
            rot = t.jitter(k + "poly.rot", 0.2); faceW = 0.84
        case .sun:
            rx = 0.74; ry = 0.74
            let count = Int(t.num(k + "sun.n", 6, 9.99))
            let dist = rx * t.num(k + "sun.dist", 1.0, 1.08), pr = rx * t.num(k + "sun.r", 0.2, 0.26)
            let off = t.numD(k + "sun.rot", 0, 2 * .pi)
            for i in 0..<count {
                let a = off + 2 * .pi * Double(i) / Double(count)
                petals.append((dist * CGFloat(cos(a)), dist * CGFloat(sin(a)), pr))
            }
        case .triangle:
            rx = 1.18; ry = 1.1; sides = 3; corner = t.num(k + "poly.round", 0.35, 0.55)
            rot = t.jitter(k + "poly.rot", 0.06); faceY = 0.22; faceW = 0.55
        }
        // Droplets carry their point above: drop the body so the whole shape sits on the same ground.
        if silhouette == .droplet { faceY += 0.18 }
        self.rx = rx; self.ry = ry; self.n = n; self.rot = rot; self.radii = radii; self.petals = petals
        self.sides = sides; self.corner = corner; self.tip = tip; self.faceY = faceY; self.faceW = faceW
    }

    /// The body's outline, centred on the origin, in points (R = one body radius).
    public func path(R: CGFloat) -> Path {
        var p = Path()
        let rx = self.rx * R, ry = self.ry * R
        if sides > 0 {
            p = Self.polygon(rx: rx, ry: ry, sides: sides, round: corner, rot: rot)
        } else if !radii.isEmpty {
            p = Self.spline(rx: rx, ry: ry, radii: radii)
        } else if silhouette == .capsule {
            p.addRect(CGRect(x: -(rx - ry), y: -ry, width: 2 * (rx - ry), height: 2 * ry))
        } else {
            p = Self.superellipse(rx: rx, ry: ry, n: n, rot: rot)
        }
        for c in petals {
            p = p.union(Path(ellipseIn: CGRect(x: (c.x - c.r) * R, y: (c.y - c.r) * R, width: c.r * 2 * R, height: c.r * 2 * R)))
        }
        if tip > 0 { p = p.union(Self.taper(rx: rx, ry: ry, tip: tip)) }
        if silhouette == .droplet { p = p.offsetBy(dx: 0, dy: 0.18 * R) }
        return p
    }

    /// How far the shape reaches above and below its centre, in units of R (for the ground line and sprout).
    public var top: CGFloat {
        var t = ry
        if tip > 0 { t = ry * tip * 0.95 - 0.18 }
        for c in petals { t = max(t, -c.y + c.r) }
        return t
    }
    public var bottom: CGFloat {
        var b = ry + (silhouette == .droplet ? 0.18 : 0)
        for c in petals { b = max(b, c.y + c.r) }
        return b
    }

    // MARK: Primitives (blobatar's shape.ts, as SwiftUI paths)

    /// |x/a|^n + |y/b|^n = 1, one cubic per quadrant through the 45° point.
    static func superellipse(rx a: CGFloat, ry b: CGFloat, n: CGFloat, rot: CGFloat = 0) -> Path {
        let k = min(1, (8 * pow(2, -1 / n) - 4) / 3)
        let pts: [(CGFloat, CGFloat)] = [
            (a, 0), (a, b * k), (a * k, b), (0, b), (-a * k, b), (-a, b * k), (-a, 0),
            (-a, -b * k), (-a * k, -b), (0, -b), (a * k, -b), (a, -b * k), (a, 0),
        ]
        let c = cos(rot), s = sin(rot)
        let at = { (i: Int) in CGPoint(x: pts[i].0 * c - pts[i].1 * s, y: pts[i].0 * s + pts[i].1 * c) }
        var p = Path()
        p.move(to: at(0))
        for i in stride(from: 1, to: 13, by: 3) { p.addCurve(to: at(i + 2), control1: at(i), control2: at(i + 1)) }
        p.closeSubpath()
        return p
    }

    /// A closed Catmull-Rom curve through radii sampled around an ellipse: the lumpy pebble.
    static func spline(rx: CGFloat, ry: CGFloat, radii: [CGFloat]) -> Path {
        let n = radii.count
        let pts = radii.enumerated().map { i, m -> CGPoint in
            let a = 2 * CGFloat.pi * CGFloat(i) / CGFloat(n)
            return CGPoint(x: rx * m * cos(a), y: ry * m * sin(a))
        }
        let at = { (i: Int) in pts[((i % n) + n) % n] }
        var p = Path()
        p.move(to: at(0))
        for i in 0..<n {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            p.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                       control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        p.closeSubpath()
        return p
    }

    /// A regular polygon with rounded corners, a vertex at the top.
    static func polygon(rx: CGFloat, ry: CGFloat, sides: Int, round: CGFloat, rot: CGFloat) -> Path {
        let k = min(0.5, max(0, round / 2))
        let v = (0..<sides).map { i -> CGPoint in
            let a = rot - .pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(sides)
            return CGPoint(x: rx * cos(a), y: ry * sin(a))
        }
        let at = { (i: Int) in v[((i % sides) + sides) % sides] }
        let cut = { (i: Int, j: Int) -> CGPoint in
            let a = at(i), b = at(j)
            return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        var p = Path()
        p.move(to: cut(0, -1))
        for i in 0..<sides {
            p.addQuadCurve(to: cut(i, i + 1), control: at(i))
            if k < 0.5 { p.addLine(to: cut(i + 1, i)) }
        }
        p.closeSubpath()
        return p
    }

    /// The point of a droplet: the two tangents from an apex above the body ellipse.
    static func taper(rx: CGFloat, ry: CGFloat, tip: CGFloat) -> Path {
        let t = max(1.05, tip)
        let tx = rx * sqrt(1 - 1 / (t * t)), ty = -ry / t, apex = -t * ry
        let px = tx * 0.14, py = ty + 0.86 * (apex - ty)
        var p = Path()
        p.move(to: CGPoint(x: -tx, y: ty))
        p.addLine(to: CGPoint(x: -px, y: py))
        p.addQuadCurve(to: CGPoint(x: px, y: py), control: CGPoint(x: 0, y: apex))
        p.addLine(to: CGPoint(x: tx, y: ty))
        p.closeSubpath()
        return p
    }
}

// MARK: - Traits from a seed

/// Reads values from a seed by name. Each key hashes on its own, so keys are independent and new ones can be
/// added without changing any existing Tomo. An override (0…1) pins a key to that position in its range.
struct TomoTraits {
    private let state: UInt32
    private let overrides: [String: Double]

    /// How far values reach from the middle of each range, and how flat the odds are (1 = as written).
    private let spread: Double

    init(seed: String, overrides: [String: Double] = [:], spread: Double = 1) {
        self.spread = max(0.01, spread)
        let s = seed.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bytes = Array(s.utf8)
        state = Self.feed(1_779_033_703 ^ UInt32(truncatingIfNeeded: bytes.count), bytes)
        self.overrides = overrides
    }

    /// Uniform in [0, 1).
    func callAsFunction(_ key: String) -> Double {
        if let o = overrides[key] { return min(max(o, 0), 0.999999) }
        let h = Self.finalize(Self.feed(Self.feed(state, [0xFF]), Array(key.utf8)))
        return Double(h) / 4_294_967_296
    }

    func num(_ key: String, _ lo: Double, _ hi: Double) -> CGFloat { CGFloat(numD(key, lo, hi)) }
    func numD(_ key: String, _ lo: Double, _ hi: Double) -> Double { (lo + hi) / 2 + (self(key) - 0.5) * (hi - lo) * spread }
    func jitter(_ key: String, _ amount: Double) -> CGFloat { CGFloat((self(key) * 2 - 1) * amount * spread) }
    /// True with probability `p` (squared with the spread, so rare things get much rarer or commoner).
    func chance(_ key: String, _ p: Double) -> Bool { self(key) < min(0.5, p * spread * spread) }
    /// A weighted pick: each option with the upper edge of its band in [0, 1). The spread flattens the odds
    /// (above 1) or sharpens them toward the commonest options (below 1).
    func band<T>(_ key: String, _ bands: [(T, Double)]) -> T {
        let v = self(key)
        var edges = bands.map(\.1)
        if spread != 1 {
            var last = 0.0
            let weights = bands.map { b -> Double in defer { last = b.1 }; return pow(max(1e-6, b.1 - last), 1 / spread) }
            let total = weights.reduce(0, +)
            var sum = 0.0
            edges = weights.map { sum += $0 / total; return sum }
        }
        return bands[edges.firstIndex { v < $0 } ?? bands.count - 1].0
    }

    private static func feed(_ h0: UInt32, _ bytes: [UInt8]) -> UInt32 {
        var h = h0
        for b in bytes {
            h = (h ^ UInt32(b)) &* 3_432_918_353
            h = (h << 13) | (h >> 19)
        }
        return h
    }

    /// murmur3's fmix32: full avalanche, so near-identical seeds look unrelated.
    private static func finalize(_ h0: UInt32) -> UInt32 {
        var h = h0
        h = (h ^ (h >> 16)) &* 2_246_822_507
        h = (h ^ (h >> 13)) &* 3_266_489_909
        return h ^ (h >> 16)
    }
}

// MARK: - Colour in OKLCh

/// A perceptual colour (lightness 0…1, chroma, hue in degrees), so every hue in a tone looks equally light.
struct TomoOklch {
    var l: Double, c: Double, h: Double

    static let notch = TomoOklch(l: 0.145, c: 0, h: 0)

    private func linear(c chroma: Double) -> (Double, Double, Double) {
        let r = h * .pi / 180, a = chroma * cos(r), b = chroma * sin(r)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.291485548 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return (4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
                -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
                -0.0041960863 * L - 0.7034186147 * M + 1.707614701 * S)
    }

    /// Linear sRGB, giving up chroma (not hue) when the colour is out of gamut.
    private var rgb: (Double, Double, Double) {
        let ok = { (v: (Double, Double, Double)) in [v.0, v.1, v.2].allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 } }
        var v = linear(c: c)
        if !ok(v) {
            var lo = 0.0, hi = c
            for _ in 0..<12 { let mid = (lo + hi) / 2; if ok(linear(c: mid)) { lo = mid } else { hi = mid } }
            v = linear(c: lo)
        }
        let clamp = { (x: Double) in min(1, max(0, x)) }
        return (clamp(v.0), clamp(v.1), clamp(v.2))
    }

    var luminance: Double { let v = rgb; return 0.2126 * v.0 + 0.7152 * v.1 + 0.0722 * v.2 }

    func contrast(_ o: TomoOklch) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Moves lightness away from `bg` until the pair reaches `min` contrast.
    func ensuringContrast(against bg: TomoOklch, min target: Double) -> TomoOklch {
        if contrast(bg) >= target { return self }
        let lean: Double = l >= bg.l ? 1 : -1
        for dir in [lean, -lean] {
            var p = self
            for _ in 0..<60 {
                p.l = min(1, max(0, p.l + dir * 0.02))
                if p.contrast(bg) >= target { return p }
                if p.l == 0 || p.l == 1 { break }
            }
        }
        return self
    }

    var color: Color {
        let v = rgb
        let enc = { (x: Double) in x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        return Color(.sRGB, red: enc(v.0), green: enc(v.1), blue: enc(v.2))
    }
}
