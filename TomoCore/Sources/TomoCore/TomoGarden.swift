import SwiftUI

// MARK: - The word garden (#137 item 2, Stats Take Two's direction 2)
//
// Every word the learner has met is a plant (`TomoStats.garden`), planted when it was first answered right and grown to
// its stage: a sprout while Tomo has just heard it, leaves once it knows it, a bud when it's good at it, a flower when it
// loves it, and a gold star on the flower for forever. A word that slipped turns pale (the bar's rule) and never wilts.
// Words met or grown in the chosen range glow, and the ones practiced get watered, so a Win (green) and Practice (blue)
// read without words. The first words are at the back and the newest at the front, and Tomo strolls along the front.
// Tapping a plant shows its word. The replay grows the garden again from the first day, from the answer log. It's all
// drawn live in a Canvas: plants sway, drops fall; under Reduce Motion nothing sways or falls and Tomo stays put, still
// breathing. Words not met yet aren't planted, so nothing in the garden is waiting to be done.

/// The garden's colours, light and dark (the stats page's palette).
struct TomoGardenColors {
    let groundTop, groundBottom, bed, furrow, soil, leaf, leaf2, pale, bud, petal, gold, win, practice, ink, muted: Color

    init(dark: Bool) {
        func c(_ light: String, _ night: String) -> Color { Color(hex: dark ? night : light) }
        groundTop = c("#E4EFD9", "#1D2A1E"); groundBottom = c("#CFE2C1", "#233424")
        bed = c("#D9C7AA", "#3B3226"); furrow = c("#C7B293", "#4A3F31"); soil = c("#A8865F", "#6B5640")
        leaf = c("#3F9A3A", "#5FC155"); leaf2 = c("#76C863", "#93DD7F"); pale = c("#C4D8B4", "#3F4D3A")
        bud = c("#E98DB6", "#E98DB6"); petal = c("#FFB8D4", "#F7A9C9"); gold = c("#FFC83D", "#FFC83D")
        win = c("#4CC27F", "#4CC27F"); practice = c("#66A2F3", "#66A2F3")
        ink = c("#1B1D25", "#ECEDF2"); muted = c("#6A6F80", "#9A9FAF")
    }
}

/// One plant, drawn at its stage: `at` is where it meets the soil, `size` its height scale.
enum TomoPlantDrawing {
    /// The stage's group: 0 just heard (1–4), 1 knows it (5–6), 2 good at it (7), 3 loves it (8), 4 forever (9).
    static func group(_ stage: Int) -> Int { stage <= 4 ? 0 : stage <= 6 ? 1 : stage == 7 ? 2 : stage == 8 ? 3 : 4 }

    static func draw(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, stage: Int, sway: Double, pale: Bool,
                     grow: CGFloat = 1, colors c: TomoGardenColors) {
        guard grow > 0, stage > 0 else { return }
        let s = s * grow
        var g = ctx
        g.translateBy(x: p.x, y: p.y)
        g.fill(Path(ellipseIn: CGRect(x: -s * 0.3, y: -s * 0.08, width: s * 0.6, height: s * 0.16)), with: .color(c.soil))
        g.rotate(by: .radians(sway))
        let leaf = pale ? c.pale : c.leaf, leaf2 = pale ? c.pale : c.leaf2
        func leafAt(_ y: CGFloat, _ len: CGFloat, _ angle: Double, _ color: Color) {
            var l = g
            l.translateBy(x: 0, y: y)
            l.rotate(by: .radians(angle))
            l.fill(Path(ellipseIn: CGRect(x: 0, y: -len * 0.22, width: len, height: len * 0.44)), with: .color(color))
        }
        let kind = group(stage)
        if kind == 0 {
            let h = s * (0.1 + 0.03 * CGFloat(stage)), len = s * (0.13 + 0.03 * CGFloat(stage))
            g.stroke(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 0, y: -h)) }, with: .color(leaf),
                     style: StrokeStyle(lineWidth: max(1, s * 0.04), lineCap: .round))
            leafAt(-h, len, -2.5, leaf2)
            leafAt(-h, len, -0.64, leaf)
            return
        }
        let h = s * (kind == 1 ? 0.46 : kind == 2 ? 0.6 : 0.72)
        g.stroke(Path { $0.move(to: .zero); $0.addQuadCurve(to: CGPoint(x: 0, y: -h), control: CGPoint(x: s * 0.05, y: -h * 0.5)) },
                 with: .color(leaf), style: StrokeStyle(lineWidth: max(1.2, s * 0.05), lineCap: .round))
        for k in 0..<(kind == 1 ? 2 : 3) {
            let y = -h * (0.3 + 0.28 * CGFloat(k)), len = s * (0.26 - 0.04 * CGFloat(k))
            leafAt(y, len, -2.6 + Double(k) * 0.1, k % 2 == 1 ? leaf : leaf2)
            leafAt(y, len, -0.55 - Double(k) * 0.1, k % 2 == 1 ? leaf2 : leaf)
        }
        if kind == 2 {
            g.fill(Path(ellipseIn: CGRect(x: -s * 0.07, y: -h - s * 0.16, width: s * 0.14, height: s * 0.2)), with: .color(c.bud))
        }
        if kind >= 3 {
            for k in 0..<5 {
                let a = Double(k) * 2 * .pi / 5, r = s * 0.08
                let center = CGPoint(x: cos(a) * s * 0.09, y: -h + sin(a) * s * 0.09)
                g.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(c.petal))
            }
            let r = s * 0.06
            g.fill(Path(ellipseIn: CGRect(x: -r, y: -h - r, width: r * 2, height: r * 2)), with: .color(c.gold))
        }
        if kind == 4 { g.fill(star(at: CGPoint(x: 0, y: -h - s * 0.2), r: s * 0.07), with: .color(c.gold)) }
    }

    /// A four-point star (forever, and the glow's sparkle).
    static func star(at p: CGPoint, r: CGFloat) -> Path {
        Path { path in
            for k in 0..<8 {
                let a = Double(k) * .pi / 4 - .pi / 2, d = k % 2 == 0 ? r : r * 0.4
                let q = CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d)
                if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
        }
    }
}

/// Where each plant goes: rows of the bed, oldest at the back, with a little jitter so it reads as planted by hand.
struct TomoGardenLayout {
    struct Spot { let id: String; let x: CGFloat; let y: CGFloat; let cell: CGFloat; let phase: Double }
    let spots: [Spot]
    /// The bed, as a share of the field: x, y, width, height.
    static let bed = CGRect(x: 0.04, y: 0.16, width: 0.92, height: 0.78)

    init(ids: [String], size: CGSize, tall: Bool) {
        let b = Self.bed, n = max(ids.count, 1)
        let aspect = (b.width * size.width) / max(b.height * size.height, 1)
        let cols = max(3, Int((Double(n) * aspect).squareRoot().rounded())), rows = Int(ceil(Double(n) / Double(cols)))
        let cellW = b.width * size.width / CGFloat(cols), cellH = b.height * size.height / CGFloat(rows)
        spots = ids.enumerated().map { k, id in
            let r = k / cols, c = k % cols, j = CGFloat(Self.jitter(id))
            let x = b.minX + b.width * ((CGFloat(c) + 0.5 + (r % 2 == 1 ? 0.2 : -0.1) + j * 0.18) / CGFloat(cols))
            let y = b.minY + b.height * ((CGFloat(r) + 0.85) / (CGFloat(rows) + 0.2))
            return Spot(id: id, x: min(max(x, b.minX + 0.01), b.maxX - 0.01), y: y,
                        cell: min(cellW, cellH * (tall ? 1.25 : 0.7)), phase: Double(j) * 6)
        }
    }

    /// A steady 0…1 for a word, from its id.
    static func jitter(_ id: String) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Double(h % 10_000) / 10_000
    }
}

/// The garden itself: the bed, the plants at time `at` (nil: now), glowing and watered by the range, Tomo strolling, and
/// the word card of a tapped plant.
struct TomoGardenField: View {
    let plants: [TomoStats.Plant]
    let glowing: Set<String>
    let watered: Set<String>
    let at: Date?
    let look: TomoLook
    let material: TomoMaterial
    let growth: CGFloat
    let tall: Bool
    let emptyNote: String
    @Binding var selected: String?
    @ObservedObject private var motion = TomoMotion.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size, layout = TomoGardenLayout(ids: plants.map(\.id), size: size, tall: tall)
            let byID = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
            ZStack(alignment: .bottomLeading) {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: motion.reduce && watered.isEmpty)) { tl in
                    Canvas { ctx, sz in
                        draw(ctx, size: sz, layout: layout, plants: byID, t: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                TomoGardenStroller(look: look, material: material, growth: growth, width: size.width)
                    .frame(height: min(size.width * (tall ? 0.24 : 0.2), 110))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                let near = layout.spots.filter { spot in byID[spot.id].map { stage($0) > 0 } ?? false }.min {
                    hypot($0.x * size.width - p.x, $0.y * size.height - p.y) < hypot($1.x * size.width - p.x, $1.y * size.height - p.y)
                }
                if let near, hypot(near.x * size.width - p.x, (near.y - 0.03) * size.height - p.y) < max(34, near.cell) {
                    selected = near.id
                } else {
                    selected = nil
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    /// A plant's stage where the garden is in time: now, its stage now; in the replay, its stage then.
    private func stage(_ plant: TomoStats.Plant) -> Int { at.map(plant.stage(at:)) ?? plant.stage }

    private func draw(_ ctx: GraphicsContext, size: CGSize, layout: TomoGardenLayout, plants: [String: TomoStats.Plant],
                      t: Double) {
        let c = TomoGardenColors(dark: scheme == .dark), calm = motion.reduce
        let W = size.width, H = size.height, b = TomoGardenLayout.bed
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [c.groundTop, c.groundBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        let bedRect = CGRect(x: b.minX * W, y: (b.minY - 0.04) * H, width: b.width * W, height: (b.height + 0.05) * H)
        ctx.fill(Path(roundedRect: bedRect, cornerRadius: 14), with: .color(c.bed))
        var y = b.minY + 0.04
        while y < b.maxY {
            ctx.stroke(Path { $0.move(to: CGPoint(x: bedRect.minX + 10, y: y * H)); $0.addLine(to: CGPoint(x: bedRect.maxX - 10, y: y * H)) },
                       with: .color(c.furrow), lineWidth: 1)
            y += 0.07
        }
        guard !plants.isEmpty else {
            // An empty bed: a little mound of soil where the first sprout goes, and a word about it.
            ctx.fill(Path(ellipseIn: CGRect(x: W * 0.55 - 12, y: H * 0.55 - 5, width: 24, height: 10)), with: .color(c.soil))
            ctx.draw(Text(emptyNote).font(.system(size: 13, weight: .medium)).foregroundStyle(c.muted),
                     at: CGPoint(x: W * 0.55, y: H * 0.55 + 24))
            return
        }
        let sorted = layout.spots.sorted { $0.y < $1.y }
        for spot in sorted {
            guard let plant = plants[spot.id] else { continue }
            let stage = stage(plant)
            guard stage > 0 else { continue }
            let x = spot.x * W, py = spot.y * H, s = spot.cell * (0.85 + 0.45 * spot.y) * 1.4
            let grow: CGFloat = at.map { CGFloat(min(max($0.timeIntervalSince(plant.met) / (36 * 3600), 0.15), 1)) } ?? 1
            if at == nil, glowing.contains(spot.id) {
                let pulse = calm ? 0.5 : 0.42 + 0.16 * sin(t * 2 + spot.phase)
                let center = CGPoint(x: x, y: py - s * 0.3), r = s * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [c.win.opacity(pulse), c.win.opacity(0)]), center: center,
                                               startRadius: 1, endRadius: r))
                var sparkle = ctx
                sparkle.opacity = calm ? 0.8 : 0.5 + 0.5 * sin(t * 3 + spot.phase * 2)
                sparkle.fill(TomoPlantDrawing.star(at: CGPoint(x: x + s * 0.22, y: py - s * 0.82), r: max(2.5, s * 0.07)),
                             with: .color(c.gold))
            }
            let sway = calm || plants.count > 600 ? 0 : sin(t * 1.3 + spot.phase) * 0.06
            TomoPlantDrawing.draw(ctx, at: CGPoint(x: x, y: py), size: s, stage: stage, sway: sway,
                                  pale: plant.pale && at == nil, grow: grow, colors: c)
            if selected == spot.id {
                ctx.stroke(Path(ellipseIn: CGRect(x: x - s * 0.42, y: py - s * 0.8, width: s * 0.84, height: s)),
                           with: .color(c.ink), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            if at == nil, calm, watered.contains(spot.id) {     // still, a drop beside it says it was watered
                ctx.fill(Path(ellipseIn: CGRect(x: x + s * 0.2, y: py - s * 0.5, width: 4, height: 6)), with: .color(c.practice))
            }
        }
        // Practice waters: every 0.9 s three drops fall on one of the watered plants.
        guard at == nil, !calm, !watered.isEmpty else { return }
        let ids = sorted.filter { watered.contains($0.id) }
        guard !ids.isEmpty else { return }
        let slot = Int(t / 0.9), q = (t / 0.9) - Double(slot)
        let spot = ids[Int(TomoGardenLayout.jitter("\(slot)") * Double(ids.count)) % ids.count]
        let s = spot.cell * (0.85 + 0.45 * spot.y) * 1.4
        var drops = ctx
        drops.opacity = 1 - q
        for k in -1...1 {
            let x = spot.x * W + CGFloat(k) * s * 0.12, y = spot.y * H - s * 1.1 + CGFloat(q) * s * 0.7
            drops.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: y - 3.4, width: 4.4, height: 6.8)), with: .color(c.practice))
        }
    }
}

/// Tomo strolling along the front of the garden and back, looking where it goes. Under Reduce Motion it stays at the
/// side, still breathing and blinking.
private struct TomoGardenStroller: View {
    let width: CGFloat
    @StateObject private var blob: TomoBlob
    @ObservedObject private var motion = TomoMotion.shared
    private let growth: CGFloat

    init(look: TomoLook, material: TomoMaterial, growth: CGFloat, width: CGFloat) {
        self.width = width
        self.growth = growth
        _blob = StateObject(wrappedValue: TomoBlob(look: look, material: material, motion: .shared))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate, period = 26.0
            let k = motion.reduce ? 0 : 0.5 - 0.5 * cos(2 * .pi * t / period)
            let heading = motion.reduce ? 0.3 : sin(2 * .pi * t / period) >= 0 ? 0.7 : -0.7
            GeometryReader { geo in
                let side = geo.size.height
                Canvas { ctx, size in
                    blob.frameDate = tl.date
                    blob.lookX = heading
                    blob.step()
                    blob.draw(ctx, size: size)
                }
                .frame(width: side, height: side)
                .offset(x: (width - side) * (0.04 + 0.6 * k))
            }
        }
        .onAppear { blob.setGrowth(growth) }
    }
}

/// How a word grows: the five stages as plants, with their names.
struct TomoGardenLegend: View {
    let horizontal: Bool
    @ObservedObject private var lang = TomoLanguages.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stages = [(1, "heard"), (5, "knows"), (7, "good"), (8, "loves"), (9, "forever")]
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        layout {
            ForEach(stages, id: \.0) { stage, name in
                let item = Group {
                    Canvas { ctx, size in
                        TomoPlantDrawing.draw(ctx, at: CGPoint(x: size.width / 2, y: size.height - 3), size: size.height * 1.1,
                                              stage: stage, sway: 0, pale: false, colors: TomoGardenColors(dark: scheme == .dark))
                    }
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                    Text(lang.learner("stage.\(name)")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if horizontal { VStack(spacing: 2) { item } } else { HStack(spacing: 6) { item } }
            }
        }
    }
}

/// The word of a tapped plant: its picture, the word, its reading and meaning, its stage, and when it was met.
struct TomoPlantCard: View {
    let plant: TomoStats.Plant
    let progress: TomoProgress
    let close: () -> Void
    @ObservedObject private var lang = TomoLanguages.shared

    var body: some View {
        let w = progress.word(plant.id, learner: lang.learner.id)
        HStack(alignment: .top, spacing: 10) {
            if let emoji = w.emoji { Text(emoji).font(.system(size: 30)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(w.say).font(.system(size: 20, weight: .bold, design: .rounded))
                Text([w.reading, w.meaning].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                Text([lang.learner("stage.\(TomoSRS.group(plant.stage))"), plant.pale ? lang.learner("garden.pale") : nil,
                      lang.learner("garden.met", ["date": TomoStats.shortDay(plant.met, lang.learner)])].compactMap { $0 }
                        .joined(separator: lang.learner("list.separator")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.learner("garden.close"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
