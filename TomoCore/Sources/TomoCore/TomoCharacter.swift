import SwiftUI

// MARK: - Tomo, the blob
//
// Every Tomo is a blob of its own, drawn and animated by our own code (decisions.md, 2026-10-07). What it
// looks like comes from its seed (TomoLook.swift): a colour and eyes for life, and a new form at every
// birthday. Growth is an age step, 0 = 1さい … 5 = 6さい; each birthday it squeezes down glowing and pops out
// in its next form.
// The app drives it through notifications (docs/architecture.md, "Character"): the task state
// (`AppState.effectiveState`), `.botTalk`, `.botNudge`, `.botGrow`, `.botLevelUp`, `.botGreet`, `.botGulp`,
// `.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`.
// Big moments (a level-up, a birthday, becoming another Tomo) are cue scripts: one timeline each, as data, played on
// Tomo's clock (`Cue`, `play`).
// Reduce Motion is an input (`reduceMotion`): a live Tomo follows its shell's setting (`TomoMotion`), and offline
// renders leave it off, so they never depend on the Mac that renders them.

@MainActor
public final class TomoBlob: ObservableObject {
    /// Where the cursor is, −1…1 (positive y = above Tomo).
    public var lookX: CGFloat = 0
    public var lookY: CGFloat = 0
    /// Extra canvas height above Tomo for particles (the canvas is taller than it is wide).
    public var particleOverhang: CGFloat = 0
    /// Small, decorative copy (no particles, wanders its gaze).
    public var isMini = false
    /// The time source: real time in the app, a scripted clock when rendering offline.
    public var clock: () -> Double = { CACurrentMediaTime() }
    /// Seconds with nothing happening (no cursor movement, no events) before Tomo dozes off.
    public var dozeAfter: Double = 45
    /// The frame being drawn (set by the view; reading it ties the Canvas to the frame timer).
    public var frameDate = Date()
    /// Reduce Motion: hops, shakes and wiggles become a face flash and a small puff, a big moment plays its calm script
    /// (a glow, star eyes and a puff), and particles are a third as many, and slower. Breathing, blinking and gaze stay.
    /// A live Tomo follows `motion`; offline renders set it themselves (off unless TOMO_REDUCE_MOTION=1).
    public var reduceMotion = false

    /// Whose Tomo this is. Nil: the learner's own (`TomoLook.current`), changing with a pop when it does.
    public let fixedLook: TomoLook?
    public private(set) var look: TomoLook
    /// The shell's Reduce Motion setting, followed every frame: `TomoMotion.shared` for a live Tomo, nil offline.
    private let motion: TomoMotion?

    public init(look: TomoLook? = nil, motion: TomoMotion? = nil) {
        fixedLook = look
        self.look = look ?? TomoLook.current
        self.motion = motion
        reduceMotion = motion?.reduce ?? false
    }

    /// The age step on show (0 = 1さい). The one it's growing into is the playing script's `swap`.
    public private(set) var age = 0
    /// The big moment playing, if any (`play`).
    private var cue: Playing?

    public private(set) var state: BotState = .idle
    private var baseFace: Face = .normal
    private var flash: (face: Face, until: Double)?
    private var moves: [Move] = []
    private var bits: [Bit] = []
    private var pose = Pose()              // this frame's moves, summed in step()

    // Smoothed values and secondary motion
    private var look2 = CGPoint.zero
    private var glance: (to: CGPoint, until: Double)?
    private var saccade = CGPoint.zero
    private var wander = CGPoint.zero
    private var tilt: CGFloat = 0
    private var puff: CGFloat = 1
    private var puffTarget: CGFloat = 1
    private var blush: CGFloat = 0
    private var sway: CGFloat = 0          // the sprout, lagging behind the body's moves
    private var swayVel: CGFloat = 0
    private var jiggle: CGFloat = 0        // the body's own wobble after a hop or a pop
    private var jiggleVel: CGFloat = 0
    private var lastDy: CGFloat = 0
    private var lastRot: CGFloat = 0
    private var lastDx: CGFloat = 0

    // Timers, started on the first frame from `clock`
    private var started = false
    private var born: Double = 0
    private var lastTime: Double = 0
    private var blinkAt: Double = -10
    private var secondBlinkAt: Double?
    private var nextBlink: Double = 0
    private var nextSaccade: Double = 0
    private var nextWander: Double = 0
    private var nextFidget: Double = 0
    private var lastStir: Double = 0
    private var lastStirLook = CGPoint.zero
    private var drowsy = false
    private var lastAmbient: Double = 0
    private var pokes: [Double] = []

    // MARK: Inputs

    public func setState(_ s: BotState, force: Bool = false) {
        guard s != state || force else { return }
        stir()
        let previous = state
        state = s
        baseFace = Self.face(for: s)
        let now = clock()
        switch s {
        case .finished:                       // got it right: hop, wiggle, sparkles
            add(.hop(0.3), 0.45); add(.wiggle(4), 0.5); add(.rock, 0.9)
            emit(.sparkle, 6)
        case .error:                          // wrong: shake it off
            add(.shake, 0.45)
            flash = (.squeeze, now + 0.8)
        case .question:                       // asking, or didn't understand: puzzled look, then attentive
            blink()
            flash = (.confused, now + 1.0)
        case .dizzy:
            add(.wobble, 1.3)
        case .approval:
            add(.hop(0.2), 0.4)
        default:
            if previous != .idle || s != .idle { blink() }
        }
    }

    public func blink() { blinkAt = clock() }

    /// The mouth opens once per spoken line.
    public func talk() { stir(); add(.mouth, 0.28) }

    /// "Over here!": a double hop with a wiggle (under Reduce Motion, a puff and a happy face).
    public func nudge() {
        stir(); add(.nudge, 0.75); blink()
        if reduceMotion { flash = (.happy, clock() + 0.8) }
    }

    public func greet() {
        stir()
        add(.hop(0.25), 0.45); add(.wiggle(6), 0.8)
        flash = (.happy, clock() + 1.4)
        emit(.sparkle, 3)
    }

    /// Eating (feed): two gulps.
    public func gulp() { stir(); add(.gulp, 0.6) }

    /// Clicked on Tomo: a squish that flops its ears or sprout (not under Reduce Motion). Three pokes in a row make it
    /// dizzy.
    public func poke() {
        stir()
        let now = clock()
        add(.squish, 0.35)
        flash = (.squeeze, now + 0.5)
        if !reduceMotion {
            swayVel += (Bool.random() ? 1 : -1) * 16
            jiggleVel += 5
        }
        pokes = pokes.filter { now - $0 < 2.5 } + [now]
        if pokes.count >= 3 {
            pokes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        }
    }

    /// A new level: the level-up script (`levelUpCue`). The game's win and `.proud`, sent with it, add nothing (`play`).
    public func levelUp() { play(Self.levelUpCue) }

    public func emote(_ e: BotEmote) {
        stir()
        let now = clock()
        switch e {
        case .love:      flash = (.love, now + 1.8); blush = 1; emit(.heart, 4)
        case .surprised: flash = (.surprised, now + 1.2); add(.hop(0.2), 0.4); add(.mouth, 0.6)
        case .proud:     flash = (.happy, now + 1.8); add(.hop(0.15), 0.4); emit(.sparkle, 4)
        case .wink:      flash = (.wink, now + 0.9)
        case .yawn:      flash = (.sleepy, now + 1.6); add(.mouth, 1.2)
        case .happy:     flash = (.happy, now + 1.4); add(.wiggle(3), 0.4)
        case .annoyed:   flash = (.flat, now + 1.2); add(.shake, 0.3)
        }
    }

    /// Cursor over Tomo: puff up a little.
    public func setHover(_ scale: CGFloat) {
        if scale > 1 { stir() }
        puffTarget = scale > 1 ? 1.05 : 1
    }

    /// Grow up (or reset) to an age step. Growing up plays the birthday script (`birthdayCue`): the new form comes at
    /// its swap.
    public func grow(to target: CGFloat) {
        let next = Self.ageStep(target)
        let showing = cue?.swap?.age ?? age            // the age on show, or the one a birthday is growing into
        // Already there, or growing into it: a shell can report one birthday twice (the iPhone's view sees the age
        // change and the game's notification), and the second must not cut the birthday short.
        if next == showing { return }
        if next > showing {
            play(Self.birthdayCue, swap: (next, cue?.swap?.look ?? look))
        } else {
            stir()
            setGrowth(target)
        }
    }

    /// Jump straight to an age step (no animation). A birthday playing keeps going, without its swap.
    public func setGrowth(_ value: CGFloat) {
        age = Self.ageStep(value)
        cue?.swap = nil
    }

    private static func ageStep(_ v: CGFloat) -> Int { min(max(Int(v.rounded()), 0), TomoLook.ages - 1) }

    /// Something small Tomo does on its own between events, so it never sits frozen:
    /// a glance, a peep, a stretch, a curious tilt, a shuffle, a little lean, or a hop.
    public func fidget() {
        let now = clock()
        switch Int.random(in: 0..<7) {
        case 0:
            let side: CGFloat = Bool.random() ? 1 : -1
            glance = (CGPoint(x: side * .random(in: 0.6...1), y: .random(in: -0.3...0.5)), now + .random(in: 0.7...1.3))
        case 1: add(.peep, 0.35)
        case 2: add(.stretch, 0.9)
        case 3: add(.tiltHold(Bool.random() ? 0.15 : -0.15), 1.4)
        case 4: add(.shuffle, 0.8)
        case 5:
            add(.lean(Bool.random() ? 1 : -1), 1.0)
            flash = (.sleep, now + 0.7)
        default: add(.hop(0.12), 0.35); add(.wiggle(2), 0.35)
        }
    }

    /// Anything happening keeps Tomo awake (and wakes it with a start if it was dozing).
    private func stir() {
        let now = clock()
        lastStir = now
        if drowsy {
            drowsy = false
            add(.hop(0.18), 0.4)
            flash = (.surprised, now + 0.6)
        }
    }

    // MARK: Frame

    public func step() {
        let now = clock()
        if let motion { reduceMotion = motion.reduce }
        if !started {
            started = true
            born = now - .random(in: 0...4)
            lastTime = now; lastStir = now
            nextBlink = now + 1.5; nextFidget = now + .random(in: 2...4)
            if fixedLook == nil { look = TomoLook.current }
        }
        // Real elapsed time: if macOS pauses the frame timer (screen asleep, window hidden),
        // particles and timers still catch up instead of freezing. Smoothing is stable for any step.
        let elapsed = max(0, now - lastTime)
        lastTime = now
        let dt = CGFloat(min(elapsed, 1))

        // A different learner's Tomo (it synced in, or a new one hatched): pop into it.
        if fixedLook == nil, TomoLook.current != (cue?.swap?.look ?? look) {
            play(Self.newTomoCue, swap: (cue?.swap?.age ?? age, TomoLook.current))
        }
        advanceCue(now)

        moves.removeAll { now > $0.start + $0.duration }
        if let f = flash, now > f.until { flash = nil }
        if let g = glance, now > g.until { glance = nil }
        pose = pose(at: now)

        // Gaze: the cursor (or a wander, or a glance), a mood, and tiny eye darts.
        var target = CGPoint(x: lookX, y: lookY)
        if !isMini, hypot(target.x - lastStirLook.x, target.y - lastStirLook.y) > 0.05 {
            lastStirLook = target
            stir()
        }
        if isMini {
            if now > nextWander {
                wander = CGPoint(x: .random(in: -0.9...0.9), y: .random(in: -0.5...0.5))
                nextWander = now + .random(in: 0.6...2.0)
            }
            target = wander
        }
        if let g = glance { target = g.to }
        switch state {
        case .thinking: target = CGPoint(x: 0.5 + target.x * 0.3, y: 0.5)
        case .sleeping: target = CGPoint(x: 0, y: -0.2)
        default: break
        }
        if drowsy { target = CGPoint(x: target.x * 0.3, y: -0.3) }
        if now > nextSaccade {
            saccade = CGPoint(x: .random(in: -0.12...0.12), y: .random(in: -0.08...0.08))
            nextSaccade = now + .random(in: 0.8...2.4)
        }
        target.x += saccade.x
        target.y += saccade.y
        let kLook = 1 - pow(0.0005, dt), kSoft = 1 - pow(0.001, dt)
        look2.x += (target.x - look2.x) * kLook
        look2.y += (target.y - look2.y) * kLook
        tilt += (Self.tilt(for: state) - tilt) * kSoft
        puff += (puffTarget - puff) * kSoft
        blush += (0 - blush) * (1 - pow(0.4, dt))

        // Springs, in small substeps: the sprout, which lags behind the body's moves and wobbles back,
        // and the body's jelly wobble when it lands.
        if dt > 0 {
            let vy = (pose.dy - lastDy) / dt
            let vx = (pose.dx - lastDx) / dt
            let vr = (pose.rot + tilt - lastRot) / dt
            let swayTarget = max(-0.6, min(0.6, -vr * 0.08 - vx * 0.6 - look2.x * 0.1))
            var left = dt
            while left > 0 {
                let h = min(left, 1.0 / 120)
                let ws: CGFloat = 18, zs: CGFloat = 0.18
                swayVel += (ws * ws * (swayTarget - sway) - 2 * zs * ws * swayVel - vy * 4) * h
                sway += swayVel * h
                let wj: CGFloat = 22, zj: CGFloat = 0.2
                jiggleVel += (-wj * wj * jiggle - 2 * zj * wj * jiggleVel + vy * 0.9) * h
                jiggle += jiggleVel * h
                left -= h
            }
            jiggle = max(-0.12, min(0.12, jiggle))
        }
        lastDy = pose.dy; lastDx = pose.dx; lastRot = pose.rot + tilt

        // Blinks, at this Tomo's own pace
        if now > nextBlink {
            if state != .sleeping && state != .dizzy {
                blinkAt = now
                if Double.random(in: 0...1) < 0.22 { secondBlinkAt = now + 0.26 }
            }
            nextBlink = now + .random(in: 2.2...5.4) * look.blinkPace
        }
        if let b = secondBlinkAt, now > b { blinkAt = now; secondBlinkAt = nil }

        // Fidgets while waiting (not during a big moment); dozing when ignored for a while.
        let calm = cue == nil && (state == .idle || state == .question || state == .thinking)
        if calm, !drowsy, flash == nil, moves.isEmpty, glance == nil, now > nextFidget {
            fidget()
            nextFidget = now + .random(in: 2.5...6)
        } else if !calm {
            nextFidget = max(nextFidget, now + 2)
        }
        if !isMini, state == .idle, !drowsy, now - lastStir > dozeAfter { drowsy = true }
        if state != .idle { drowsy = false }

        // Sleeping z's
        if (state == .sleeping || drowsy) && now - lastAmbient > (drowsy ? 3 : 1.4) {
            lastAmbient = now
            emit(.z, 1)
        }

        for i in bits.indices {
            let pace = bits[i].pace
            bits[i].age += elapsed
            bits[i].pos.x += bits[i].vel.dx * dt * pace
            bits[i].pos.y += bits[i].vel.dy * dt * pace
            bits[i].vel.dy += bits[i].kind.gravity * dt * pace
        }
        bits.removeAll { $0.age >= $0.life }
    }

    // MARK: Drawing

    public func draw(_ context: GraphicsContext, size: CGSize) {
        let now = clock()
        let p = started ? pose : pose(at: now)
        let form = look.form(age)
        let R = size.width * 0.27
        let ground = form.bottom * R
        let t = CGFloat(now - born)
        // Lean toward the cursor; nod off when drowsy.
        var rot = tilt + p.rot + look2.x * 0.06
        var dy = p.dy
        if drowsy { rot += sin(t * 0.8) * 0.05; dy += max(0, sin(t * 0.8)) * 0.03 }
        let cx = size.width / 2 + (p.dx + look2.x * 0.04) * R
        let cy = size.height / 2 + particleOverhang / 2 + dy * R + R * 0.1
        let g = form.scale
        let rate = CGFloat(look.breathRate)
        let breath = 1 + sin(t * rate) * (state == .sleeping || drowsy ? 0.035 : 0.018)

        // Anchor scaling and rocking at Tomo's base, so squashes stay on the ground.
        var ctx = context
        ctx.translateBy(x: cx, y: cy + ground)
        ctx.rotate(by: .radians(Double(rot)))
        ctx.scaleBy(x: p.sx * puff * g * (1 - jiggle * 0.5), y: p.sy * puff * g * breath * (1 + jiggle))
        ctx.translateBy(x: 0, y: -ground)

        drawTopper(ctx, form: form, R: R)
        drawBody(ctx, form: form, R: R, glow: p.glow)
        drawFace(ctx, form: form, R: R, now: now, mouth: p.mouth)

        if !isMini {
            let center = CGPoint(x: cx, y: cy)
            if state == .question { drawQuestionMark(context, center: center, R: R * g, t: t) }
            drawBits(context, center: center, R: R * g)
        }
    }

    // MARK: - Parts

    private enum Palette {
        public static let heart = Color(hex: "#FF5C8A")
        public static let leaf = Color(hex: "#7FD36B")
        public static let leafDark = Color(hex: "#4FA845")
        public static let horn = Color(hex: "#FFF1D6")
        public static let gold = Color(hex: "#FFC83D")
        public static let goldEdge = Color(hex: "#B5630C")
    }

    private func drawBody(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, glow: CGFloat) {
        let body = form.path(R: R)
        let top = -form.top * R, bottom = form.bottom * R
        ctx.fill(body, with: .linearGradient(Gradient(colors: [look.bodyLight, look.body]),
                                             startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        var inner = ctx
        inner.clip(to: body)
        drawPattern(inner, form: form, R: R, top: top, bottom: bottom)
        // A soft shade along the bottom, so it sits on something.
        inner.fill(Path(ellipseIn: CGRect(x: -R * 1.4, y: bottom - R * 0.35, width: R * 2.8, height: R * 0.9)),
                   with: .color(.black.opacity(0.08)))
        if form.details.contains(.sheen) {
            inner.fill(Path(ellipseIn: CGRect(x: -R * 0.62, y: top + R * 0.2, width: R * 0.36, height: R * 0.22))
                        .applying(CGAffineTransform(rotationAngle: -0.5)),
                       with: .color(.white.opacity(0.4)))
        }
        if form.details.contains(.mark) {
            let side: CGFloat = look.markSeed < 0.5 ? -1 : 1
            var c = inner
            c.translateBy(x: side * form.rx * R * 0.48, y: (form.faceY - 0.42) * R)
            c.rotate(by: .radians(Double(side) * 0.3))
            let s = R * 0.16
            if look.markSeed.truncatingRemainder(dividingBy: 0.5) < 0.25 { c.fill(heart(size: s), with: .color(.white.opacity(0.6))) }
            else { c.fill(star(s * 0.55, inner: 0.45, points: 5), with: .color(.white.opacity(0.6))) }
        }
        if glow > 0.01 { inner.fill(body, with: .color(.white.opacity(Double(glow)))) }
    }

    /// Its markings, in its second colour, kept off the face.
    private func drawPattern(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, top: CGFloat, bottom: CGFloat) {
        let accent = GraphicsContext.Shading.color(look.accent)
        let w = form.rx * R
        switch look.pattern {
        case .none:
            break
        case .belly:
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.62, y: bottom - R * 0.72, width: w * 1.24, height: R * 1.1)), with: accent)
        case .cap:
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 1.5, y: top - R * 1.3, width: w * 3, height: R * 1.75)), with: accent)
        case .spots:
            var rng = look.markSeed
            for _ in 0..<7 {
                rng = (rng * 9301 + 0.4929).truncatingRemainder(dividingBy: 1)
                let x = (CGFloat(rng) * 2 - 1) * form.rx * 0.85
                rng = (rng * 9301 + 0.4929).truncatingRemainder(dividingBy: 1)
                let y = (CGFloat(rng) * 1.7 - 0.85) * form.ry
                let r = R * (0.09 + 0.07 * CGFloat(rng))
                guard abs(y - form.faceY - look.eyeY) > 0.3 || abs(x) > 0.55 else { continue }
                ctx.fill(Path(ellipseIn: CGRect(x: x * R - r, y: y * R - r, width: r * 2, height: r * 2)), with: accent)
            }
        case .stripes:
            for i in 0..<3 {
                let y = top + R * (0.1 + 0.17 * CGFloat(i))
                var band = Path()
                band.move(to: CGPoint(x: -w * 1.5, y: y))
                band.addQuadCurve(to: CGPoint(x: w * 1.5, y: y), control: CGPoint(x: 0, y: y - R * 0.12))
                ctx.stroke(band, with: accent, style: StrokeStyle(lineWidth: R * 0.075, lineCap: .round))
            }
        case .twoTone:
            ctx.fill(Path(CGRect(x: -w * 2, y: top - R, width: w * 4, height: bottom - top + R * 2)),
                     with: .linearGradient(Gradient(colors: [look.accent, look.accent.opacity(0)]),
                                           startPoint: CGPoint(x: -w, y: top), endPoint: CGPoint(x: w * 0.4, y: bottom)))
        }
    }

    /// What grows on its head from 2さい (ears, horns, an antenna or a sprout), swaying after every move.
    private func drawTopper(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat) {
        guard age >= 1, look.topper != .none else { return }
        let grow = 0.8 + 0.06 * CGFloat(age)
        let lift = (form.silhouette == .droplet ? 0.18 : 0) - form.ry * 0.74
        let spread = form.rx * (form.silhouette == .triangle ? 0.3 : 0.58)
        let fill = GraphicsContext.Shading.color(look.bodyLight)
        let inside = GraphicsContext.Shading.color(look.cheek.opacity(0.55))
        func pair(_ draw: (GraphicsContext, CGFloat) -> Void) {
            for side: CGFloat in [-1, 1] {
                var c = ctx
                c.translateBy(x: side * spread * R, y: lift * R)
                c.rotate(by: .radians(Double(side * 0.3 + sway * 0.5)))
                draw(c, side)
            }
        }
        switch look.topper {
        case .none:
            break
        case .cat:
            pair { c, _ in
                let h = R * 0.48 * grow, b = R * 0.24
                c.fill(triangle(b, h), with: fill)
                c.fill(triangle(b * 0.55, h * 0.62), with: inside)
            }
        case .bunny:
            pair { c, _ in
                let h = R * 0.8 * grow
                c.fill(Path(ellipseIn: CGRect(x: -R * 0.13, y: -h, width: R * 0.26, height: h + R * 0.1)), with: fill)
                c.fill(Path(ellipseIn: CGRect(x: -R * 0.065, y: -h * 0.85, width: R * 0.13, height: h * 0.75)), with: inside)
            }
        case .bear:
            pair { c, _ in
                let r = R * 0.21 * grow
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 1.5, width: r * 2, height: r * 2)), with: fill)
                c.fill(Path(ellipseIn: CGRect(x: -r * 0.5, y: -r, width: r, height: r)), with: inside)
            }
        case .horns:
            pair { c, _ in
                c.fill(triangle(R * 0.11, R * 0.36 * grow), with: .color(Palette.horn))
            }
        case .antenna:
            var c = ctx
            c.translateBy(x: 0, y: -form.top * R + R * 0.08)
            c.rotate(by: .radians(Double(form.sproutLean + sway * 0.9)))
            let L = R * 0.42 * grow
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: R * 0.1, y: -L * 0.5))
            c.stroke(stem, with: .color(look.ink.opacity(0.7)), style: StrokeStyle(lineWidth: R * 0.04, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: -R * 0.09, y: -L - R * 0.09, width: R * 0.18, height: R * 0.18)),
                   with: .color(look.pattern == .none ? look.cheek : look.accent))
        case .sprout:
            var c = ctx
            c.translateBy(x: 0, y: -form.top * R + R * 0.06)
            c.rotate(by: .radians(Double(form.sproutLean + sway * 0.9)))
            let L = R * 0.3 * grow
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: -R * 0.08, y: -L * 0.5))
            c.stroke(stem, with: .color(Palette.leafDark), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
            for side: CGFloat in [-1, 1] {
                var leaf = Path()
                leaf.move(to: CGPoint(x: 0, y: -L))
                leaf.addQuadCurve(to: CGPoint(x: side * R * 0.24, y: -L - R * 0.1), control: CGPoint(x: side * R * 0.1, y: -L - R * 0.16))
                leaf.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: side * R * 0.16, y: -L + R * 0.02))
                c.fill(leaf, with: .color(Palette.leaf))
            }
        }
    }

    /// A rounded spike standing on the origin: base half-width `b`, height `h`.
    private func triangle(_ b: CGFloat, _ h: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -b, y: b * 0.4))
        p.addQuadCurve(to: CGPoint(x: 0, y: -h), control: CGPoint(x: -b * 0.6, y: -h * 0.5))
        p.addQuadCurve(to: CGPoint(x: b, y: b * 0.4), control: CGPoint(x: b * 0.6, y: -h * 0.5))
        p.closeSubpath()
        return p
    }

    private func star(_ r: CGFloat, inner: CGFloat, points: Int) -> Path {
        var p = Path()
        for i in 0..<(points * 2) {
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let rr = i % 2 == 0 ? r : r * inner
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// The face on show: a big moment's, else a flash, else the state's (sleepy while dozing).
    private var shownFace: Face { cue?.face ?? flash?.face ?? (drowsy ? .sleepy : baseFace) }

    private func drawFace(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, now: Double, mouth: CGFloat) {
        let face = shownFace
        let fit = min(1, form.faceW / 0.8) * (isMini ? 1.4 : 1)       // a small face gets smaller eyes
        let one: CGFloat = look.cyclops ? 1.55 : 1
        let fx = look2.x * R * 0.16 * form.faceW, fy = -look2.y * R * 0.1 + (form.faceY + look.eyeY * fit) * R
        let ew = look.eyeW * R * fit * one, eh = look.eyeH * R * fit * one
        let unit = R * 0.095 * fit * one                                // the size expressions are drawn at
        let gap = look.cyclops ? 0 : look.eyeGap * R * max(0.7, fit)
        let eyeY = fy - eh * 0.2
        let cheekX = look.cyclops ? ew * 1.9 : gap + max(ew, unit) * 1.4
        let low = eyeY + max(eh, unit * 1.4) * 0.75                     // just under the eyes

        // Cheeks: a blush when it's loved; some Tomos have rosy cheeks all the time.
        let rosy: CGFloat = form.details.contains(.cheeks) ? 0.5 : 0
        let cheekA = max(rosy, 0.9 * blush)
        if cheekA > 0.02 {
            for side: CGFloat in [-1, 1] {
                let far = 1 - 0.3 * max(0, -side * look2.x)
                let c = CGPoint(x: side * cheekX + fx * 0.6, y: low)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.11 * far, y: c.y - R * 0.06, width: R * 0.22 * far, height: R * 0.12)),
                         with: .color(look.cheek.opacity(Double(cheekA))))
            }
        }
        if form.details.contains(.freckles) {
            for side: CGFloat in [-1, 1] {
                for (dx, dy) in [(-0.06, 0.0), (0.05, -0.02), (0.0, 0.06)] as [(CGFloat, CGFloat)] {
                    let c = CGPoint(x: side * cheekX + fx * 0.6 + dx * R, y: low + dy * R)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.018, y: c.y - R * 0.018, width: R * 0.036, height: R * 0.036)),
                             with: .color(look.ink.opacity(0.35)))
                }
            }
        }

        // Eyes (one, for a cyclops)
        let since = now - blinkAt
        let open: CGFloat = since < 0.09 ? CGFloat(1 - since / 0.09)
                          : since < 0.2 ? CGFloat((since - 0.09) / 0.11) : 1
        for side: CGFloat in look.cyclops ? [1] : [-1, 1] {
            var c = ctx
            c.translateBy(x: side * gap + fx, y: eyeY)
            if !look.cyclops { c.scaleBy(x: 1 - 0.25 * max(0, -side * look2.x), y: 1) }   // the eye turning away narrows
            drawEye(c, face: face, side: side, w: ew, h: eh, unit: unit, open: max(0.08, open), now: now)
        }

        // Mouth: opens to talk, eat, yawn and gasp; otherwise its own resting mouth, if it has one.
        let o = min(1, mouth + (face == .surprised ? 0.4 : 0))
        let my = low + R * 0.04
        if o > 0.03 {
            let mw = R * (0.07 + 0.05 * o), mh = R * 0.16 * o
            ctx.fill(Path(roundedRect: CGRect(x: fx * 1.2 - mw, y: my, width: mw * 2, height: max(R * 0.03, mh)),
                          cornerRadius: mw), with: .color(look.ink))
            return
        }
        var m = ctx
        m.translateBy(x: fx * 1.2, y: my + R * 0.02)
        let ink = GraphicsContext.Shading.color(look.ink)
        let line = StrokeStyle(lineWidth: R * 0.032, lineCap: .round, lineJoin: .round)
        switch look.mouth {
        case .none:
            break
        case .smile, .fang:
            var p = Path()
            p.move(to: CGPoint(x: -R * 0.075, y: 0))
            p.addQuadCurve(to: CGPoint(x: R * 0.075, y: 0), control: CGPoint(x: 0, y: R * 0.08))
            m.stroke(p, with: ink, style: line)
            if look.mouth == .fang {
                var f = Path()
                f.move(to: CGPoint(x: R * 0.015, y: R * 0.035)); f.addLine(to: CGPoint(x: R * 0.06, y: R * 0.025))
                f.addLine(to: CGPoint(x: R * 0.04, y: R * 0.075)); f.closeSubpath()
                m.fill(f, with: .color(.white))
            }
        case .cat:
            var p = Path()
            p.move(to: CGPoint(x: -R * 0.08, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -R * 0.04, y: R * 0.06))
            p.addQuadCurve(to: CGPoint(x: R * 0.08, y: 0), control: CGPoint(x: R * 0.04, y: R * 0.06))
            m.stroke(p, with: ink, style: line)
        case .o:
            m.stroke(Path(ellipseIn: CGRect(x: -R * 0.032, y: -R * 0.01, width: R * 0.064, height: R * 0.07)), with: ink, style: line)
        case .flat:
            var p = Path()
            p.move(to: CGPoint(x: -R * 0.05, y: R * 0.02)); p.addLine(to: CGPoint(x: R * 0.05, y: R * 0.02))
            m.stroke(p, with: ink, style: line)
        }
    }

    /// One eye. At rest it's the Tomo's own eye style (`w`, `h`); expressions are drawn at a shared `unit`, so
    /// every Tomo's faces read the same.
    private func drawEye(_ ctx: GraphicsContext, face: Face, side: CGFloat, w: CGFloat, h: CGFloat, unit u: CGFloat,
                         open: CGFloat, now: Double) {
        let ink = GraphicsContext.Shading.color(look.ink)
        let line = StrokeStyle(lineWidth: u * 1.05, lineCap: .round, lineJoin: .round)
        func eye(_ k: CGFloat, dy: CGFloat = 0) {
            let rw = w * k, rh = h * k * open
            var shape = TomoForm.superellipse(rx: rw, ry: rh, n: look.eyeN).offsetBy(dx: 0, dy: dy)
            if look.eyeStyle == .lidded {      // a heavy upper lid: only the lower part shows
                shape = shape.intersection(Path(CGRect(x: -rw * 2, y: dy - rh * 0.25, width: rw * 4, height: rh * 3)))
            }
            ctx.fill(shape, with: ink)
            guard open > 0.6, look.eyeStyle != .bead || k > 1 else { return }
            let s = rw * (look.eyeStyle == .big ? 0.38 : 0.3)
            let gy = look.eyeStyle == .lidded ? dy : dy - rh * 0.45
            ctx.fill(Path(ellipseIn: CGRect(x: rw * 0.2 - s, y: gy - s, width: s * 2, height: s * 2)), with: .color(.white.opacity(0.9)))
            if look.eyeStyle == .big {
                let t = s * 0.45
                ctx.fill(Path(ellipseIn: CGRect(x: -rw * 0.35 - t, y: dy + rh * 0.35 - t, width: t * 2, height: t * 2)),
                         with: .color(.white.opacity(0.7)))
            }
        }
        func smile() {
            var p = Path()
            p.move(to: CGPoint(x: -u * 1.5, y: u * 0.5))
            p.addQuadCurve(to: CGPoint(x: u * 1.5, y: u * 0.5), control: CGPoint(x: 0, y: -u * 1.7))
            ctx.stroke(p, with: ink, style: line)
        }
        switch face {
        case .normal: eye(1)
        case .surprised: eye(1.22)
        case .confused: side < 0 ? eye(0.72, dy: -h * 0.15) : eye(1.12)
        case .happy: smile()
        case .wink: side > 0 ? smile() : eye(1)
        case .sleep:
            var p = Path()
            p.move(to: CGPoint(x: -u * 1.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: u * 1.5, y: 0), control: CGPoint(x: 0, y: u * 1.2))
            ctx.stroke(p, with: ink, style: line)
        case .sleepy:
            ctx.fill(Path(roundedRect: CGRect(x: -u * 1.2, y: u * 0.1, width: u * 2.4, height: u * 0.6), cornerRadius: u * 0.3), with: ink)
        case .flat:
            ctx.fill(Path(roundedRect: CGRect(x: -u * 1.6, y: -u * 0.5, width: u * 3.2, height: u), cornerRadius: u * 0.5), with: ink)
        case .squeeze:
            var p = Path()
            let d = -side          // left eye ">", right eye "<"
            p.move(to: CGPoint(x: -u * 1.2 * d, y: -u * 1.1))
            p.addLine(to: CGPoint(x: u * 1.1 * d, y: 0))
            p.addLine(to: CGPoint(x: -u * 1.2 * d, y: u * 1.1))
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: u * 0.95, lineCap: .round, lineJoin: .round))
        case .love:
            ctx.fill(heart(size: u * 3.6), with: .color(Palette.heart))
        case .star:                        // a gold star per eye, rocking a little
            var c = ctx
            c.rotate(by: .radians(Double(starRock(now))))
            let s = star(u * 2.5, inner: 0.5, points: 5)
            c.stroke(s, with: .color(Palette.goldEdge), style: StrokeStyle(lineWidth: u * 0.5, lineJoin: .round))
            c.fill(s, with: .color(Palette.gold))
        case .dizzy:
            let a = CGFloat(now * 7) * side
            let r = u * 1.5
            var p = Path()
            p.addArc(center: .zero, radius: r * 0.95, startAngle: .radians(Double(a)),
                     endAngle: .radians(Double(a) + 5), clockwise: false)
            p.addArc(center: .zero, radius: r * 0.42, startAngle: .radians(Double(a) + 5),
                     endAngle: .radians(Double(a) + 9), clockwise: false)
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: u * 0.7, lineCap: .round))
        }
    }

    private func drawQuestionMark(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat, t: CGFloat) {
        let mark = Text("?").font(.system(size: R * 0.55, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
        ctx.draw(mark, at: CGPoint(x: center.x + R * 1.05, y: center.y - R * 1.0 + sin(t * 3) * R * 0.05))
    }

    // MARK: - Particles

    private struct Bit {
        public enum Kind {
            case sparkle, heart, z, pop
            public var gravity: CGFloat { self == .pop ? 2.6 : self == .sparkle ? 0.6 : -0.15 }
        }
        public let kind: Kind
        public var pos: CGPoint        // relative to Tomo's center, in body radii
        public var vel: CGVector
        public var age: Double = 0
        public let life: Double
        public let size: CGFloat
        public let spin: CGFloat
        /// How fast it plays: 1, or slower under Reduce Motion (the same path, at that pace).
        public var pace: CGFloat = 1
    }

    /// Particles fly at this pace under Reduce Motion, and only a third of them.
    private static let calmPace: CGFloat = 0.4

    /// While a big moment plays, only its own particles fly (`fromCue`).
    private func emit(_ kind: Bit.Kind, _ count: Int, fromCue: Bool = false) {
        guard !isMini, cue == nil || fromCue else { return }
        let count = reduceMotion ? max(1, Int((Double(count) / 3).rounded())) : count
        let first = bits.count
        for _ in 0..<count {
            switch kind {
            case .sparkle:
                let a = CGFloat.random(in: 0...(2 * .pi))
                let speed = CGFloat.random(in: 0.7...1.2)
                bits.append(Bit(kind: kind, pos: CGPoint(x: cos(a) * 0.9, y: sin(a) * 0.9 - 0.1),
                                vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 0.5),
                                life: .random(in: 0.6...0.9), size: .random(in: 0.12...0.2), spin: .random(in: -4...4)))
            case .heart:
                bits.append(Bit(kind: kind, pos: CGPoint(x: .random(in: -0.6...0.6), y: -0.9),
                                vel: CGVector(dx: .random(in: -0.3...0.3), dy: .random(in: -0.9 ... -0.6)),
                                life: .random(in: 1.0...1.4), size: .random(in: 0.22...0.3), spin: 0))
            case .z:
                bits.append(Bit(kind: kind, pos: CGPoint(x: 0.6, y: -0.8),
                                vel: CGVector(dx: 0.25, dy: -0.45), life: 1.8, size: 0.3, spin: 0))
            case .pop:                         // drops of Tomo's own colour, flung out as it evolves
                let a = CGFloat.random(in: 0...(2 * .pi))
                let speed = CGFloat.random(in: 1.2...2.0)
                bits.append(Bit(kind: kind, pos: CGPoint(x: cos(a) * 0.6, y: sin(a) * 0.6),
                                vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 1.2),
                                life: .random(in: 0.7...1.0), size: .random(in: 0.08...0.15), spin: 0))
            }
        }
        if reduceMotion { for i in first..<bits.count { bits[i].pace = Self.calmPace } }
    }

    private func drawBits(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat) {
        for b in bits {
            var c = ctx
            c.opacity = max(0, 1 - b.age / b.life)
            c.translateBy(x: center.x + b.pos.x * R, y: center.y + b.pos.y * R)
            c.rotate(by: .radians(Double(b.spin * b.pace) * b.age))
            let s = b.size * R
            switch b.kind {
            case .sparkle:
                var star = Path()
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4
                    let rr = i % 2 == 0 ? s : s * 0.3
                    let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
                    if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                }
                star.closeSubpath()
                c.fill(star, with: .color(Color(hex: "#FFF3B0")))
            case .heart:
                c.fill(heart(size: s * 2), with: .color(Palette.heart))
            case .z:
                c.draw(Text("z").font(.system(size: s * 1.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8)), at: .zero)
            case .pop:
                c.fill(Path(ellipseIn: CGRect(x: -s, y: -s, width: s * 2, height: s * 2)), with: .color(look.body))
            }
        }
    }

    // MARK: - Moves

    private enum Face { case normal, happy, sleep, sleepy, squeeze, surprised, love, confused, dizzy, wink, flat, star }

    /// The star eyes' rock, in radians: still under Reduce Motion (it's a face, so the stars stay).
    private func starRock(_ now: Double) -> CGFloat { reduceMotion ? 0 : CGFloat(sin(now * 5)) * 0.2 }

    private struct Move {
        public enum Kind {
            case hop(CGFloat), nudge, shake, wiggle(Int), gulp, rock, squish, wobble, mouth
            case peep, stretch, tiltHold(CGFloat), shuffle, lean(CGFloat)
            case puff                          // Reduce Motion's stand-in for the others: a small swell
            // The cue scripts' moves. Each starts and ends at rest, so they add up; times are in seconds.
            case crouch                        // squeeze down, then let go to take off
            case leap(CGFloat)                 // up that high (in body radii) and down, stretched and twirling
            case settle                        // a few small rocks, dying away
            case evolve(squeeze: Double)       // squeeze down until then (the new shape), then pop out past size
            case glow(CGFloat, peak: Double)   // glow up to that brightness at that time (0: a flash), then fade

            /// Carries Tomo off its spot, tips or squashes it: under Reduce Motion it becomes a puff, and during a big
            /// moment it's skipped (`add`). The mouth moves only open the mouth then, and a glow only glows (`pose`).
            public var movesBody: Bool {
                switch self {
                case .mouth, .peep, .gulp, .glow: return false
                default: return true
                }
            }
        }
        public let kind: Kind
        public let start: Double
        public let duration: Double
        /// Started by a big moment's script, so a newer one takes it back (`play`).
        public var byCue = false
    }

    private struct Pose {
        public var dx: CGFloat = 0, dy: CGFloat = 0, rot: CGFloat = 0
        public var sx: CGFloat = 1, sy: CGFloat = 1
        public var mouth: CGFloat = 0, glow: CGFloat = 0
    }

    private func add(_ kind: Move.Kind, _ duration: Double) {
        let now = clock()
        if cue != nil, kind.movesBody { return }            // a big moment owns the body (`play`)
        guard reduceMotion, kind.movesBody else {
            moves.append(Move(kind: kind, start: now, duration: duration))
            return
        }
        // Reduce Motion: a small puff instead, one for moves that start together (a win's hop, wiggle and rock).
        let puffing = moves.contains { m in
            if case .puff = m.kind { return now - m.start < 0.3 }
            return false
        }
        if !puffing { moves.append(Move(kind: .puff, start: now, duration: 0.5)) }
    }

    private func pose(at now: Double) -> Pose {
        var p = Pose()
        let body: CGFloat = reduceMotion ? 0 : 1           // the mouth moves' little bob
        var puffed: CGFloat = 0                            // puffs don't add up: the fullest one shows
        for m in moves {
            let q = CGFloat(min(1, max(0, (now - m.start) / m.duration)))
            let arc = sin(.pi * q)
            switch m.kind {
            case .hop(let h):
                p.dy -= h * arc; p.sy *= 1 + 0.08 * arc; p.sx *= 1 - 0.05 * arc
            case .nudge:
                p.dy -= q < 0.55 ? 0.42 * sin(.pi * q / 0.55) : 0.2 * sin(.pi * (q - 0.55) / 0.45)
                let w = sin(q * 8 * .pi) * 0.06
                p.sx *= 1 + w; p.sy *= 1 - w
            case .shake:
                p.dx += sin(q * 6 * .pi) * 0.09 * (1 - q)
            case .wiggle(let n):                   // a happy jelly wiggle: squash and stretch side to side
                let w = sin(q * CGFloat(n) * .pi) * 0.07 * (1 - q * 0.5)
                p.sx *= 1 + w; p.sy *= 1 - w; p.rot += w * 0.6
            case .gulp:
                p.dy += 0.1 * abs(sin(q * 2 * .pi)) * body; p.mouth = max(p.mouth, max(0, sin(q * 4 * .pi)))
                p.sy *= 1 - 0.06 * abs(sin(q * 2 * .pi)) * body
            case .rock:
                p.rot += sin(q * 4 * .pi) * 0.13 * (1 - q * 0.6)
            case .squish:
                p.sy *= 1 - 0.2 * arc; p.sx *= 1 + 0.15 * arc
            case .wobble:
                p.rot += sin(q * 7 * .pi) * 0.16 * (1 - q)
            case .mouth:
                p.mouth = max(p.mouth, arc); p.dy -= 0.04 * arc * body
            case .peep:
                p.mouth = max(p.mouth, 0.55 * arc); p.dy -= 0.05 * arc * body
            case .stretch:
                p.sy *= 1 + 0.09 * arc; p.sx *= 1 - 0.05 * arc
            case .tiltHold(let a):
                p.rot += a * Self.hold(q)
            case .shuffle:
                p.dx += sin(q * 4 * .pi) * 0.05; p.rot += sin(q * 4 * .pi) * 0.05
            case .lean(let side):
                let e = Self.hold(q)
                p.rot += side * 0.16 * e; p.dy += 0.05 * e; p.sy *= 1 - 0.04 * e
            case .puff:
                puffed = max(puffed, arc)
            case .crouch:                          // the squash builds, then lets go in the last fifth
                let e = q < 0.8 ? Self.inOut(q / 0.8) : 1 - Self.inOut((q - 0.8) / 0.2)
                p.sx *= 1 + 0.16 * e; p.sy *= 1 - 0.2 * e
            case .leap(let h):
                p.dy -= h * arc; p.sx *= 1 - 0.1 * arc; p.sy *= 1 + 0.14 * arc
                p.rot += sin(q * 2 * .pi) * 0.12
            case .settle:
                p.rot += sin(q * 4 * .pi) * 0.05 * (1 - q)
            case .evolve(let squeeze):             // wide and trembling, then the new shape pops out past its size
                let at = CGFloat(squeeze / m.duration)
                if q < at {
                    let e = Self.inOut(q / at)
                    p.sx *= 1 + 0.2 * e; p.sy *= 1 - 0.3 * e
                    p.dx += sin(CGFloat(now - m.start) * 70) * 0.02 * e
                } else {
                    let k = (q - at) / (1 - at), b = Self.overshoot(k)
                    p.sx *= 1.2 - 0.2 * b; p.sy *= 0.7 + 0.3 * b
                    p.dy -= 0.32 * sin(.pi * k)
                }
            case .glow(let g, let peak):
                let at = CGFloat(peak / m.duration)
                let e = q < at ? Self.inOut(q / at) : 1 - (q - at) / max(1 - at, 0.001)
                p.glow = max(p.glow, g * e)
            }
        }
        if puffed > 0 {
            p.sx *= 1 + 0.045 * puffed; p.sy *= 1 + 0.045 * puffed
            p.glow = max(p.glow, 0.16 * puffed)
        }
        return p
    }

    /// 0 → 1 → hold → 0 envelope with eased edges.
    private static func hold(_ q: CGFloat) -> CGFloat {
        let e = min(1, min(q, 1 - q) * 4)
        return e * e * (3 - 2 * e)
    }

    /// 0 → 1, easing in and out (cubic).
    private static func inOut(_ u: CGFloat) -> CGFloat {
        if u < 0.5 { return 4 * u * u * u }
        let v = 2 - 2 * u
        return 1 - v * v * v / 2
    }

    /// 0 → 1, past 1 and back (a springy overshoot).
    private static func overshoot(_ u: CGFloat) -> CGFloat {
        let s: CGFloat = 1.9, v = u - 1
        return 1 + (s + 1) * v * v * v + s * v * v
    }

    private static func face(for s: BotState) -> Face {
        switch s {
        case .finished: return .happy
        case .sleeping: return .sleep
        case .dizzy: return .dizzy
        case .approval: return .surprised
        case .ratelimit: return .sleepy
        default: return .normal
        }
    }

    private static func tilt(for s: BotState) -> CGFloat {
        switch s {
        case .question: return 0.18
        case .sleeping: return -0.06
        default: return 0
        }
    }

    // MARK: - Big moments (cue scripts)

    /// A big moment as one timeline on Tomo's clock: what happens at each time, as data, so it plays the same live and
    /// offline. `lively` is the moment; `calm` plays under Reduce Motion (a glow, star eyes and a small puff; no hop,
    /// squash or tip). To add a moment (#87), write a script; a new kind of step or move goes here and in `pose`.
    private struct Cue {
        enum Step {
            case face(Face)                    // worn from then on, until the next face or the end
            case move(Move.Kind, Double)       // a move for that many seconds, starting exactly at the step's time
            case sparkles(Int)
            case drops(Int)                    // drops of Tomo's own colour
            case kick(CGFloat)                 // a jiggle, as on landing
            case swap                          // the new shape: the age or look the script was started with
        }
        let length: Double
        let lively: [(at: Double, step: Step)]
        let calm: [(at: Double, step: Step)]
    }

    /// A new level (about 2.1 s): squeeze, then flash and leap with star eyes and a sparkle burst, land with a jiggle
    /// kick, settle with happy eyes.
    private static let levelUpCue = Cue(length: 2.1, lively: [
        (0, .face(.squeeze)), (0, .move(.crouch, 0.35)),
        (0.35, .face(.star)), (0.35, .move(.leap(0.55), 0.6)), (0.35, .move(.glow(0.85, peak: 0), 0.45)),
        (0.38, .sparkles(10)),
        (0.95, .move(.squish, 0.35)), (0.95, .kick(6)), (0.95, .sparkles(3)),
        (1.3, .move(.settle, 0.8)), (1.3, .face(.happy)),
    ], calm: [
        (0, .face(.star)), (0, .move(.glow(0.5, peak: 0.25), 0.5)), (0, .move(.puff, 0.5)),
        (0.15, .sparkles(10)),
        (1.7, .face(.happy)),
    ])

    /// A birthday (about 2.6 s): a glowing squeeze-down, the new shape at 0.62 s with drops of Tomo's colour, a pop
    /// out with star eyes, and it settles, happy.
    private static let birthdayCue = Cue(length: 2.6, lively: [
        (0, .face(.squeeze)), (0, .move(.evolve(squeeze: 0.62), 1.2)), (0, .move(.glow(0.95, peak: 0.62), 1.2)),
        (0.62, .swap), (0.62, .drops(12)), (0.62, .kick(7)), (0.62, .face(.star)),
        (0.66, .sparkles(10)),
        (1.2, .kick(6)), (1.2, .sparkles(3)), (1.2, .move(.settle, 0.8)),
        (1.8, .face(.happy)),
    ], calm: [
        (0, .face(.star)), (0, .move(.glow(0.95, peak: 0.62), 1.2)),
        (0.62, .swap), (0.62, .drops(12)), (0.62, .move(.puff, 0.5)),
        (0.66, .sparkles(10)),
        (1.8, .face(.happy)),
    ])

    /// Becoming another Tomo (a new one hatched, or the learner's own arrived from iCloud): the birthday's squeeze and
    /// pop, without the party.
    private static let newTomoCue = Cue(length: 2.0, lively: [
        (0, .move(.evolve(squeeze: 0.62), 1.2)), (0, .move(.glow(0.95, peak: 0.62), 1.2)),
        (0.62, .swap), (0.62, .drops(12)), (0.62, .kick(7)),
        (1.2, .move(.settle, 0.8)),
    ], calm: [
        (0, .move(.glow(0.95, peak: 0.62), 1.2)),
        (0.62, .swap), (0.62, .drops(12)), (0.62, .move(.puff, 0.5)),
    ])

    /// A script playing: its steps (lively or calm, picked when it starts), how far it has got, and what it opened.
    private final class Playing {
        let length: Double
        let start: Double
        let steps: [(at: Double, step: Cue.Step)]
        var next = 0                           // the first step not fired yet
        var fired: [Double] = []               // the clock when each step fired (the self-test reads it)
        var face: Face?
        var swap: (age: Int, look: TomoLook)?  // what `.swap` changes to; nil once it has

        init(_ cue: Cue, start: Double, calm: Bool, swap: (age: Int, look: TomoLook)?) {
            length = cue.length
            self.start = start
            steps = calm ? cue.calm : cue.lively
            self.swap = swap
        }
    }

    /// Plays a big moment. A newer one replaces the one playing, which first finishes what it opened (its shape swap).
    /// The moment starts clean: body moves and particles that other inputs started since the last frame (the game's
    /// win and `.proud`, sent with a level-up) are taken back, and until it ends it owns Tomo's body, face and particles
    /// (`add`, `emit`, `shownFace`); the mouth still talks.
    private func play(_ script: Cue, swap: (age: Int, look: TomoLook)? = nil) {
        stir()
        if let old = cue {
            if let s = old.swap { age = s.age; look = s.look }
            moves.removeAll { $0.byCue }
        }
        moves.removeAll { $0.start >= lastTime && $0.kind.movesBody }
        bits.removeAll { $0.age == 0 }
        flash = nil
        let now = clock()
        cue = Playing(script, start: now, calm: reduceMotion, swap: swap)
        advanceCue(now)
    }

    /// Fires the playing script's due steps, each once and in order; a move starts at its step's own time, whatever the
    /// frame rate. The script ends after its length. One whose time passed while Tomo wasn't drawn (a hidden island, an
    /// app in the background) only swaps the shape.
    private func advanceCue(_ now: Double) {
        guard let c = cue else { return }
        let over = now >= c.start + c.length
        while c.next < c.steps.count, c.start + c.steps[c.next].at <= now {
            let (at, step) = c.steps[c.next]
            c.next += 1
            c.fired.append(now)
            switch step {
            case .swap:
                if let s = c.swap { age = s.age; look = s.look; c.swap = nil }
            case _ where over:
                break
            case .face(let f):
                c.face = f
            case .move(let kind, let duration):
                moves.append(Move(kind: kind, start: c.start + at, duration: duration, byCue: true))
            case .sparkles(let n):
                emit(.sparkle, n, fromCue: true)
            case .drops(let n):
                emit(.pop, n, fromCue: true)
            case .kick(let v):
                if !reduceMotion { jiggleVel += v }
            }
        }
        if over {
            if let s = c.swap { age = s.age; look = s.look }
            cue = nil
        }
    }

    // MARK: - Shapes

    private func heart(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: s * 0.35))
        p.addCurve(to: CGPoint(x: -s * 0.5, y: -s * 0.1), control1: CGPoint(x: -s * 0.1, y: s * 0.2),
                   control2: CGPoint(x: -s * 0.5, y: s * 0.12))
        p.addArc(center: CGPoint(x: -s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(180),
                 endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(180),
                 endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: s * 0.35), control1: CGPoint(x: s * 0.5, y: s * 0.12),
                   control2: CGPoint(x: s * 0.1, y: s * 0.2))
        return p
    }
}

// MARK: - Checks (TOMO_SELFTEST)

extension TomoBlob {
    /// Reduce Motion, on a scripted clock: a win, a miss, a poke, a nudge, a level-up and a birthday keep Tomo on its
    /// spot with only a small puff, a win's sparkles are a third, the level-up and the birthday are a glow and star eyes,
    /// the birthday still swaps the shape, and Tomo still blinks. The same script with it off must hop, so the check can
    /// tell.
    static func motionSelfTest(_ check: (Bool, String) -> Void) {
        struct Run {
            var moved: CGFloat = 0, swell: CGFloat = 0, squash: CGFloat = 0, glow: CGFloat = 0
            var sparkles = 0, age = 0, blinks = 0, stars = 0
        }
        func run(reduce: Bool) -> Run {
            let blob = TomoBlob(look: .mascot)
            blob.reduceMotion = reduce
            var t = 100.0
            blob.clock = { t }
            blob.step()
            var r = Run()
            blob.setState(.finished)                                     // a win
            r.sparkles = blob.bits.count
            let script: [(at: Double, run: (TomoBlob) -> Void)] = [
                (1.5, { $0.setState(.idle) }),
                (2.0, { $0.setState(.error) }), (3.0, { $0.setState(.idle) }),   // a miss
                (3.5, { $0.poke() }),
                (4.5, { $0.nudge() }),
                (5.5, { $0.setState(.finished); $0.emote(.proud); $0.levelUp() }),   // a level-up (TomoGame.celebrate)
                (8.0, { $0.setState(.idle); $0.grow(to: 1) }),               // a birthday
            ]
            var next = 0, lastBlink = blob.blinkAt
            for i in 1...(60 * 11) {
                t = 100 + Double(i) / 60
                while next < script.count, 100 + script[next].at <= t { script[next].run(blob); next += 1 }
                blob.step()
                let p = blob.pose
                r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(blob.jiggle))
                r.swell = max(r.swell, p.sx - 1, p.sy - 1)
                r.squash = max(r.squash, 1 - p.sx, 1 - p.sy)
                r.glow = max(r.glow, p.glow)
                if blob.shownFace == .star { r.stars += 1 }
                if blob.blinkAt != lastBlink { r.blinks += 1; lastBlink = blob.blinkAt }
            }
            r.age = blob.age
            return r
        }
        let calm = run(reduce: true), lively = run(reduce: false)
        check(lively.moved > 0.2, "Tomo hops and shakes for a win, a miss, a poke, a level-up and a birthday")
        check(calm.moved == 0 && calm.squash == 0 && calm.swell <= 0.046,
              String(format: "under Reduce Motion they're a puff (%.1f%% at most): no hop, shake, tip or squash",
                     calm.swell * 100))
        check(calm.glow > 0.4 && calm.stars > 120,
              String(format: "under Reduce Motion a level-up and a birthday still glow (%.2f) with star eyes (%.1f s)",
                     calm.glow, Double(calm.stars) / 60))
        check(calm.age == 1, "under Reduce Motion a birthday still swaps Tomo's shape")
        check(calm.sparkles == 2 && lively.sparkles == 6, "under Reduce Motion a win has a third of the sparkles (6 → 2)")
        check(calm.blinks > 0, "under Reduce Motion Tomo still blinks")
    }

    /// The small touches: a poke flops the ears or sprout (not under Reduce Motion), a level-up shows star eyes that
    /// rock (still under Reduce Motion), and love from resting on Tomo waits 6 s between shows.
    static func touchesSelfTest(_ check: (Bool, String) -> Void) {
        func flop(reduce: Bool) -> (sway: CGFloat, jiggle: CGFloat) {
            let blob = TomoBlob(look: .mascot)
            blob.reduceMotion = reduce
            var t = 100.0
            blob.clock = { t }
            blob.step()
            blob.poke()
            var most: (sway: CGFloat, jiggle: CGFloat) = (0, 0)
            for i in 1...30 {
                t = 100 + Double(i) / 60
                blob.step()
                most = (max(most.sway, abs(blob.sway)), max(most.jiggle, abs(blob.jiggle)))
            }
            return most
        }
        let lively = flop(reduce: false), calm = flop(reduce: true)
        check(lively.sway > 0.3 && lively.jiggle > 0.05,
              String(format: "a poke flops Tomo's ears or sprout (%.2f rad) and wobbles it", lively.sway))
        // What sway is left follows the eyes' small darts (a few hundredths), not the poke.
        check(calm.sway < 0.05 && calm.jiggle == 0,
              String(format: "under Reduce Motion a poke doesn't flop (%.3f rad) or wobble", calm.sway))

        let blob = TomoBlob(look: .mascot)
        var t = 100.0
        blob.clock = { t }
        blob.step()
        blob.levelUp()
        let rocks = Set((0..<8).map { blob.starRock(t + Double($0) * 0.1) }).count > 1
        blob.reduceMotion = true
        let still = (0..<8).allSatisfy { blob.starRock(t + Double($0) * 0.1) == 0 }
        t += 1
        blob.step()
        check(blob.shownFace == .star && rocks && still,
              "a level-up shows star eyes, rocking (still under Reduce Motion)")

        var love = TomoLoveCooldown()
        let first = love.show(at: 50), soon = love.show(at: 53), waiting = love.ready(at: 55.9)
        let later = love.show(at: 56.5), again = love.show(at: 60)
        check(first && !soon && !waiting && later && !again,
              "love from resting on Tomo (Mac pointer, iPhone long press) shows at most once every 6 s")
    }

    /// The big moments' scripts, on a clock only the check moves: each step fires once, at its time, however the frames
    /// fall; a level-up keeps #130's timings; what the game sends with a level-up adds nothing; a newer script closes an
    /// older one's pending swap; a moment that passed unseen only swaps the shape; and under Reduce Motion its puff never
    /// adds to another (the rest of Reduce Motion: motionSelfTest).
    static func cueSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob() -> TomoBlob {
            t = 100
            let b = TomoBlob(look: .mascot)
            b.clock = { t }
            b.step()
            return b
        }

        // Frames repeated, uneven and far apart: every step fires once, never early, at the first frame past its time,
        // and each move starts at its step's own time.
        let b1 = blob()
        b1.grow(to: 1)
        var onTime = b1.cue != nil, exact = true, swappedAt: Double?
        if let c = b1.cue {
            for s in [0.0, 0.0, 0.1, 0.37, 0.37, 0.6, 0.62, 0.62, 0.9, 1.25, 1.25, 1.9, 2.5] {
                t = 100 + s
                b1.step()
                let due = c.steps.filter { c.start + $0.at <= t }.count
                onTime = onTime && c.next == due && c.fired.count == due
                    && zip(c.fired, c.steps).allSatisfy { $0 >= c.start + $1.at }
                exact = exact && b1.moves.filter(\.byCue).allSatisfy { m in c.steps.contains { c.start + $0.at == m.start } }
                if swappedAt == nil, b1.age == 1 { swappedAt = s }
            }
        }
        check(onTime && exact && swappedAt == 0.62,
              "a script's steps each fire once, at their times (a birthday's new shape at 0.62 s), however the frames fall")

        // The level-up (#130): squeeze (0–0.35 s), leap with star eyes, land (0.95–1.3 s), settle happy, over at 2.1 s.
        let b2 = blob()
        b2.setState(.finished)
        b2.levelUp()
        var squeezed: CGFloat = 1, top: (dy: CGFloat, at: Double) = (0, 0), landed: CGFloat = 1
        var faces: [Face] = []
        for i in 1...127 {
            t = 100 + Double(i) / 60
            b2.step()
            let p = b2.pose, s = Double(i) / 60
            if s < 0.35 { squeezed = min(squeezed, p.sy) }
            if p.dy < top.dy { top = (p.dy, s) }
            if s > 0.95 && s < 1.3 { landed = min(landed, p.sy) }
            if [12, 39, 114].contains(i) { faces.append(b2.shownFace) }   // at 0.2, 0.65 and 1.9 s
        }
        check(squeezed < 0.85 && top.dy < -0.4 && abs(top.at - 0.65) < 0.05 && landed < 0.85
              && faces == [.squeeze, .star, .happy] && b2.cue == nil,
              String(format: "a level-up squeezes, leaps (highest at %.2f s) with star eyes, lands squashed, settles happy, and ends at 2.1 s",
                     top.at))

        // What celebrate sends with a level-up (the win's state, .proud), in either order, adds no hop and no sparkles.
        func leap(_ order: Int) -> (pose: [CGFloat], early: Int) {
            let b = blob()
            if order == 1 { b.setState(.finished); b.emote(.proud) }
            b.levelUp()
            var pose: [CGFloat] = [], early = 0
            for i in 1...126 {
                t = 100 + Double(i) / 60
                if order == 2, i == 1 { b.setState(.finished); b.emote(.proud) }   // the state arrives a frame later
                b.step()
                pose += [b.pose.dx, b.pose.dy, b.pose.rot, b.pose.sx, b.pose.sy, b.pose.glow]
                if i < 22 { early += b.bits.count }                               // before the burst at 0.38 s
            }
            return (pose, early)
        }
        let alone = leap(0), sent = leap(1), later = leap(2)
        check(sent.pose == alone.pose && later.pose == alone.pose && sent.early == 0 && later.early == 0,
              "the game's win and .proud, sent with a level-up in either order, add no hop and no sparkles to it")

        // A newer script closes what an older one opened: a level-up mid-birthday shows the birthday's new shape now.
        let b3 = blob()
        b3.grow(to: 1)
        t = 100.3
        b3.step()
        let before = b3.age
        b3.levelUp()
        let closed = b3.age == 1 && b3.cue?.swap == nil
            && !b3.moves.contains { if case .evolve = $0.kind { return true } else { return false } }
        b3.grow(to: 1)                                  // the same birthday heard again: nothing more
        t = 100.7
        b3.step()
        let leveling = b3.shownFace == .star
        b3.grow(to: 2)                                  // then a birthday over a birthday
        t = 101
        b3.step()
        b3.grow(to: 3)
        let skipped = b3.age == 2
        t = 105
        b3.step()
        check(before == 0 && closed && leveling && skipped && b3.age == 3 && b3.cue == nil,
              "a newer script closes an older one's pending shape swap (a level-up or a birthday over a birthday)")

        // Unseen (a hidden island, an app in the background): when Tomo is drawn again, only the shape has changed.
        let b4 = blob()
        b4.grow(to: 1)
        t = 105
        b4.step()
        check(b4.age == 1 && b4.cue == nil && b4.bits.isEmpty && b4.jiggle == 0 && !b4.moves.contains(where: \.byCue),
              "a birthday that passed unseen only swaps the shape: no late drops, sparkles or jiggle")

        // Under Reduce Motion a big moment's puff doesn't add to one already running (a poke's, a fidget's).
        let b5 = blob()
        b5.reduceMotion = true
        b5.poke()
        t = 100.1
        b5.step()
        b5.levelUp()
        var swell: CGFloat = 0
        for i in 1...60 {
            t = 100.1 + Double(i) / 60
            b5.step()
            swell = max(swell, b5.pose.sx - 1, b5.pose.sy - 1)
        }
        check(swell <= 0.046, String(format: "under Reduce Motion a level-up's puff doesn't add to a poke's (%.1f%% at most)",
                                     swell * 100))
    }
}


// MARK: - Views

/// Tomo on its own: a Canvas redrawn every frame. Shells that know where the pointer is set `gaze`.
/// `look`: nil for the learner's own Tomo. It follows Reduce Motion (`TomoMotion`).
public struct TomoBlobView: View {
    @StateObject private var blob: TomoBlob
    public var state: BotState
    public var growth: CGFloat
    public var gaze: (() -> CGPoint)?

    public init(state: BotState = .idle, growth: CGFloat, look: TomoLook? = nil, gaze: (() -> CGPoint)? = nil) {
        _blob = StateObject(wrappedValue: TomoBlob(look: look, motion: .shared))
        self.state = state
        self.growth = growth
        self.gaze = gaze
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                blob.frameDate = timeline.date
                if let g = gaze?() { blob.lookX = g.x; blob.lookY = g.y }
                blob.step()
                blob.draw(context, size: size)
            }
        }
        .onChange(of: state) { _, s in blob.setState(s) }
        .onChange(of: growth) { _, g in blob.grow(to: g) }
        .onAppear {
            blob.setState(state, force: true)
            blob.setGrowth(growth)
        }
        .tomoReactions(blob)
    }
}

/// Reduce Motion for every live Tomo: the one setting their TomoBlobs follow (`TomoBlobView`, `TomoLiveAvatar`, the
/// Mac's island). The shell sets it from the system and follows changes (`follow`); TomoCore never reads the system.
/// TOMO_REDUCE_MOTION=1 turns it on, for snapshots and renders.
@MainActor
public final class TomoMotion: ObservableObject {
    public static let shared = TomoMotion()
    /// TOMO_REDUCE_MOTION=1: on, whatever the system says.
    public nonisolated static let forced = ProcessInfo.processInfo.environment["TOMO_REDUCE_MOTION"] == "1"
    @Published public private(set) var reduce = TomoMotion.forced
    private var watch: NSObjectProtocol?

    private init() {}

    /// The shell's system setting, once at launch: `system` now, and again each time `center` posts `name`.
    public func follow(_ center: NotificationCenter, _ name: Notification.Name,
                       system: @escaping @MainActor @Sendable () -> Bool) {
        reduce = Self.forced || system()
        watch = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reduce = Self.forced || system() }
        }
    }
}

public extension View {
    /// Tomo reacts to the game's notifications (talk, nudge, greet, grow, level-ups, emotes, pokes).
    func tomoReactions(_ blob: TomoBlob) -> some View {
        modifier(TomoBlobMoves(blob: blob)).modifier(TomoBlobReactions(blob: blob))
    }
}

private struct TomoBlobMoves: ViewModifier {
    public let blob: TomoBlob

    public func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .botTalk)) { _ in blob.talk() }
            .onReceive(NotificationCenter.default.publisher(for: .botNudge)) { _ in blob.nudge() }
            .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in blob.greet() }
            .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in blob.gulp() }
            .onReceive(NotificationCenter.default.publisher(for: .botLevelUp)) { _ in blob.levelUp() }
            .onReceive(NotificationCenter.default.publisher(for: .botGrow)) { n in
                if let t = n.object as? CGFloat { blob.grow(to: t) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botSetGrowth)) { n in
                if let t = n.object as? CGFloat { blob.setGrowth(t) }
            }
    }
}

private struct TomoBlobReactions: ViewModifier {
    public let blob: TomoBlob

    public func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { n in
                if let e = n.object as? BotEmote { blob.emote(e) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in blob.poke() }
            .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in blob.blink() }
            .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { n in
                if let s = n.object as? CGFloat { blob.setHover(s) }
            }
    }
}


/// Tomo held in one pose, for places that can't animate: widgets and Live Activities only redraw when
/// their content changes (decisions.md, 2026-10-06). Drawn by the same TomoBlob, half a second into
/// `state` (and `emote`), so it's never caught mid-blink and a win still has its sparkles. These places
/// show the mascot unless given a look.
public struct TomoBlobStill: View {
    var state: BotState
    var emote: BotEmote?
    var growth: CGFloat
    var look: TomoLook

    public init(state: BotState = .idle, emote: BotEmote? = nil, growth: CGFloat, look: TomoLook = .mascot) {
        self.state = state
        self.emote = emote
        self.growth = growth
        self.look = look
    }

    public var body: some View {
        Canvas { context, size in
            let blob = TomoBlob(look: look)
            var t = 100.0
            blob.clock = { t }
            blob.setGrowth(growth)
            blob.step()
            blob.setState(state, force: true)
            if let emote { blob.emote(emote) }
            t += 0.5
            blob.step()
            blob.draw(context, size: size)
        }
    }
}
