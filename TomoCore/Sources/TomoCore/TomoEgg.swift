import SwiftUI

// MARK: - The egg (#258)
//
// The speckled egg in the colours of the Tomo inside it: the first run hatches Tomo from it (`TomoEggView`), and Tomo
// can go back into it and hatch again (`TomoBlob.inEgg`, the states lab's Shell option). Both draw it from here, so
// they're the same egg. It's fixed fills in code: an egg outline, seeded speckles in Tomo's body and accent colours, a
// shine, an outline and a zigzag crack.

public enum TomoEgg {
    /// From the first tap to the shell splitting open.
    public static let crackTime = 0.9

    /// How far above its place the top half starts as it drops on round Tomo, in egg heights (the lab's Shell).
    static let dropFrom: CGFloat = 1.1

    /// How the egg is drawn in one frame, around where it stands: its shell's opacity, how far it's tipped and lifted,
    /// how much of its crack shows, and its halves when they move apart (to close round Tomo, or to let it out).
    struct Frame {
        var alpha: CGFloat = 1
        var rot: CGFloat = 0
        var hop: CGFloat = 0                // up off the floor, in egg widths
        var crack: CGFloat = 0              // how much of the crack shows, 0…1
        var split: CGFloat?                 // the halves flying apart, 0…1 (the hatch)
        var top: Half?                      // the top half off its place (closing round Tomo)
        var bottom: Half?
        var clipFloor = false               // nothing below the floor shows (a half rising out of it)
        var resting = false                 // in its shell: it rocks, breathes and peeks (`TomoBlob`)

        struct Half { var dy: CGFloat = 0; var alpha: CGFloat = 1 }     // dy in egg heights
    }

    /// The egg's outline, `w` wide and `h` tall, centred on the origin: narrower at the top.
    static func path(width w: CGFloat, height h: CGFloat) -> Path {
        var p = Path()
        let n = 64
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let up = sin(a)                                         // 1 at the top
            let x = w / 2 * cos(a) * (1 - 0.14 * up)
            let y = -h / 2 * up
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }

    /// Where the crack runs across an egg `h` tall: a little above its middle.
    static func crackY(height h: CGFloat) -> CGFloat { -h * 0.04 }

    /// The zigzag crack across the egg, left to right.
    static func crackLine(width w: CGFloat, y: CGFloat) -> Path {
        var p = Path()
        let teeth = 7
        p.move(to: CGPoint(x: -w * 0.56, y: y))
        for i in 1...teeth {
            let x = -w * 0.56 + w * 1.12 * CGFloat(i) / CGFloat(teeth)
            p.addLine(to: CGPoint(x: x, y: y + (i % 2 == 0 ? -1 : 1) * w * 0.07))
        }
        return p
    }

    /// The part of the shell above (or below) the crack.
    static func half(crackY: CGFloat, width w: CGFloat, height h: CGFloat, top: Bool) -> Path {
        var p = crackLine(width: w, y: crackY)
        let edge = top ? -h : h
        p.addLine(to: CGPoint(x: w, y: crackY))
        p.addLine(to: CGPoint(x: w, y: edge))
        p.addLine(to: CGPoint(x: -w, y: edge))
        p.addLine(to: CGPoint(x: -w, y: crackY))
        p.closeSubpath()
        return p
    }

    /// Seven speckles placed from the seed (x, y in egg widths and heights from the centre; r in egg widths).
    static func spots(seed: String) -> [(x: CGFloat, y: CGFloat, r: CGFloat)] {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        func next() -> CGFloat {
            h ^= h << 13; h ^= h >> 7; h ^= h << 17
            return CGFloat(h % 10_000) / 10_000
        }
        return (0..<7).map { _ in (x: (next() - 0.5) * 0.8, y: (next() - 0.5) * 0.8, r: 0.05 + next() * 0.07) }
    }

    /// The shell, centred on the origin: a cream gradient, the look's speckles (`spots`, or worked out from its seed),
    /// a soft shine top left, and an outline `outline` wide.
    static func drawShell(_ ctx: GraphicsContext, _ egg: Path, width w: CGFloat, height h: CGFloat, look: TomoLook,
                          outline: CGFloat, spots kept: [(x: CGFloat, y: CGFloat, r: CGFloat)]? = nil) {
        ctx.fill(egg, with: .linearGradient(Gradient(colors: [Color(hex: "#FFF9EC"), Color(hex: "#EBDDC3")]),
                                            startPoint: CGPoint(x: -w * 0.3, y: -h * 0.5),
                                            endPoint: CGPoint(x: w * 0.3, y: h * 0.5)))
        var inside = ctx
        inside.clip(to: egg)
        for (i, s) in (kept ?? spots(seed: look.seed)).enumerated() {
            let r = s.r * w
            let rect = CGRect(x: s.x * w - r, y: s.y * h - r, width: r * 2, height: r * 2)
            inside.fill(Path(ellipseIn: rect), with: .color((i % 3 == 0 ? look.accent : look.body).opacity(0.85)))
        }
        inside.fill(Path(ellipseIn: CGRect(x: -w * 0.32, y: -h * 0.38, width: w * 0.2, height: h * 0.16)),
                    with: .color(.white.opacity(0.55)))
        ctx.stroke(egg, with: .color(Color(hex: "#C9B48F").opacity(0.6)), lineWidth: outline)
    }

    /// The crack, `shown` of the way across, kept on the shell.
    static func drawCrack(_ ctx: GraphicsContext, _ egg: Path, width w: CGFloat, y: CGFloat, shown: CGFloat,
                          lineWidth: CGFloat) {
        guard shown > 0 else { return }
        var shell = ctx
        shell.clip(to: egg)
        shell.stroke(crackLine(width: w, y: y).trimmedPath(from: 0, to: min(1, shown)), with: .color(Color(hex: "#7A5F3A")),
                     style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// How solid the shell's halves are, `k` of the way through the hatch's split (0…1): solid until its last seventh
    /// (0.1 s of the 0.7 s, six frames), when both have sunk most of the way into the floor beside and under Tomo's
    /// foot, so half-faded cream never hangs round Tomo as a grey smudge on a dark card or the first run's dark page.
    static func splitSolid(_ k: CGFloat) -> CGFloat { 1 - min(1, max(0, (k - 6 / 7) * 7)) }

    /// The hatch's halves flying apart, `k` of the way (0…1), both solid (`splitSolid`) and gone below the floor (the
    /// egg's foot) by the end. The top pops up a little (no higher than it ever did, so it stays in Tomo's room) and
    /// tumbles off to the side, no further than the first run's egg frame keeps, then down into the floor; the bottom
    /// sinks into it, as it rose from it going in. `ctx` is at the egg's centre.
    static func drawSplit(_ ctx: GraphicsContext, k: CGFloat, width w: CGFloat, height h: CGFloat,
                          shell: (GraphicsContext) -> Void) {
        let y = crackY(height: h), solid = Double(splitSolid(k))
        var above = ctx
        above.clip(to: Path(CGRect(x: -w * 4, y: -h * 4, width: w * 8, height: h * 4.5)))     // above the floor
        above.opacity *= solid
        var top = above
        top.translateBy(x: w * 0.34 * k * (2 - k), y: h * (-1.8 * k + 3.1 * k * k))      // up 0.26 h at most, then down
        top.rotate(by: .radians(Double(1.3 * k)))
        top.clip(to: half(crackY: y, width: w, height: h, top: true))
        shell(top)
        var bottom = above
        bottom.translateBy(x: 0, y: h * 0.62 * k * k)
        bottom.clip(to: half(crackY: y, width: w, height: h, top: false))
        shell(bottom)
    }
}
