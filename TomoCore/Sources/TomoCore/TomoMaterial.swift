import SwiftUI

// MARK: - What Tomo is made of
//
// A material is how a Tomo is drawn and how it moves: a pass over its body, its springs, and its hello. It belongs to
// a character, beside its look (TomoLook.swift), and the character's host passes it into TomoBlob, which never picks
// one itself (docs/architecture.md, "Character"). The learner's own Tomo is jelly (`own`); the mascot and the renders
// that ship as files (the widgets' and the Live Activity's frame font, the icons) are classic, today's look.
// #137's other three directions (lit clay, paper cut and lantern, in docs/reference/tomo/motion-directions.html) are
// kept for other friends. Each would be a case here, with its pass (`drawInside`), its springs (`springs`) and its
// hello (`TomoBlob.helloCue`).

public enum TomoMaterial: String, CaseIterable, Sendable {
    /// Tomo as it was before #137: a soft gradient body with a shade along the bottom, on firm springs, and no hello.
    /// It never changes, because the widgets' frame font is rendered from it.
    case classic
    /// Wet, glossy and lit from inside: a light rising from its bottom, an inner rim and two highlights (fixed fills,
    /// no blur), on loose springs that overshoot and wobble. The amber call and a moment's light glow from inside it. Its
    /// hello is a drop that falls from the notch and gathers into Tomo.
    case jelly

    /// The learner's own Tomo's material (decisions.md, 2026-10-11). Hosts that show it pass this in; a friend would pass
    /// its own.
    public static let own: TomoMaterial = .jelly

    /// TOMO_MATERIAL=classic|jelly: the material of the renders that check Tomo's look and motion (TOMO_RENDER_ANIM, the
    /// sheets); the learner's own otherwise. The icons and the card frames are always classic.
    public static var forRenders: TomoMaterial {
        ProcessInfo.processInfo.environment["TOMO_MATERIAL"].flatMap(TomoMaterial.init(rawValue:)) ?? own
    }
}

// MARK: Springs

extension TomoMaterial {
    /// How Tomo's springs give: the ears or sprout swaying behind the body's moves, and the body's own wobble after a hop,
    /// a landing or a poke. `w` is the stiffness (rad/s) and `z` the damping (1: no overshoot).
    struct Springs: Equatable {
        var swayW: CGFloat, swayZ: CGFloat
        var wobbleW: CGFloat, wobbleZ: CGFloat
        /// How much a fall or a rise sets the body wobbling.
        var lift: CGFloat
        /// The wobble's limit: this much taller (and half as much narrower), or shorter.
        var most: CGFloat
        /// A landing's or a poke's kick to the body, times this.
        var kick: CGFloat
    }

    var springs: Springs {
        switch self {
        case .classic:
            return Springs(swayW: 18, swayZ: 0.18, wobbleW: 22, wobbleZ: 0.2, lift: 0.9, most: 0.12, kick: 1)
        case .jelly:      // looser and less damped: it overshoots further and wobbles about twice as long
            return Springs(swayW: 15, swayZ: 0.12, wobbleW: 15, wobbleZ: 0.13, lift: 1.4, most: 0.18, kick: 1.4)
        }
    }
}

// MARK: Light from inside

extension TomoMaterial {
    /// The light inside Tomo this frame, each 0…1: the call glow's amber (`TomoBlob.callGlow`, pulsing) and a moment's
    /// gold (the hello's).
    struct Glow {
        var call: CGFloat = 0
        var shine: CGFloat = 0
    }

    static let amber = Color(hex: "#F2B04A")       // the call glow's and the countdown line's amber
    static let gold = Color(hex: "#FFC83D")        // the star eyes' gold

    /// The material's pass over the body, drawn inside it (`ctx` is clipped to `body`), after its markings and before a
    /// big moment's white glow. In Tomo's own coordinates: its centre at the origin, `top` and `bottom` its edges.
    /// Classic draws nothing here.
    func drawInside(_ ctx: GraphicsContext, form: TomoForm, body: Path, R: CGFloat, top: CGFloat, bottom: CGFloat,
                    glow: Glow) {
        guard self == .jelly else { return }
        let all = CGRect(x: -R * 2, y: top - R, width: R * 4, height: bottom - top + R * 2)
        // A light rising from its bottom, as if lit from inside.
        let low = CGPoint(x: 0, y: bottom - R * 0.35)
        ctx.fill(Path(all), with: .radialGradient(Gradient(colors: [.white.opacity(0.3), .white.opacity(0)]),
                                                 center: low, startRadius: R * 0.05, endRadius: R * 1.3))
        // The call's amber and a moment's gold glow from its middle, brightening it (screened, so a blue Tomo turns
        // lighter, not green).
        let mid = CGPoint(x: 0, y: (top + bottom) / 2)
        var lit = ctx
        lit.blendMode = .screen
        for (color, a) in [(Self.amber, glow.call), (Self.gold, glow.shine)] where a > 0.01 {
            lit.fill(Path(all), with: .radialGradient(Gradient(colors: [color.opacity(Double(0.75 * a)), color.opacity(0)]),
                                                     center: mid, startRadius: 0, endRadius: R * 1.25))
        }
        // A thin inner rim, where the jelly is thinnest (half the stroke shows, inside the clip).
        ctx.stroke(body, with: .color(.white.opacity(0.17)), lineWidth: R * 0.12)
        // Two highlights, high on its left, over the widest part of it that's above the face (on a triangle or a droplet,
        // lower than the top), and clear of the mark some Tomos get at 6さい.
        let x = -R * 0.36 * min(1, form.faceW / 0.8), y = max(top + R * 0.3, (form.faceY - 0.66) * R)
        var shine = ctx
        shine.translateBy(x: x, y: y)
        shine.rotate(by: .radians(-0.55))
        shine.fill(Path(ellipseIn: CGRect(x: -R * 0.21, y: -R * 0.1, width: R * 0.42, height: R * 0.2)),
                   with: .color(.white.opacity(0.72)))
        shine.fill(Path(ellipseIn: CGRect(x: R * 0.295, y: R * 0.025, width: R * 0.09, height: R * 0.09)),
                   with: .color(.white.opacity(0.9)))
    }

    /// The hello's drop (jelly): a bead of Tomo's colour with its tail pulled up behind it, `r` across, at `c`; `stretch`
    /// is how long the tail is, in radii (longer as it falls faster).
    func drawDrop(_ ctx: GraphicsContext, at c: CGPoint, r: CGFloat, stretch: CGFloat, look: TomoLook) {
        guard r > 0.2 else { return }
        var drop = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 1.15, width: r * 2, height: r * 2.3))
        var tail = Path()
        tail.move(to: CGPoint(x: c.x - r * 0.72, y: c.y - r * 0.55))
        tail.addQuadCurve(to: CGPoint(x: c.x + r * 0.72, y: c.y - r * 0.55),
                          control: CGPoint(x: c.x, y: c.y - r * (0.55 + 2 * stretch)))
        drop.addPath(tail)
        ctx.fill(drop, with: .linearGradient(Gradient(colors: [look.bodyLight, look.body]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r * 1.5), endPoint: CGPoint(x: c.x, y: c.y + r)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.5, height: r * 0.36)),
                 with: .color(.white.opacity(0.75)))
    }
}
