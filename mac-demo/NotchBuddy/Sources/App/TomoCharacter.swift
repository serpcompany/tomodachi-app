import SwiftUI

// MARK: - Tomo, the chick
//
// Tomo is a hiyoko (baby chick), drawn and animated by our own code. Growth:
//   0 = 1さい: sits in the bottom half of its eggshell, one head feather
//   1 = 2さい: hatched; the shell drops away, feet and a second feather appear
//   2 = 3さい: a little bigger, a third feather
// The app drives it through notifications (docs/architecture.md, "Character"): the task state
// (`AppState.effectiveState`), `.botTalk`, `.botNudge`, `.botGrow`, `.botGreet`, `.botGulp`,
// `.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`.

@MainActor
final class TomoChick: ObservableObject {
    /// Where the cursor is, −1…1 (positive y = above Tomo).
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0
    /// Extra canvas height above Tomo for particles (the canvas is taller than it is wide).
    var particleOverhang: CGFloat = 0
    /// Small, decorative copy (no particles, wanders its gaze).
    var isMini = false
    /// The time source: real time in the app, a scripted clock when rendering offline.
    var clock: () -> Double = { CACurrentMediaTime() }
    /// Seconds with nothing happening (no cursor movement, no events) before Tomo dozes off.
    var dozeAfter: Double = 45
    /// The frame being drawn (set by the view; reading it ties the Canvas to the frame timer).
    var frameDate = Date()

    /// 0 = 1さい (in the shell), 1 = 2さい (hatched), 2 = 3さい. Springs toward `growthTarget`.
    var growth: CGFloat = 0
    private var growthTarget: CGFloat = 0
    private var growthVel: CGFloat = 0

    private(set) var state: BotState = .idle
    private var baseFace: Face = .normal
    private var flash: (face: Face, until: Double)?
    private var moves: [Move] = []
    private var bits: [Bit] = []
    private var pose = Pose()              // this frame's moves, summed in step()

    // Smoothed values and secondary motion
    private var look = CGPoint.zero
    private var glance: (to: CGPoint, until: Double)?
    private var saccade = CGPoint.zero
    private var wander = CGPoint.zero
    private var tilt: CGFloat = 0
    private var puff: CGFloat = 1
    private var puffTarget: CGFloat = 1
    private var blush: CGFloat = 0
    private var tuftSwing: CGFloat = 0
    private var tuftVel: CGFloat = 0
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

    func setState(_ s: BotState, force: Bool = false) {
        guard s != state || force else { return }
        stir()
        let previous = state
        state = s
        baseFace = Self.face(for: s)
        let now = clock()
        switch s {
        case .finished:                       // got it right: hop, flap, sparkles
            add(.hop(0.3), 0.45); add(.flap(4), 0.5); add(.rock, 0.9)
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

    func blink() { blinkAt = clock() }

    /// One beak flap per spoken line.
    func talk() { stir(); add(.beak, 0.28) }

    /// "Over here!": a double hop with a wing flap.
    func nudge() { stir(); add(.nudge, 0.75); blink() }

    func greet() {
        stir()
        add(.hop(0.25), 0.45); add(.flap(6), 0.8)
        flash = (.happy, clock() + 1.4)
        emit(.sparkle, 3)
    }

    /// Eating (feed): two pecks.
    func gulp() { stir(); add(.peck, 0.6) }

    /// Clicked on Tomo. Three pokes in a row make it dizzy.
    func poke() {
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

    func emote(_ e: BotEmote) {
        stir()
        let now = clock()
        switch e {
        case .love:      flash = (.love, now + 1.8); blush = 1; emit(.heart, 4)
        case .surprised: flash = (.surprised, now + 1.2); add(.hop(0.2), 0.4); add(.beak, 0.6)
        case .proud:     flash = (.happy, now + 1.8); add(.hop(0.15), 0.4); emit(.sparkle, 4)
        case .wink:      flash = (.wink, now + 0.9)
        case .yawn:      flash = (.sleepy, now + 1.6); add(.beak, 1.2)
        case .happy:     flash = (.happy, now + 1.4); add(.flap(3), 0.4)
        case .annoyed:   flash = (.flat, now + 1.2); add(.shake, 0.3)
        }
    }

    /// Cursor over Tomo: puff up a little.
    func setHover(_ scale: CGFloat) {
        if scale > 1 { stir() }
        puffTarget = scale > 1 ? 1.05 : 1
    }

    /// Grow up (or reset) to an age step.
    func grow(to target: CGFloat) {
        stir()
        if target > growthTarget {
            add(.flap(5), 0.7); add(.hop(0.3), 0.5)
            emit(.sparkle, 8)
            if growthTarget < 1 && target >= 1 { emit(.shell, 8) }
        }
        growthTarget = target
    }

    /// Jump straight to an age step (no animation).
    func setGrowth(_ value: CGFloat) {
        growth = value; growthTarget = value; growthVel = 0
    }

    /// Something small Tomo does on its own between events, so it never sits frozen:
    /// a glance, a peep, a wing stretch, a curious tilt, a shuffle, preening, or a little hop.
    func fidget() {
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
            add(.preen(Bool.random() ? 1 : -1), 1.0)
            flash = (.sleep, now + 0.7)
        default: add(.hop(0.12), 0.35); add(.flap(2), 0.35)
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

    func step() {
        let now = clock()
        if !started {
            started = true
            born = now - .random(in: 0...4)
            lastTime = now; lastStir = now
            nextBlink = now + 1.5; nextFidget = now + .random(in: 2...4)
        }
        // Real elapsed time: if macOS pauses the frame timer (screen asleep, window hidden),
        // particles and timers still catch up instead of freezing. Smoothing is stable for any step.
        let elapsed = max(0, now - lastTime)
        lastTime = now
        let dt = CGFloat(min(elapsed, 1))
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
        look.x += (target.x - look.x) * kLook
        look.y += (target.y - look.y) * kLook
        tilt += (Self.tilt(for: state) - tilt) * kSoft
        puff += (puffTarget - puff) * kSoft
        blush += (0 - blush) * (1 - pow(0.4, dt))

        // Springs, in small substeps: growth (a little overshoot, like a pop) and the head
        // feathers, which lag behind the body's moves and wobble back.
        if dt > 0 {
            let vy = (pose.dy - lastDy) / dt
            let vx = (pose.dx - lastDx) / dt
            let vr = (pose.rot + tilt - lastRot) / dt
            let swingTarget = max(-0.6, min(0.6, -vr * 0.08 - vx * 0.6 - look.x * 0.1))
            var left = dt
            while left > 0 {
                let h = min(left, 1.0 / 120)
                let w: CGFloat = 9, zeta: CGFloat = 0.55
                growthVel += (w * w * (growthTarget - growth) - 2 * zeta * w * growthVel) * h
                growth += growthVel * h
                let ws: CGFloat = 18, zs: CGFloat = 0.18
                tuftVel += (ws * ws * (swingTarget - tuftSwing) - 2 * zs * ws * tuftVel - vy * 4) * h
                tuftSwing += tuftVel * h
                left -= h
            }
        }
        lastDy = pose.dy; lastDx = pose.dx; lastRot = pose.rot + tilt

        // Blinks
        if now > nextBlink {
            if state != .sleeping && state != .dizzy {
                blinkAt = now
                if Double.random(in: 0...1) < 0.22 { secondBlinkAt = now + 0.26 }
            }
            nextBlink = now + .random(in: 2.2...5.4)
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

    func draw(_ context: GraphicsContext, size: CGSize) {
        let now = clock()
        let p = started ? pose : pose(at: now)
        let R = size.width * 0.3
        let ry = R * Shape.bodyRY
        let t = CGFloat(now - born)
        // Lean toward the cursor; nod off when drowsy.
        var rot = tilt + p.rot + look.x * 0.06
        var dy = p.dy
        if drowsy { rot += sin(t * 0.8) * 0.05; dy += max(0, sin(t * 0.8)) * 0.03 }
        let cx = size.width / 2 + (p.dx + look.x * 0.04) * R
        let cy = size.height / 2 + particleOverhang / 2 + dy * R + R * 0.06
        let g = 1 + 0.12 * max(0, growth)
        let breath = 1 + sin(t * 1.7) * (state == .sleeping || drowsy ? 0.035 : 0.018)
        let idleWing = 0.05 + 0.05 * sin(t * 1.7)

        // Anchor scaling and rocking at Tomo's feet, so squashes stay on the ground.
        var ctx = context
        ctx.translateBy(x: cx, y: cy + ry)
        ctx.rotate(by: .radians(Double(rot)))
        ctx.scaleBy(x: p.sx * puff * g, y: p.sy * puff * g * breath)
        ctx.translateBy(x: 0, y: -ry)

        drawTuft(ctx, R: R)
        drawWings(ctx, R: R, left: max(p.wingL, idleWing), right: max(p.wingR, idleWing))
        drawFeet(ctx, R: R)
        drawBody(ctx, R: R)
        drawFace(ctx, R: R, now: now, beak: p.beak)
        drawShell(ctx, R: R)

        if !isMini {
            let center = CGPoint(x: cx, y: cy)
            if state == .question { drawQuestionMark(context, center: center, R: R * g, t: t) }
            drawBits(context, center: center, R: R * g)
        }
    }

    // MARK: - Parts

    private enum Shape {
        static let bodyRX: CGFloat = 1.0
        static let bodyRY: CGFloat = 0.94
    }

    private enum Palette {
        static let bodyTop = Color(hex: "#FFE68C")
        static let bodyBottom = Color(hex: "#FFC53A")
        static let belly = Color(hex: "#FFF5CC")
        static let wing = Color(hex: "#F6BA2C")
        static let tuft = Color(hex: "#F3B226")
        static let beakTop = Color(hex: "#F7982B")
        static let beakBottom = Color(hex: "#E2771A")
        static let mouth = Color(hex: "#8A3413")
        static let cheek = Color(hex: "#FF8E6E")
        static let ink = Color(hex: "#2B1B0E")
        static let feet = Color(hex: "#EF8A2A")
        static let shell = Color(hex: "#FFFBF1")
        static let shellLine = Color(hex: "#E3D3B2")
        static let heart = Color(hex: "#FF5C8A")
    }

    private func drawBody(_ ctx: GraphicsContext, R: CGFloat) {
        let rx = R * Shape.bodyRX, ry = R * Shape.bodyRY
        let body = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Palette.bodyTop, Palette.bodyBottom]),
                                             startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: ry)))
        var inner = ctx
        inner.clip(to: body)
        inner.fill(Path(ellipseIn: CGRect(x: -R * 0.55, y: R * 0.05, width: R * 1.1, height: R * 0.8)),
                   with: .color(Palette.belly.opacity(0.55)))
    }

    /// Head feathers: one at 1さい, two at 2さい, three at 3さい.
    private func drawTuft(_ ctx: GraphicsContext, R: CGFloat) {
        let base = CGPoint(x: 0, y: -R * Shape.bodyRY * 0.9)
        let a1 = min(1, max(0, growth)), a2 = min(1, max(0, growth - 1))
        // One feather at 1さい; two splayed at 2さい; a fan of three at 3さい.
        let feathers: [(angle: Double, amount: CGFloat)] = [
            (Double(0.05 - 0.3 * a1 + 0.3 * a2), 1),
            (Double(0.35 * a1 + 0.2 * a2), a1),
            (-0.5, a2),
        ]
        for f in feathers where f.amount > 0.02 {
            var c = ctx
            c.translateBy(x: base.x, y: base.y)
            c.rotate(by: .radians(f.angle + Double(tuftSwing) * (0.8 + 0.2 * f.angle.magnitude)))
            let L = R * 0.32 * (0.4 + 0.6 * f.amount)
            var path = Path()
            path.move(to: .zero)
            path.addQuadCurve(to: CGPoint(x: R * 0.09, y: -L), control: CGPoint(x: -R * 0.13, y: -L * 0.55))
            c.stroke(path, with: .color(Palette.tuft.opacity(Double(f.amount))),
                     style: StrokeStyle(lineWidth: R * 0.11, lineCap: .round))
        }
    }

    private func drawWings(_ ctx: GraphicsContext, R: CGFloat, left: CGFloat, right: CGFloat) {
        for side: CGFloat in [-1, 1] {
            let lift = side < 0 ? left : right
            var c = ctx
            c.translateBy(x: side * R * 0.86, y: R * 0.02)
            c.rotate(by: .radians(Double(-side * (0.22 + lift * 1.15))))
            let wing = Path(ellipseIn: CGRect(x: -R * 0.16 + side * R * 0.05, y: -R * 0.04,
                                              width: R * 0.32, height: R * 0.56))
            c.fill(wing, with: .color(Palette.wing))
        }
    }

    private func drawFeet(_ ctx: GraphicsContext, R: CGFloat) {
        let a = min(1, max(0, growth))
        guard a > 0.02 else { return }
        for side: CGFloat in [-1, 1] {
            let foot = Path(ellipseIn: CGRect(x: side * R * 0.3 - R * 0.15, y: R * Shape.bodyRY * 0.9,
                                              width: R * 0.3, height: R * 0.15))
            ctx.fill(foot, with: .color(Palette.feet.opacity(Double(a))))
        }
    }

    private func drawFace(_ ctx: GraphicsContext, R: CGFloat, now: Double, beak: CGFloat) {
        let face = flash?.face ?? (drowsy ? .sleepy : baseFace)
        // Inside the shell the face sits higher, so the shell's edge stays below the beak.
        let inShell = 1 - min(1, max(0, growth))
        let fx = look.x * R * 0.16, fy = -look.y * R * 0.1 - inShell * R * 0.1
        let r = R * 0.105 * (isMini ? 1.5 : 1)

        // Cheeks
        for side: CGFloat in [-1, 1] {
            let far = 1 - 0.3 * max(0, -side * look.x)     // the cheek turning away gets narrower
            let c = CGPoint(x: side * R * 0.56 + fx * 0.6, y: R * 0.12 + fy)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.12 * far, y: c.y - R * 0.07, width: R * 0.24 * far, height: R * 0.14)),
                     with: .color(Palette.cheek.opacity(Double(0.42 + 0.45 * blush))))
        }

        // Eyes
        let since = now - blinkAt
        let open: CGFloat = since < 0.09 ? CGFloat(1 - since / 0.09)
                          : since < 0.2 ? CGFloat((since - 0.09) / 0.11) : 1
        for side: CGFloat in [-1, 1] {
            var c = ctx
            c.translateBy(x: side * R * 0.34 + fx, y: -R * 0.1 + fy)
            c.scaleBy(x: 1 - 0.25 * max(0, -side * look.x), y: 1)   // the eye turning away narrows
            drawEye(c, face: face, side: side, r: r, open: max(0.08, open), now: now)
        }

        // Beak (opens to talk, eat, yawn, gasp)
        let o = min(1, beak + (face == .surprised ? 0.35 : 0)) * R * 0.12
        var b = ctx
        b.translateBy(x: fx * 1.3, y: R * 0.07 + fy)
        if o > R * 0.006 {
            b.fill(Path(ellipseIn: CGRect(x: -R * 0.085, y: R * 0.06, width: R * 0.17, height: R * 0.05 + o * 1.25)),
                   with: .color(Palette.mouth))
        }
        let rounded = StrokeStyle(lineWidth: R * 0.03, lineJoin: .round)
        let lower = triangle(CGPoint(x: -R * 0.08, y: R * 0.085 + o), CGPoint(x: R * 0.08, y: R * 0.085 + o),
                             CGPoint(x: 0, y: R * 0.16 + o * 1.1))
        b.fill(lower, with: .color(Palette.beakBottom))
        b.stroke(lower, with: .color(Palette.beakBottom), style: rounded)
        let upper = triangle(CGPoint(x: -R * 0.12, y: R * 0.015), CGPoint(x: R * 0.12, y: R * 0.015),
                             CGPoint(x: 0, y: R * 0.13))
        b.fill(upper, with: .color(Palette.beakTop))
        b.stroke(upper, with: .color(Palette.beakTop), style: rounded)
    }

    private func drawEye(_ ctx: GraphicsContext, face: Face, side: CGFloat, r: CGFloat, open: CGFloat, now: Double) {
        let ink = GraphicsContext.Shading.color(Palette.ink)
        let line = StrokeStyle(lineWidth: r * 0.55, lineCap: .round, lineJoin: .round)
        func dot(_ size: CGFloat) {
            ctx.fill(Path(ellipseIn: CGRect(x: -size, y: -size * open, width: size * 2, height: size * 2 * open)), with: ink)
            if open > 0.6 {
                let s = size * 0.34
                ctx.fill(Path(ellipseIn: CGRect(x: size * 0.28 - s, y: -size * 0.36 - s, width: s * 2, height: s * 2)),
                         with: .color(.white))
            }
        }
        switch face {
        case .normal: dot(r)
        case .surprised: dot(r * 1.3)
        case .confused: dot(side < 0 ? r * 0.72 : r * 1.18)
        case .happy, .wink where side > 0:
            var p = Path()
            p.move(to: CGPoint(x: -r, y: r * 0.3))
            p.addQuadCurve(to: CGPoint(x: r, y: r * 0.3), control: CGPoint(x: 0, y: -r * 1.3))
            ctx.stroke(p, with: ink, style: line)
        case .wink: dot(r)
        case .sleep:
            var p = Path()
            p.move(to: CGPoint(x: -r, y: 0))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: r * 0.9))
            ctx.stroke(p, with: ink, style: line)
        case .sleepy:
            ctx.fill(Path(ellipseIn: CGRect(x: -r, y: 0, width: r * 2, height: r * 0.8)), with: ink)
        case .flat:
            var p = Path()
            p.move(to: CGPoint(x: -r, y: 0)); p.addLine(to: CGPoint(x: r, y: 0))
            ctx.stroke(p, with: ink, style: line)
        case .squeeze:
            var p = Path()
            let d = -side          // left eye ">", right eye "<"
            p.move(to: CGPoint(x: -r * 0.8 * d, y: -r * 0.75))
            p.addLine(to: CGPoint(x: r * 0.7 * d, y: 0))
            p.addLine(to: CGPoint(x: -r * 0.8 * d, y: r * 0.75))
            ctx.stroke(p, with: ink, style: line)
        case .love:
            ctx.fill(heart(size: r * 2.3), with: .color(Palette.heart))
        case .dizzy:
            let a = CGFloat(now * 7) * side
            var p = Path()
            p.addArc(center: .zero, radius: r * 0.95, startAngle: .radians(Double(a)),
                     endAngle: .radians(Double(a) + 5), clockwise: false)
            p.addArc(center: .zero, radius: r * 0.42, startAngle: .radians(Double(a) + 5),
                     endAngle: .radians(Double(a) + 9), clockwise: false)
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: r * 0.4, lineCap: .round))
        }
    }

    /// The bottom half of the eggshell. Falls away as Tomo hatches (growth 0 → 1).
    private func drawShell(_ ctx: GraphicsContext, R: CGFloat) {
        let hatched = min(1, max(0, growth))
        guard hatched < 0.98 else { return }
        var c = ctx
        // Falls away like it has weight, solid until the very end.
        c.translateBy(x: 0, y: hatched * hatched * R * 2.6)
        c.opacity = Double(hatched < 0.85 ? 1 : (1 - hatched) / 0.15)
        let rx = R * 1.07, top = R * 0.3, depth = R * 0.75
        var shell = Path()
        let teeth = 8
        for i in 0...teeth {
            let x = -rx + CGFloat(i) * (2 * rx / CGFloat(teeth))
            let y = top - (i % 2 == 1 ? R * 0.13 : 0)
            if i == 0 { shell.move(to: CGPoint(x: x, y: y)) } else { shell.addLine(to: CGPoint(x: x, y: y)) }
        }
        for k in 0...24 {
            let a = Double(k) / 24 * .pi
            shell.addLine(to: CGPoint(x: rx * CGFloat(cos(a)), y: top + depth * CGFloat(sin(a))))
        }
        shell.closeSubpath()
        c.fill(shell, with: .color(Palette.shell))
        c.stroke(shell, with: .color(Palette.shellLine), style: StrokeStyle(lineWidth: R * 0.025, lineJoin: .round))
        for (x, y, s) in [(-0.5, 0.6, 0.05), (0.35, 0.8, 0.04), (0.62, 0.5, 0.035)] as [(CGFloat, CGFloat, CGFloat)] {
            c.fill(Path(ellipseIn: CGRect(x: R * (x - s), y: R * (y - s), width: R * s * 2, height: R * s * 2)),
                   with: .color(Palette.shellLine))
        }
    }

    private func drawQuestionMark(_ ctx: GraphicsContext, center: CGPoint, R: CGFloat, t: CGFloat) {
        let mark = Text("?").font(.system(size: R * 0.55, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
        ctx.draw(mark, at: CGPoint(x: center.x + R * 1.0, y: center.y - R * 1.05 + sin(t * 3) * R * 0.05))
    }

    // MARK: - Particles

    private struct Bit {
        enum Kind {
            case sparkle, heart, z, shell
            var gravity: CGFloat { self == .shell ? 3.2 : self == .sparkle ? 0.6 : -0.15 }
        }
        let kind: Kind
        var pos: CGPoint        // relative to Tomo's center, in body radii
        var vel: CGVector
        var age: Double = 0
        let life: Double
        let size: CGFloat
        let spin: CGFloat
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
                bits.append(Bit(kind: kind, pos: CGPoint(x: 0.55, y: -0.8),
                                vel: CGVector(dx: 0.25, dy: -0.45), life: 1.8, size: 0.3, spin: 0))
            case .shell:
                bits.append(Bit(kind: kind, pos: CGPoint(x: .random(in: -0.9...0.9), y: 0.3),
                                vel: CGVector(dx: .random(in: -1.4...1.4), dy: .random(in: -1.6 ... -0.8)),
                                life: 0.9, size: .random(in: 0.12...0.2), spin: .random(in: -8...8)))
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
            case .shell:
                c.fill(triangle(CGPoint(x: -s, y: s * 0.6), CGPoint(x: s, y: s * 0.5), CGPoint(x: 0, y: -s * 0.7)),
                       with: .color(Palette.shell))
            }
        }
    }

    // MARK: - Moves

    private enum Face { case normal, happy, sleep, sleepy, squeeze, surprised, love, confused, dizzy, wink, flat }

    private struct Move {
        enum Kind {
            case hop(CGFloat), nudge, shake, flap(Int), peck, rock, squish, wobble, beak
            case peep, stretch, tiltHold(CGFloat), shuffle, preen(CGFloat)
        }
        let kind: Kind
        let start: Double
        let duration: Double
    }

    private struct Pose {
        var dx: CGFloat = 0, dy: CGFloat = 0, rot: CGFloat = 0
        var sx: CGFloat = 1, sy: CGFloat = 1
        var wingL: CGFloat = 0, wingR: CGFloat = 0, beak: CGFloat = 0
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
                p.dy -= h * arc; p.sy *= 1 + 0.06 * arc; p.sx *= 1 - 0.04 * arc
            case .nudge:
                p.dy -= q < 0.55 ? 0.42 * sin(.pi * q / 0.55) : 0.2 * sin(.pi * (q - 0.55) / 0.45)
                p.wingL = max(p.wingL, abs(sin(q * 4 * .pi))); p.wingR = p.wingL
            case .shake:
                p.dx += sin(q * 6 * .pi) * 0.09 * (1 - q)
            case .flap(let n):
                let f = abs(sin(q * CGFloat(n) * .pi))
                p.wingL = max(p.wingL, f); p.wingR = max(p.wingR, f)
            case .peck:
                p.dy += 0.14 * abs(sin(q * 2 * .pi)); p.beak = max(p.beak, max(0, sin(q * 4 * .pi)))
            case .rock:
                p.rot += sin(q * 4 * .pi) * 0.13 * (1 - q * 0.6)
            case .squish:
                p.sy *= 1 - 0.2 * arc; p.sx *= 1 + 0.15 * arc
            case .wobble:
                p.rot += sin(q * 7 * .pi) * 0.16 * (1 - q)
            case .beak:
                p.beak = max(p.beak, arc); p.dy -= 0.04 * arc
            case .peep:
                p.beak = max(p.beak, 0.55 * arc); p.dy -= 0.05 * arc
            case .stretch:
                p.wingL = max(p.wingL, 0.85 * arc); p.wingR = max(p.wingR, 0.85 * arc)
                p.sy *= 1 + 0.05 * arc; p.sx *= 1 - 0.03 * arc
            case .tiltHold(let a):
                p.rot += a * Self.hold(q)
            case .shuffle:
                p.dx += sin(q * 4 * .pi) * 0.05; p.rot += sin(q * 4 * .pi) * 0.05
            case .preen(let side):
                let e = Self.hold(q)
                p.rot += side * 0.16 * e; p.dy += 0.05 * e
                if side < 0 { p.wingL = max(p.wingL, 0.45 * e) } else { p.wingR = max(p.wingR, 0.45 * e) }
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

    private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath()
        return p
    }

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

/// Tomo in the island: a Canvas redrawn every frame, gaze following the cursor.
struct TomoCharacterView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    @StateObject private var chick = TomoChick()

    var body: some View {
        // The Canvas must read the timeline's date, or SwiftUI won't redraw it every frame.
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                chick.frameDate = timeline.date
                let g = gaze()
                chick.lookX = g.x
                chick.lookY = g.y
                chick.particleOverhang = particleOverhang
                chick.step()
                chick.draw(context, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, s in chick.setState(s) }
        .onAppear {
            chick.setState(state.effectiveState, force: true)
            chick.setGrowth(CGFloat(min(max(TomoGame.shared.stage - 1, 0), 2)))
        }
        .modifier(TomoChickMoves(chick: chick))
        .modifier(TomoChickReactions(chick: chick))
    }

    /// Cursor direction relative to Tomo, −1…1 (positive y = above).
    private func gaze() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (w, h) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress,
                                nw: state.notchWidth, nh: state.notchHeight)
        let (bx, by, _, _) = botPosition(mode: state.mode, view: state.view, islandW: w, islandH: h,
                                         uploadProgress: state.uploadProgress)
        let screenX = screen.frame.midX - w / 2 + bx
        return CGPoint(x: tanh((state.mousePosition.x - screenX) / 260),
                       y: -tanh((state.mousePosition.y - by) / 200))
    }
}

private struct TomoChickMoves: ViewModifier {
    let chick: TomoChick

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .botTalk)) { _ in chick.talk() }
            .onReceive(NotificationCenter.default.publisher(for: .botNudge)) { _ in chick.nudge() }
            .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in chick.greet() }
            .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in chick.gulp() }
            .onReceive(NotificationCenter.default.publisher(for: .botGrow)) { n in
                if let t = n.object as? CGFloat { chick.grow(to: t) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botSetGrowth)) { n in
                if let t = n.object as? CGFloat { chick.setGrowth(t) }
            }
    }
}

private struct TomoChickReactions: ViewModifier {
    let chick: TomoChick

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { n in
                if let e = n.object as? BotEmote { chick.emote(e) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in chick.poke() }
            .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in chick.blink() }
            .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { n in
                if let s = n.object as? CGFloat { chick.setHover(s) }
            }
    }
}

/// Small decorative Tomo for the leftover agent pills (switched off in Tomodachi; removed with issue #1).
struct MiniBotCanvasView: View {
    let task: AgentTask
    @StateObject private var chick: TomoChick = {
        let c = TomoChick()
        c.isMini = true
        c.setGrowth(1)
        return c
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                chick.frameDate = timeline.date
                chick.step()
                chick.draw(context, size: size)
            }
        }
        .onChange(of: task.state) { _, s in chick.setState(s) }
        .onAppear { chick.setState(task.state, force: true) }
    }
}
