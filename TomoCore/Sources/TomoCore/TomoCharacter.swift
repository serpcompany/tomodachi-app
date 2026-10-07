import SwiftUI

// MARK: - Tomo, the blob
//
// Every Tomo is a blob of its own, drawn and animated by our own code (decisions.md, 2026-10-07). What it
// looks like comes from its seed (TomoLook.swift): a colour and eyes for life, and a new form at every
// birthday. Growth is an age step, 0 = 1さい … 5 = 6さい; each birthday it squeezes down, flashes and pops out
// in its next form.
// The app drives it through notifications (docs/architecture.md, "Character"): the task state
// (`AppState.effectiveState`), `.botTalk`, `.botNudge`, `.botGrow`, `.botGreet`, `.botGulp`,
// `.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`.

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

    /// Whose Tomo this is. Nil: the learner's own (`TomoLook.current`), changing with a pop when it does.
    public let fixedLook: TomoLook?
    public private(set) var look: TomoLook

    public init(look: TomoLook? = nil) {
        fixedLook = look
        self.look = look ?? TomoLook.current
    }

    /// The age step on show (0 = 1さい), and the one it's growing into.
    public private(set) var age = 0
    private var swap: (at: Double, age: Int, look: TomoLook)?

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

    /// "Over here!": a double hop with a wiggle.
    public func nudge() { stir(); add(.nudge, 0.75); blink() }

    public func greet() {
        stir()
        add(.hop(0.25), 0.45); add(.wiggle(6), 0.8)
        flash = (.happy, clock() + 1.4)
        emit(.sparkle, 3)
    }

    /// Eating (feed): two gulps.
    public func gulp() { stir(); add(.gulp, 0.6) }

    /// Clicked on Tomo. Three pokes in a row make it dizzy.
    public func poke() {
        stir()
        let now = clock()
        add(.squish, 0.35)
        flash = (.squeeze, now + 0.5)
        pokes = pokes.filter { now - $0 < 2.5 } + [now]
        if pokes.count >= 3 {
            pokes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        }
    }

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

    /// Grow up (or reset) to an age step. Growing up evolves: squeeze, flash, pop out in the next form.
    public func grow(to target: CGFloat) {
        stir()
        let next = Self.ageStep(target)
        if next > (swap?.age ?? age) {
            evolve(to: next, look: swap?.look ?? look)
            emit(.sparkle, 8)
        } else {
            setGrowth(target)
        }
    }

    /// Jump straight to an age step (no animation).
    public func setGrowth(_ value: CGFloat) {
        age = Self.ageStep(value)
        swap = nil
    }

    private static func ageStep(_ v: CGFloat) -> Int { min(max(Int(v.rounded()), 0), TomoLook.ages - 1) }

    private func evolve(to next: Int, look next2: TomoLook) {
        add(.evolve, 0.9)
        swap = (clock() + 0.4, next, next2)
    }

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
        if fixedLook == nil, TomoLook.current != (swap?.look ?? look) {
            evolve(to: swap?.age ?? age, look: TomoLook.current)
        }
        if let s = swap, now >= s.at {
            age = s.age; look = s.look; swap = nil
            emit(.pop, 12)
            jiggleVel += 6
        }

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

        // Fidgets while waiting; dozing when ignored for a while.
        let calm = state == .idle || state == .question || state == .thinking
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
            bits[i].age += elapsed
            bits[i].pos.x += bits[i].vel.dx * dt
            bits[i].pos.y += bits[i].vel.dy * dt
            bits[i].vel.dy += bits[i].kind.gravity * dt
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

        if form.details.contains(.sprout) { drawSprout(ctx, form: form, R: R) }
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
    }

    private func drawBody(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, glow: CGFloat) {
        let body = form.path(R: R)
        let top = -form.top * R, bottom = form.bottom * R
        ctx.fill(body, with: .linearGradient(Gradient(colors: [look.bodyLight, look.body]),
                                             startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        var inner = ctx
        inner.clip(to: body)
        // A soft shade along the bottom, so it sits on something.
        inner.fill(Path(ellipseIn: CGRect(x: -R * 1.4, y: bottom - R * 0.35, width: R * 2.8, height: R * 0.9)),
                   with: .color(.black.opacity(0.08)))
        if form.details.contains(.spots) {
            var rng = form.spotSeed
            for _ in 0..<4 {
                rng = (rng * 9301 + 0.4929).truncatingRemainder(dividingBy: 1)
                let x = (CGFloat(rng) * 1.4 - 0.7) * form.rx
                rng = (rng * 9301 + 0.4929).truncatingRemainder(dividingBy: 1)
                let y = (CGFloat(rng) * 0.9 - 0.2) * form.ry
                let r = R * (0.08 + 0.06 * CGFloat(rng))
                guard abs(y - form.faceY) > 0.25 || abs(x) > form.faceW * 0.55 else { continue }
                inner.fill(Path(ellipseIn: CGRect(x: x * R - r, y: y * R - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(0.22)))
            }
        }
        if form.details.contains(.sheen) {
            inner.fill(Path(ellipseIn: CGRect(x: -R * 0.62, y: top + R * 0.2, width: R * 0.36, height: R * 0.22))
                        .applying(CGAffineTransform(rotationAngle: -0.5)),
                       with: .color(.white.opacity(0.4)))
        }
        if glow > 0.01 { inner.fill(body, with: .color(.white.opacity(Double(glow)))) }
    }

    /// A little sprout on top that sways after every move.
    private func drawSprout(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat) {
        var c = ctx
        c.translateBy(x: 0, y: -form.top * R + R * 0.06)
        c.rotate(by: .radians(Double(form.sproutLean + sway * 0.9)))
        let L = R * 0.3
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

    private func drawFace(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, now: Double, mouth: CGFloat) {
        let face = flash?.face ?? (drowsy ? .sleepy : baseFace)
        let fit = min(1, form.faceW / 0.8) * (isMini ? 1.4 : 1)       // a small face gets smaller eyes
        let fx = look2.x * R * 0.16 * form.faceW, fy = -look2.y * R * 0.1 + form.faceY * R
        let ew = look.eyeW * R * fit, eh = look.eyeH * R * fit
        let gap = look.eyeGap * R * max(0.7, fit)
        let eyeY = fy - eh * 0.2

        // Cheeks: a blush when it's loved; some Tomos have rosy cheeks all the time.
        let rosy: CGFloat = form.details.contains(.cheeks) ? 0.5 : 0
        let cheekA = max(rosy, 0.9 * blush)
        if cheekA > 0.02 {
            for side: CGFloat in [-1, 1] {
                let far = 1 - 0.3 * max(0, -side * look2.x)
                let c = CGPoint(x: side * (gap + ew * 1.6) + fx * 0.6, y: eyeY + eh * 0.75)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.11 * far, y: c.y - R * 0.06, width: R * 0.22 * far, height: R * 0.12)),
                         with: .color(look.cheek.opacity(Double(cheekA))))
            }
        }
        if form.details.contains(.freckles) {
            for side: CGFloat in [-1, 1] {
                for (dx, dy) in [(-0.06, 0.0), (0.05, -0.02), (0.0, 0.06)] as [(CGFloat, CGFloat)] {
                    let c = CGPoint(x: side * (gap + ew * 1.4) + fx * 0.6 + dx * R, y: eyeY + eh * 0.7 + dy * R)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.018, y: c.y - R * 0.018, width: R * 0.036, height: R * 0.036)),
                             with: .color(look.ink.opacity(0.35)))
                }
            }
        }

        // Eyes
        let since = now - blinkAt
        let open: CGFloat = since < 0.09 ? CGFloat(1 - since / 0.09)
                          : since < 0.2 ? CGFloat((since - 0.09) / 0.11) : 1
        for side: CGFloat in [-1, 1] {
            var c = ctx
            c.translateBy(x: side * gap + fx, y: eyeY)
            c.scaleBy(x: 1 - 0.25 * max(0, -side * look2.x), y: 1)   // the eye turning away narrows
            drawEye(c, face: face, side: side, w: ew, h: eh, open: max(0.08, open), now: now)
        }

        // Mouth: opens to talk, eat, yawn and gasp; hidden otherwise.
        let o = min(1, mouth + (face == .surprised ? 0.4 : 0))
        if o > 0.03 {
            let mw = R * (0.07 + 0.05 * o), mh = R * 0.16 * o
            let my = eyeY + eh * 0.75 + R * 0.06
            ctx.fill(Path(roundedRect: CGRect(x: fx * 1.2 - mw, y: my, width: mw * 2, height: max(R * 0.03, mh)),
                          cornerRadius: mw), with: .color(look.ink))
        }
    }

    private func drawEye(_ ctx: GraphicsContext, face: Face, side: CGFloat, w: CGFloat, h: CGFloat, open: CGFloat, now: Double) {
        let ink = GraphicsContext.Shading.color(look.ink)
        let line = StrokeStyle(lineWidth: w * 1.15, lineCap: .round, lineJoin: .round)
        func bar(_ k: CGFloat, dy: CGFloat = 0) {
            let rh = h * k * open
            ctx.fill(TomoForm.superellipse(rx: w * k, ry: rh, n: look.eyeN).offsetBy(dx: 0, dy: dy), with: ink)
            if open > 0.6 {
                let s = w * k * 0.32
                ctx.fill(Path(ellipseIn: CGRect(x: w * k * 0.15 - s, y: dy - rh * 0.5 - s, width: s * 2, height: s * 2)),
                         with: .color(.white.opacity(0.85)))
            }
        }
        func smile() {
            var p = Path()
            p.move(to: CGPoint(x: -w * 1.5, y: h * 0.25))
            p.addQuadCurve(to: CGPoint(x: w * 1.5, y: h * 0.25), control: CGPoint(x: 0, y: -h * 0.85))
            ctx.stroke(p, with: ink, style: line)
        }
        switch face {
        case .normal: bar(1)
        case .surprised: bar(1.22)
        case .confused: side < 0 ? bar(0.72, dy: -h * 0.15) : bar(1.12)
        case .happy: smile()
        case .wink: side > 0 ? smile() : bar(1)
        case .sleep:
            var p = Path()
            p.move(to: CGPoint(x: -w * 1.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 1.5, y: 0), control: CGPoint(x: 0, y: h * 0.6))
            ctx.stroke(p, with: ink, style: line)
        case .sleepy:
            ctx.fill(TomoForm.superellipse(rx: w * 1.15, ry: h * 0.3, n: look.eyeN).offsetBy(dx: 0, dy: h * 0.35), with: ink)
        case .flat:
            ctx.fill(Path(roundedRect: CGRect(x: -w * 1.6, y: -w * 0.5, width: w * 3.2, height: w), cornerRadius: w * 0.5), with: ink)
        case .squeeze:
            var p = Path()
            let d = -side          // left eye ">", right eye "<"
            p.move(to: CGPoint(x: -w * 1.2 * d, y: -h * 0.55))
            p.addLine(to: CGPoint(x: w * 1.1 * d, y: 0))
            p.addLine(to: CGPoint(x: -w * 1.2 * d, y: h * 0.55))
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: w * 0.95, lineCap: .round, lineJoin: .round))
        case .love:
            ctx.fill(heart(size: h * 1.9), with: .color(Palette.heart))
        case .dizzy:
            let a = CGFloat(now * 7) * side
            let r = max(w * 1.5, h * 0.6)
            var p = Path()
            p.addArc(center: .zero, radius: r * 0.95, startAngle: .radians(Double(a)),
                     endAngle: .radians(Double(a) + 5), clockwise: false)
            p.addArc(center: .zero, radius: r * 0.42, startAngle: .radians(Double(a) + 5),
                     endAngle: .radians(Double(a) + 9), clockwise: false)
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: w * 0.7, lineCap: .round))
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
    }

    private func emit(_ kind: Bit.Kind, _ count: Int) {
        guard !isMini else { return }
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
    }

    private func drawBits(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat) {
        for b in bits {
            var c = ctx
            c.opacity = max(0, 1 - b.age / b.life)
            c.translateBy(x: center.x + b.pos.x * R, y: center.y + b.pos.y * R)
            c.rotate(by: .radians(Double(b.spin) * b.age))
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

    private enum Face { case normal, happy, sleep, sleepy, squeeze, surprised, love, confused, dizzy, wink, flat }

    private struct Move {
        public enum Kind {
            case hop(CGFloat), nudge, shake, wiggle(Int), gulp, rock, squish, wobble, mouth
            case peep, stretch, tiltHold(CGFloat), shuffle, lean(CGFloat), evolve
        }
        public let kind: Kind
        public let start: Double
        public let duration: Double
    }

    private struct Pose {
        public var dx: CGFloat = 0, dy: CGFloat = 0, rot: CGFloat = 0
        public var sx: CGFloat = 1, sy: CGFloat = 1
        public var mouth: CGFloat = 0, glow: CGFloat = 0
    }

    private func add(_ kind: Move.Kind, _ duration: Double) {
        moves.append(Move(kind: kind, start: clock(), duration: duration))
    }

    private func pose(at now: Double) -> Pose {
        var p = Pose()
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
                p.dy += 0.1 * abs(sin(q * 2 * .pi)); p.mouth = max(p.mouth, max(0, sin(q * 4 * .pi)))
                p.sy *= 1 - 0.06 * abs(sin(q * 2 * .pi))
            case .rock:
                p.rot += sin(q * 4 * .pi) * 0.13 * (1 - q * 0.6)
            case .squish:
                p.sy *= 1 - 0.2 * arc; p.sx *= 1 + 0.15 * arc
            case .wobble:
                p.rot += sin(q * 7 * .pi) * 0.16 * (1 - q)
            case .mouth:
                p.mouth = max(p.mouth, arc); p.dy -= 0.04 * arc
            case .peep:
                p.mouth = max(p.mouth, 0.55 * arc); p.dy -= 0.05 * arc
            case .stretch:
                p.sy *= 1 + 0.09 * arc; p.sx *= 1 - 0.05 * arc
            case .tiltHold(let a):
                p.rot += a * Self.hold(q)
            case .shuffle:
                p.dx += sin(q * 4 * .pi) * 0.05; p.rot += sin(q * 4 * .pi) * 0.05
            case .lean(let side):
                let e = Self.hold(q)
                p.rot += side * 0.16 * e; p.dy += 0.05 * e; p.sy *= 1 - 0.04 * e
            case .evolve:                          // squeeze down glowing, then pop out in the next form
                let swapAt: CGFloat = 0.45
                if q < swapAt {
                    let e = q / swapAt
                    let s = 1 - 0.35 * e * e
                    p.sx *= s; p.sy *= s; p.rot += sin(e * 6 * .pi) * 0.06 * e
                } else {
                    let e = (q - swapAt) / (1 - swapAt)
                    let s = 1 - 0.35 * (1 - e) * (1 - e) + 0.18 * sin(.pi * e) * (1 - e)
                    p.sx *= s; p.sy *= s
                }
                p.glow = max(p.glow, 0.85 * max(0, 1 - abs(q - swapAt) / 0.25))
            }
        }
        return p
    }

    /// 0 → 1 → hold → 0 envelope with eased edges.
    private static func hold(_ q: CGFloat) -> CGFloat {
        let e = min(1, min(q, 1 - q) * 4)
        return e * e * (3 - 2 * e)
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


// MARK: - Views

/// Tomo on its own: a Canvas redrawn every frame. Shells that know where the pointer is set `gaze`.
/// `look`: nil for the learner's own Tomo.
public struct TomoBlobView: View {
    @StateObject private var blob: TomoBlob
    public var state: BotState
    public var growth: CGFloat
    public var gaze: (() -> CGPoint)?

    public init(state: BotState = .idle, growth: CGFloat, look: TomoLook? = nil, gaze: (() -> CGPoint)? = nil) {
        _blob = StateObject(wrappedValue: TomoBlob(look: look))
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

public extension View {
    /// Tomo reacts to the game's notifications (talk, nudge, greet, grow, emotes, pokes).
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
