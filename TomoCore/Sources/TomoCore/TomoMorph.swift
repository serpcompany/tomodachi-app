import SwiftUI

// MARK: - One outline becoming another (a birthday's morph, #259)
//
// A port of flubber's single-shape interpolation (MIT, Noah Veltman, github.com/veltman/flubber; its notice ships as
// TomoCore/LICENSE-flubber and About credits it). flubber samples each outline at equal steps along its length, winds
// both the same way, spreads extra points evenly along the one with fewer, and turns the first so its points travel as
// short a way as they can (least squares). Then every point moves in a straight line.
// Where this differs: the outline is the path's biggest closed piece (flubber takes the first), steps are measured in
// units of R, and progress past 1 carries on along the same lines (flubber hands back the end shape there), so a
// spring's overshoot overshoots the shape too, as the states lab's does. Every pair of Tomo's shapes takes the whole
// overshoot without folding (the self-test's survey).
//
// `TomoMorph` is the outline part, for any two closed paths (the egg's hatch can reuse it, #258). `TomoFormMorph` is one
// `TomoForm` becoming another: the outline, the rest of the form blended as the states lab blends it, and the lab's
// timings (`flubber`, and Reduce Motion's `crossfade`). TomoBlob plays it at a birthday (`Cue.Step.morph`).

/// One closed outline becoming another as progress goes 0 → 1 (flubber's `interpolate`).
public struct TomoMorph: Sendable {
    /// The two outlines, point for point: as many points each, wound the same way, lined up.
    public let from: [CGPoint]
    public let to: [CGPoint]

    /// `spacing`: the most room between neighbouring points on either outline (flubber's `maxSegmentLength`), in the
    /// paths' own units.
    public init(from a: Path, to b: Path, spacing: CGFloat) {
        var ra = Self.ring(a, spacing: spacing), rb = Self.ring(b, spacing: spacing)
        let diff = ra.count - rb.count
        Self.addPoints(&ra, max(0, -diff))
        Self.addPoints(&rb, max(0, diff))
        Self.rotate(&ra, toward: rb)
        from = ra
        to = rb
    }

    /// The outline `u` of the way (0: `from`, 1: `to`). Past either end it carries on along the same lines.
    public func points(at u: CGFloat) -> [CGPoint] {
        zip(from, to).map { a, b in Self.along(a, b, u) }
    }

    public func path(at u: CGFloat) -> Path { Self.path(points(at: u)) }

    /// A closed outline through `points`, in straight steps (flubber's `toPathString`).
    public static func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    // MARK: flubber, step by step

    /// flubber's `pathStringToRing` and `normalizeRing`: at least three points at equal steps along the outline, none
    /// further apart than `spacing`, wound so d3's signed area isn't positive (clockwise on screen).
    static func ring(_ path: Path, spacing: CGFloat) -> [CGPoint] {
        let line = outline(path)
        let length = perimeter(line)
        guard line.count > 2, length > 0 else { return line }
        let count = max(3, Int((length / max(spacing, 1e-6)).rounded(.up)))
        var points = sample(line, count: count, length: length)
        if area(points) > 0 { points.reverse() }
        return points
    }

    /// The path flattened into closed polylines (each curve in 16 straight steps, far finer than the samples), and the
    /// biggest kept: a union can leave a sliver ahead of the body.
    static func outline(_ path: Path) -> [CGPoint] {
        var pieces: [[CGPoint]] = [], piece: [CGPoint] = []
        var last = CGPoint.zero, start = CGPoint.zero
        func end() {
            if let f = piece.first, let l = piece.last, f == l { piece.removeLast() }
            if piece.count > 2 { pieces.append(piece) }
            piece = []
        }
        path.forEach { element in
            switch element {
            case .move(let p):
                end(); piece = [p]; last = p; start = p
            case .line(let p):
                if piece.isEmpty { piece = [last] }
                piece.append(p); last = p
            case .quadCurve(let p, let c):
                if piece.isEmpty { piece = [last] }
                let a = last
                for i in 1...16 {
                    let t = CGFloat(i) / 16, s = 1 - t
                    piece.append(CGPoint(x: s * s * a.x + 2 * s * t * c.x + t * t * p.x,
                                         y: s * s * a.y + 2 * s * t * c.y + t * t * p.y))
                }
                last = p
            case .curve(let p, let c1, let c2):
                if piece.isEmpty { piece = [last] }
                let a = last
                for i in 1...16 {
                    let t = CGFloat(i) / 16, s = 1 - t
                    let w0 = s * s * s, w1 = 3 * s * s * t, w2 = 3 * s * t * t, w3 = t * t * t
                    piece.append(CGPoint(x: w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * p.x,
                                         y: w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * p.y))
                }
                last = p
            case .closeSubpath:
                end(); last = start
            }
        }
        end()
        return pieces.max { abs(area($0)) < abs(area($1)) } ?? []
    }

    /// `count` points at equal steps along a closed polyline `length` long, the first at its start
    /// (svg-path-properties' `getPointAtLength`, as flubber calls it).
    static func sample(_ line: [CGPoint], count: Int, length: CGFloat) -> [CGPoint] {
        let n = line.count
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        var i = 0, cursor: CGFloat = 0                  // the edge from line[i], and the length before it
        for k in 0..<count {
            let want = length * CGFloat(k) / CGFloat(count)
            while i < n - 1, cursor + distance(line[i], line[i + 1]) < want {
                cursor += distance(line[i], line[i + 1])
                i += 1
            }
            let a = line[i], b = line[(i + 1) % n], edge = distance(a, b)
            out.append(edge > 0 ? along(a, b, min(1, max(0, (want - cursor) / edge))) : a)
        }
        return out
    }

    /// flubber's `addPoints`: `count` more points spread evenly along the ring, half a step in.
    static func addPoints(_ ring: inout [CGPoint], _ count: Int) {
        guard count > 0, !ring.isEmpty else { return }
        let desired = ring.count + count, step = perimeter(ring) / CGFloat(count)
        var i = 0, cursor: CGFloat = 0, insertAt = step / 2
        while ring.count < desired, i < ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count], segment = distance(a, b)
            if insertAt <= cursor + segment {
                ring.insert(segment > 0 ? along(a, b, (insertAt - cursor) / segment) : a, at: i + 1)
                insertAt += step
                continue
            }
            cursor += segment
            i += 1
        }
        while ring.count < desired, let l = ring.last { ring.append(l) }   // rounding: never short
    }

    /// flubber's `rotate`: starts the ring where the sum of squared distances to `target`'s points is least.
    static func rotate(_ ring: inout [CGPoint], toward target: [CGPoint]) {
        let n = ring.count
        guard n > 1, target.count == n else { return }
        var best = 0, least = CGFloat.infinity
        for offset in 0..<n {
            var sum: CGFloat = 0
            for (i, p) in target.enumerated() {
                let q = ring[(offset + i) % n], dx = q.x - p.x, dy = q.y - p.y
                sum += dx * dx + dy * dy
            }
            if sum < least { least = sum; best = offset }
        }
        if best > 0 { ring = Array(ring[best...] + ring[..<best]) }
    }

    /// d3's `polygonArea`: half the signed area, positive one way round and negative the other.
    static func area(_ ring: [CGPoint]) -> CGFloat {
        guard var b = ring.last else { return 0 }
        var sum: CGFloat = 0
        for p in ring {
            let a = b
            b = p
            sum += a.y * b.x - a.x * b.y
        }
        return sum / 2
    }

    /// d3's `polygonLength`: all the way round, back to the start.
    static func perimeter(_ ring: [CGPoint]) -> CGFloat {
        guard var b = ring.last else { return 0 }
        var sum: CGFloat = 0
        for p in ring {
            sum += distance(b, p)
            b = p
        }
        return sum
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    static func along(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: Checking a morph

    /// How well a morph holds together, measured on its frames (each an outline in `from`'s point order).
    public struct Health: Sendable {
        /// Frames whose outline crosses itself: a tangle.
        public var tangled = 0
        /// Frames wound the other way, or squeezed under a quarter of the smaller end's area (a flip passes through
        /// nothing on its way).
        public var flipped = 0
        /// The farthest any point turns round the middle between the two outlines, and the points' average turn (signed:
        /// a morph whose points all turn one way spins instead of changing shape), in radians.
        public var farthest: CGFloat = 0
        public var twist: CGFloat = 0
        /// The biggest loop let through as a speck (`TomoMorph.speck`), as a share of its outline's area.
        public var speck: CGFloat = 0

        /// No tangle, no flip, no point carried more than a quarter turn round, and no spin past a sixteenth of a turn.
        public var sound: Bool { tangled == 0 && flipped == 0 && farthest < .pi / 2 && abs(twist) < .pi / 8 }
    }

    public func health(_ frames: [[CGPoint]]) -> Health {
        var h = Health()
        let floor = 0.25 * min(abs(Self.area(from)), abs(Self.area(to)))
        for f in frames {
            let a = Self.area(f), loop = Self.tangle(f) / max(abs(a), 1e-9)
            if loop > Self.speck { h.tangled += 1 } else { h.speck = max(h.speck, loop) }
            if a > 0 || -a < floor { h.flipped += 1 }
        }
        let ca = Self.middle(from), cb = Self.middle(to)
        var sum: CGFloat = 0
        for (a, b) in zip(from, to) {
            let turn = (atan2(b.y - cb.y, b.x - cb.x) - atan2(a.y - ca.y, a.x - ca.x)).remainder(dividingBy: 2 * .pi)
            h.farthest = max(h.farthest, abs(turn))
            sum += turn
        }
        h.twist = from.isEmpty ? 0 : sum / CGFloat(from.count)
        return h
    }

    static func middle(_ ring: [CGPoint]) -> CGPoint {
        let n = CGFloat(max(ring.count, 1))
        return CGPoint(x: ring.reduce(0) { $0 + $1.x } / n, y: ring.reduce(0) { $0 + $1.y } / n)
    }

    /// A loop smaller than this share of the outline's area isn't a tangle but a speck: where two parts of a union meet,
    /// the outline zigzags back on itself by a hair, and morphing can turn the zigzag into a loop far under a pixel.
    static let speck: CGFloat = 0.00005

    /// Whether the outline crosses itself in a loop bigger than a speck.
    static func crossesItself(_ p: [CGPoint]) -> Bool { tangle(p) > speck * abs(area(p)) }

    /// The biggest loop where the outline crosses itself: for each two edges that aren't neighbours and cross, the area
    /// of the smaller of the two pieces the crossing cuts the outline into (0 if it never crosses). Edges go into a grid
    /// about two edges wide, and only edges sharing a cell are compared, each pair once (in the first cell they share).
    static func tangle(_ p: [CGPoint]) -> CGFloat {
        let n = p.count
        guard n > 3 else { return 0 }
        var lo = CGPoint(x: CGFloat.infinity, y: .infinity), hi = CGPoint(x: -CGFloat.infinity, y: -.infinity)
        for q in p { lo = CGPoint(x: min(lo.x, q.x), y: min(lo.y, q.y)); hi = CGPoint(x: max(hi.x, q.x), y: max(hi.y, q.y)) }
        let cell = max(2 * perimeter(p) / CGFloat(n), 1e-9)
        let cols = Int((hi.x - lo.x) / cell) + 1, rows = Int((hi.y - lo.y) / cell) + 1
        guard cols * rows < 1_000_000 else { return 0 }
        // Each edge's cells (x0, x1, y0, y1), then the cells' edges in one flat list, `first[c]..<first[c + 1]`.
        var span = [(Int, Int, Int, Int)](), first = [Int](repeating: 0, count: cols * rows + 1)
        span.reserveCapacity(n)
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n]
            let s = (Int((min(a.x, b.x) - lo.x) / cell), Int((max(a.x, b.x) - lo.x) / cell),
                     Int((min(a.y, b.y) - lo.y) / cell), Int((max(a.y, b.y) - lo.y) / cell))
            span.append(s)
            for y in s.2...s.3 { for x in s.0...s.1 { first[y * cols + x + 1] += 1 } }
        }
        for c in 0..<(cols * rows) { first[c + 1] += first[c] }
        var edges = [Int](repeating: 0, count: first[cols * rows]), fill = first
        for i in 0..<n {
            let s = span[i]
            for y in s.2...s.3 { for x in s.0...s.1 { edges[fill[y * cols + x]] = i; fill[y * cols + x] += 1 } }
        }
        var most: CGFloat = 0
        let whole = abs(area(p))
        for c in 0..<(cols * rows) where first[c + 1] - first[c] > 1 {
            for s in first[c]..<(first[c + 1] - 1) {
                for t in (s + 1)..<first[c + 1] {
                    let i = min(edges[s], edges[t]), j = max(edges[s], edges[t])
                    if j - i <= 1 || j - i == n - 1 { continue }
                    let a = span[i], b = span[j]
                    if max(a.2, b.2) * cols + max(a.0, b.0) != c { continue }   // not the first cell they share
                    guard let x = cross(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) else { continue }
                    let loop = abs(area([x] + p[(i + 1)...j]))
                    most = max(most, min(loop, max(0, whole - loop)))
                }
            }
        }
        return most
    }

    /// Where segments ab and cd cross, if they do (touching at an end doesn't count).
    static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
        guard d1 * d2 < 0, d3 * d4 < 0 else { return nil }
        return along(a, b, d1 / (d1 - d2))
    }
}

/// One age's form becoming another's: the outline through `TomoMorph`, and the rest of the form blended alongside.
public struct TomoFormMorph: Sendable {
    public let from: TomoForm
    public let to: TomoForm
    /// Their outlines, at R = 1.
    public let outline: TomoMorph

    /// 0.04 R between points (flubber's default is 10 px): about 160 round a body, so the straight steps never show.
    public static let spacing: CGFloat = 0.04

    public init(_ a: TomoForm, _ b: TomoForm) {
        from = a
        to = b
        outline = TomoMorph(from: a.path(R: 1), to: b.path(R: 1), spacing: Self.spacing)
    }

    /// The outline `u` of the way, at R = 1, wobbling out and in by `wobble` of its radius four times round, the wobble
    /// turned by `phase` (the states lab's), round the body's middle (lower on a droplet, which carries its point above).
    public func points(at u: CGFloat, wobble: CGFloat = 0, phase: CGFloat = 0) -> [CGPoint] {
        let points = outline.points(at: u)
        guard wobble != 0 else { return points }
        let c = CGPoint(x: 0, y: from.drop + (to.drop - from.drop) * u)
        return points.map { p in
            let dx = p.x - c.x, dy = p.y - c.y, k = 1 + wobble * sin(4 * atan2(dy, dx) + phase)
            return CGPoint(x: c.x + dx * k, y: c.y + dy * k)
        }
    }

    /// The form `u` of the way, with this outline. The rest is the states lab's blend (`blendF`): its size, body radii,
    /// where the face sits and how wide it is, how far it reaches up and down, where the topper stands and how it leans
    /// move with `u` (held to -0.25…1.25, so a spring's overshoot can't run away); the silhouette's own numbers and its
    /// extras are the nearer form's. At either end, unwobbled, it is that form itself.
    public func form(at u: CGFloat, wobble: CGFloat = 0, phase: CGFloat = 0) -> TomoForm {
        if wobble == 0, abs(u) < 1e-4 { return from }
        if wobble == 0, abs(1 - u) < 1e-4 { return to }
        let k = min(max(u, -0.25), 1.25)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }
        var f = k < 0.5 ? from : to
        f.scale = mix(from.scale, to.scale)
        f.rx = mix(from.rx, to.rx)
        f.ry = mix(from.ry, to.ry)
        f.faceY = mix(from.faceY, to.faceY)
        f.faceW = max(0.4, mix(from.faceW, to.faceW))
        f.sproutLean = mix(from.sproutLean, to.sproutLean)
        f.morphed = TomoForm.Outline(points: points(at: u, wobble: wobble, phase: phase),
                                     top: mix(from.top, to.top), bottom: mix(from.bottom, to.bottom),
                                     drop: mix(from.drop, to.drop), earSpread: mix(from.earSpread, to.earSpread))
        return f
    }

    /// A moment of a birthday's morph: how far the outline has got (`u`, past 1 on the spring), its wobble and the
    /// wobble's turn, how much taller Tomo is drawn (`stretch`), its glow, and how much of the old form still shows over
    /// the new one (Reduce Motion's crossfade; 0 otherwise).
    public struct Beat: Sendable, Equatable {
        public var u: CGFloat = 1, wobble: CGFloat = 0, phase: CGFloat = 0, stretch: CGFloat = 1
        public var glow: CGFloat = 0, fade: CGFloat = 0
    }

    /// `e` seconds into a morph `length` long (a birthday's is 1.2 s), as the states lab's Flubber option plays it: the
    /// outline springs to the new one a sixth of the way in, 16% past it at a third and back under, wobbling 6% four
    /// times round as the wobble dies away, while Tomo stretches up and down by up to 5%.
    public static func flubber(_ e: Double, length: Double) -> Beat {
        let q = min(max(e / length, 0), 1)
        let u = q >= 1 ? 1 : 1 - exp(-5.5 * q) * cos(3 * .pi * q)
        return Beat(u: CGFloat(u), wobble: CGFloat(0.06 * (1 - q)), phase: CGFloat(e * 16),
                    stretch: CGFloat(1 + 0.05 * sin(.pi * q) * sin(e * 14)))
    }

    /// Reduce Motion's (0.9 s): the new form fades in over the old, eased in and out, with a soft glow (half at the middle).
    public static func crossfade(_ e: Double, length: Double) -> Beat {
        let q = min(max(e / length, 0), 1)
        let u = q < 0.5 ? 4 * q * q * q : 1 - pow(2 - 2 * q, 3) / 2
        return Beat(glow: CGFloat(0.5 * sin(.pi * q)), fade: CGFloat(1 - u))
    }

    /// Its health over a birthday's frames: the Flubber beats every thirtieth of the way, wobble and overshoot included.
    public func health() -> TomoMorph.Health {
        outline.health((0...30).map { i in
            let b = Self.flubber(1.2 * Double(i) / 30, length: 1.2)
            return points(at: b.u, wobble: b.wobble, phase: b.phase)
        })
    }
}

extension TomoForm {
    /// A morph's outline standing in for the form's own (`TomoFormMorph.form(at:)`), in units of R, with how far it
    /// reaches up and down, how far its body sits below the middle, and how far apart its ears stand.
    struct Outline: Sendable {
        let points: [CGPoint]
        let top: CGFloat
        let bottom: CGFloat
        let drop: CGFloat
        let earSpread: CGFloat
    }

    /// How far the body sits below its middle, in units of R: a droplet carries its point above, so it sits 0.18 lower.
    var drop: CGFloat { morphed?.drop ?? (silhouette == .droplet ? 0.18 : 0) }
    /// How far apart a pair of ears or horns stands, as a share of rx: closer together on a triangle's narrow top.
    var earSpread: CGFloat { morphed?.earSpread ?? (silhouette == .triangle ? 0.3 : 0.58) }
}

// MARK: - Checks (TOMO_SELFTEST, TOMO_RENDER_EVOLUTION)

extension TomoFormMorph {
    /// The eight seeds the evolution renders show (TOMO_RENDER_EVOLUTION).
    public static let seeds = (0..<8).map { "variety-\($0)" }

    /// Every silhouette, each pinned by its band's middle.
    public static var silhouettes: [(TomoForm.Silhouette, Double)] {
        var last = 0.0
        return TomoForm.bands.map { band in
            defer { last = band.1 }
            return (band.0, (last + band.1) / 2)
        }
    }

    /// `seed`'s Tomo at 3さい in `a`, growing into 4さい in `b`: every pair, the same shape twice included.
    public static func pair(_ seed: String, _ a: TomoForm.Silhouette, _ b: TomoForm.Silhouette) -> TomoFormMorph {
        let at = Dictionary(uniqueKeysWithValues: silhouettes.map { ($0.0, $0.1) })
        let look = TomoLook(seed: seed, overrides: ["age2.shape": at[a] ?? 0, "age3.shape": at[b] ?? 0],
                            newShapeEachAge: false)
        return TomoFormMorph(look.form(2), look.form(3))
    }

    /// Every pair of silhouettes for each seed, measured: how many morphs there were, the ones that aren't sound, and
    /// the farthest turn, largest twist and biggest speck of any.
    public static func survey(seeds: [String] = seeds)
        -> (count: Int, unsound: [String], farthest: CGFloat, twist: CGFloat, speck: CGFloat) {
        var count = 0, unsound: [String] = [], farthest: CGFloat = 0, twist: CGFloat = 0, speck: CGFloat = 0
        for seed in seeds {
            for (a, _) in silhouettes {
                for (b, _) in silhouettes {
                    let h = pair(seed, a, b).health()
                    count += 1
                    farthest = max(farthest, h.farthest)
                    twist = max(twist, abs(h.twist))
                    speck = max(speck, h.speck)
                    if !h.sound {
                        unsound.append(String(format: "%@ %@→%@ (tangled %d, flipped %d, turn %.0f°, twist %.0f°)", seed,
                                              a.rawValue, b.rawValue, h.tangled, h.flipped, h.farthest * 180 / .pi,
                                              h.twist * 180 / .pi))
                    }
                }
            }
        }
        return (count, unsound, farthest, twist, speck)
    }

    /// The survey's result, in words: every pair of shapes for `seeds` morphs cleanly, or the first that don't.
    public static func surveyReport(seeds: [String] = seeds) -> (passed: Bool, words: String) {
        let s = survey(seeds: seeds)
        return (s.unsound.isEmpty,
                String(format: "every pair of shapes morphs cleanly for %d seeds (%d morphs: no tangle or flip, the biggest "
                       + "speck %.5f%% of the body; points turn %.0f° at most, the whole outline %.1f°)%@", seeds.count,
                       s.count, s.speck * 100, s.farthest * 180 / .pi, s.twist * 180 / .pi,
                       s.unsound.isEmpty ? "" : ": " + s.unsound.prefix(4).joined(separator: "; ")))
    }

    /// The morph itself, on its own: every pair of silhouettes for two seeds (TOMO_RENDER_EVOLUTION surveys all eight;
    /// here it would add seconds) and every real birthday of the eight holds together (no tangle, no flip, no spin), and
    /// the ends are the forms themselves.
    static func selfTest(_ check: (Bool, String) -> Void) {
        let s = surveyReport(seeds: Array(seeds.prefix(2)))
        check(s.passed, s.words)
        var births = 0, bad: [String] = []
        for seed in seeds + ["mascot"] {
            let look = seed == "mascot" ? TomoLook.mascot : TomoLook(seed: seed)
            for age in 1..<TomoLook.ages {
                births += 1
                if !TomoFormMorph(look.form(age - 1), look.form(age)).health().sound { bad.append("\(seed) \(age)") }
            }
        }
        check(bad.isEmpty, "every birthday's morph holds together (\(births) birthdays)\(bad.isEmpty ? "" : ": " + bad.joined(separator: ", "))")

        let look = TomoLook(seed: seeds[3]), m = TomoFormMorph(look.form(1), look.form(2))
        let ends = m.form(at: 0).path(R: 1) == look.form(1).path(R: 1) && m.form(at: 1).path(R: 1) == look.form(2).path(R: 1)
        let counts = m.outline.from.count == m.outline.to.count && m.outline.from.count >= 100
        let wound = TomoMorph.area(m.outline.from) < 0 && TomoMorph.area(m.outline.to) < 0
        check(ends && counts && wound, "a morph starts and ends on the forms themselves, point for point, wound the same way "
              + "(\(m.outline.from.count) points)")
        let lab = flubber(0.2, length: 1.2), peak = flubber(0.4, length: 1.2), end = flubber(1.2, length: 1.2)
        let fade = crossfade(0.45, length: 0.9)
        check(abs(lab.u - 1) < 0.001 && abs(peak.u - 1.16) < 0.01 && end.u == 1 && end.wobble == 0 && abs(end.stretch - 1) < 1e-9
              && abs(fade.fade - 0.5) < 0.001 && abs(fade.glow - 0.5) < 0.001,
              "the morph keeps the states lab's timing: the new outline at 0.2 s, 16% past it at 0.4 s, settled at 1.2 s; "
              + "Reduce Motion's crossfade half way and glowing most at 0.45 s")
    }
}

extension TomoBlob {
    /// A birthday's morph on Tomo, on a scripted clock: whatever plays over it part way (a level-up, being pulled up, the
    /// next birthday), it plays on to its end and lands on the new form, in the lively morph and in Reduce Motion's
    /// crossfade, with no frame standing still; jumping straight to an age ends it at once; and a birthday that passed
    /// unseen just has the new form.
    static func morphSelfTest(_ check: (Bool, String) -> Void) {
        let look = TomoLook(seed: TomoFormMorph.seeds[3])
        /// A birthday into 2さい at 100 s, then `interrupt` `half` seconds in, and 60 frames a second for 3 s. What went
        /// wrong, if anything: the morph stopped early, a frame stood still, its last frame was a jump away from the new
        /// outline (a pop at the end), or it didn't land on `target`'s own form.
        func run(calm: Bool, _ name: String, at half: Double, _ interrupt: (TomoBlob) -> Void, lands target: Int) -> [String] {
            let blob = TomoBlob(look: look, material: .classic)
            blob.reduceMotion = calm
            var t = 100.0
            blob.clock = { t }
            blob.step()
            blob.setGrowth(1)
            blob.grow(to: 2)
            let length = calm ? 0.9 : 1.2, what = "\(calm ? "Reduce Motion" : "lively"), \(name)"
            var start = 100.0, from = 1, interrupted = false, landed = false
            var problems: [String] = [], still = 0, last: [CGPoint] = [], lastFade: CGFloat = -1
            for i in 1...(60 * 3) {
                t = 100 + Double(i) / 60
                if !interrupted, t >= 100 + half {
                    interrupted = true
                    let before = blob.age
                    interrupt(blob)
                    if blob.age != before { start = t; from = before }    // a new birthday: a new morph, from here
                }
                blob.step()
                let frame = blob.morphFrame(t), e = t - start
                if e < length - 0.001 {
                    guard let frame else { problems.append(String(format: "%@: stopped at %.2f s", what, e)); break }
                    if calm {
                        let fade = frame.old?.alpha ?? -1
                        if fade == lastFade { still += 1 }
                        lastFade = fade
                    } else {
                        let points = frame.form.morphed?.points ?? []
                        if points == last { still += 1 }
                        last = points
                    }
                } else if e > length + 0.001 {
                    landed = frame == nil && blob.age == target
                    break
                }
            }
            if still > 0 { problems.append("\(what): \(still) frames stood still") }
            if !landed { problems.append("\(what): didn't land on age \(target)'s form") }
            let ends = TomoFormMorph(look.form(from), look.form(target)).outline.to
            let gap = calm ? max(lastFade, 0)
                : zip(last, ends).map { TomoMorph.distance($0, $1) }.max() ?? .infinity
            if gap > 0.01 { problems.append(String(format: "%@: its last frame was %.3f from the new form", what, gap)) }
            return problems
        }
        var problems: [String] = []
        for calm in [false, true] {
            let half = calm ? 0.45 : 0.6
            problems += run(calm: calm, "on its own", at: 99, { _ in }, lands: 2)
            problems += run(calm: calm, "a level-up", at: half, { $0.levelUp() }, lands: 2)
            problems += run(calm: calm, "pulled up", at: half, { $0.pullUp() }, lands: 2)
            problems += run(calm: calm, "the next birthday", at: half, { $0.grow(to: 3) }, lands: 3)
        }
        check(problems.isEmpty, "a birthday's morph plays on through a level-up, being pulled up or the next birthday and "
              + "lands on the new form, lively and under Reduce Motion, with no frame standing still"
              + (problems.isEmpty ? "" : ": " + problems.joined(separator: "; ")))

        let blob = TomoBlob(look: look, material: .classic)
        var t = 100.0
        blob.clock = { t }
        blob.step()
        blob.setGrowth(1)
        blob.grow(to: 2)
        t = 100.6
        blob.step()
        let playing = blob.morphFrame(t) != nil
        blob.setGrowth(3)
        let jumped = blob.morphFrame(t) == nil && blob.age == 3
        blob.grow(to: 4)
        t = 106                                        // the window hidden through the whole birthday
        blob.step()
        check(playing && jumped && blob.morphFrame(t) == nil && blob.age == 4,
              "jumping straight to an age ends a birthday's morph at once, and a birthday that passed unseen just has the new form")
    }
}
