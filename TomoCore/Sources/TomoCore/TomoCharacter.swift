import SwiftUI

// MARK: - Tomo, the blob
//
// Every Tomo is a blob of its own, drawn and animated by our own code (decisions.md, 2026-10-07). What it
// looks like comes from its seed (TomoLook.swift): a colour and eyes for life, and a new form at every
// birthday. Growth is an age step, 0 = 1さい … 5 = 6さい; each birthday its old shape flows into its next form
// (`TomoFormMorph`, TomoMorph.swift).
// The app drives it through notifications (docs/architecture.md, "Character"): the task state
// (`AppState.effectiveState`), `.botTalk`, `.botNudge`, `.botGrow`, `.botLevelUp`, `.botGreet`, `.botGulp`,
// `.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`.
// Big moments (a level-up, a birthday, becoming another Tomo) and arrivals (dripping in from the notch, being pulled
// back up) are cue scripts: one timeline each, as data, played on Tomo's clock (`Cue`, `play`). The shell says where
// the notch is (`strandAnchor`) and how strongly small Tomo glows to ask to play (`callGlow`).
// Reduce Motion is an input (`reduceMotion`): a live Tomo follows its shell's setting (`TomoMotion`), and offline
// renders leave it off, so they never depend on the Mac that renders them.
// What it's made of is an input too (`material`, TomoMaterial.swift): its host passes it in, with its look. It sets the
// pass over its body, its springs and its hello (`hello`, `helloCue`).

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

    /// Where the goo strand hangs from while Tomo drips in or is pulled up (`dripIn`, `pullUp`): the notch, in the
    /// canvas's own coordinates (points, y down; usually above the canvas). The shell sets it; nil: no strand.
    public var strandAnchor: CGPoint?
    /// How strongly small Tomo glows amber to say it wants to play, 0…1 (0: no glow). The shell sets it while something
    /// counts (later, the mood ladder sets how strongly). It eases in and out and pulses every 2.6 s; under Reduce
    /// Motion it's a steady, softer glow.
    public var callGlow: CGFloat = 0
    /// Pulled up into the notch (`pullUp`): nothing is drawn until `dripIn` or `appear`.
    public private(set) var isAway = false
    /// Small Tomo's badges (#137): a "…" thought bubble while it checks an answer and a tiny Zz while it dozes (`badge`),
    /// beside its head on its right, never a number. The shell turns them on where Tomo is small (the resting island)
    /// and leaves room for them to the right of the canvas (`badgeFrame`); elsewhere Tomo's face and drifting z's say it.
    /// Under Reduce Motion they show without bobbing.
    public var showsBadges = false
    /// The season's light weather around Tomo (#137): a few flakes or petals falling behind it, from the target
    /// language's calendar (`TomoCalendar`). The host passes it only where Tomo has room and the learner is looking (the
    /// card), never resting. It's drawn from the clock, with nothing stored, so it's no particles; under Reduce Motion
    /// there are a third as many, falling slower.
    public var weather: TomoWeather?
    /// Dancing to music (#130): a loop on Tomo's clock, no script. `.bounce` is its own bounce and sway on every beat
    /// at a fixed 112 BPM; `.bonOdori` the 盆踊り side-step at half that, on the days the target language's calendar
    /// says (お盆). The host turns it on while music plays and Tomo rests (visits and quiet hours win). It fades in over
    /// about 0.8 s and out again, and Tomo stays awake and doesn't fidget while it dances; a big moment, an arrival or
    /// the hello takes over while it plays. Off under Reduce Motion.
    public var dance: TomoDance?
    /// How Tomo feels (#257, #258): a look over its own (`TomoFeeling`), or nil: well. Droopy slumps lower and wider,
    /// flops its ears or topper, looks at the floor, breathes slower and sighs every 5 to 7 s; sickly turns green-grey and
    /// a size smaller, with a sweat drop, quick shallow breaths, heavy worried lids and a shiver every few seconds; mossy
    /// falls asleep curled up, breathing deep and slow, while moss creeps over its top in its own seeded patches and a
    /// sprout grows and sways, with Zz drifting up. It eases in and out over about a second (moss over three), and back to
    /// well Tomo gives a happy wiggle, or brushes its moss off (`brushCue`). Its colours are a pass over the look, so the
    /// look never changes. Under Reduce Motion only its face, colour and pose change: the sigh and the shiver are a puff,
    /// and the sweat drop and the sprout stay put. Only the Testing menu sets it for now (`TomoGame.feeling`).
    public var feeling: TomoFeeling?
    /// Back in its egg (#258): Tomo curls up and its first-run egg (`TomoEgg`) closes round it (`intoEggCue`), and there
    /// it rests, rocking every few seconds and now and then peeking out through the crack; a poke wobbles it. Set back to
    /// false, it hatches (`hatchCue`): the egg shakes and cracks, the halves fly apart and Tomo springs out, saying
    /// `hatchWord`. It comes out as it went in: its seed, age, form, colours and feeling never change. A script already
    /// playing finishes first. Under Reduce Motion the egg fades in round it and out again, with a glow and star eyes.
    /// Only the Testing menu sets it for now (`TomoGame.inEgg`).
    public var inEgg = false
    /// What Tomo says as it hatches, in a bubble beside it: the target pack's hello (`lines.hello`), given by the host.
    /// Nil: no bubble.
    public var hatchWord: String?
    /// Called as a hatch starts playing (`hatchCue`), from `step`, so a host plays the hatch's sounds with it: not while
    /// a script it waits for still plays, and not at all when Tomo was back out before it went in.
    public var onHatch: (@MainActor () -> Void)?
    /// The top of the room Tomo stands in, in the canvas's own coordinates (points, y down), or nil: no ceiling. The
    /// island without a notch sets it a little inside its top edge, which floats below the screen's. A form too tall to
    /// stand under it, with its topper, its idle stretch and a hop, is drawn smaller (`fit`), standing where it stands
    /// and moving as it does (#196).
    public var ceiling: CGFloat?
    private var standing: (seed: String, age: Int, top: CGFloat)?

    /// Whose Tomo this is. Nil: the learner's own (`TomoLook.current`), changing with a pop when it does.
    public let fixedLook: TomoLook?
    public private(set) var look: TomoLook { didSet { painted = nil } }
    /// `look` as it's drawn: in the feeling's colours (`TomoLook.tinted`), else the look itself. Particles keep the look's.
    private var paint: TomoLook
    private var painted: (sat: Int, green: Int)?   // the tint `paint` has (`TomoFeeling.Amounts.tint`); nil: work it out
    /// What it's made of, given by its host and kept for life: `TomoMaterial.own` for the learner's Tomo, `.classic` for
    /// the mascot and the renders that ship as files.
    public let material: TomoMaterial
    /// The shell's Reduce Motion setting, followed every frame: `TomoMotion.shared` for a live Tomo, nil offline.
    private let motion: TomoMotion?

    public init(look: TomoLook? = nil, material: TomoMaterial, motion: TomoMotion? = nil) {
        fixedLook = look
        self.look = look ?? TomoLook.current
        paint = self.look
        self.material = material
        self.motion = motion
        reduceMotion = motion?.reduce ?? false
    }

    /// The age step on show (0 = 1さい). The one it's growing into is the playing script's `swap`; a birthday swaps at
    /// once, and its `morph` shows the old shape flowing into the new one.
    public private(set) var age = 0
    /// The big moment playing, if any (`play`).
    private var cue: Playing?
    /// A birthday's old shape becoming the new one (`Cue.Step.morph`), until it's done or Tomo is something else.
    private var morph: Morphing?

    public private(set) var state: BotState = .idle
    private var baseFace: Face = .normal
    private var flash: (face: Face, until: Double)?
    private var moves: [Move] = []
    private var bits: [Bit] = []
    /// Where the particles' random draws come from: the system's in the app; the checks seed it, so a check sees the
    /// same burst every run (`particleSelfTest`, #203).
    var dice = TomoDice()
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
    private var callGlowShown: CGFloat = 0 // `callGlow`, eased
    private var badgeShown: (badge: Badge, alpha: CGFloat) = (.dozing, 0)   // the badge on show, fading in or out
    private var weatherShown: (weather: TomoWeather, alpha: CGFloat) = (.snow, 0)   // fading in or out, like a badge
    private var danceShown: (dance: TomoDance, amount: CGFloat) = (.bounce, 0)     // fading in or out
    private var feelingShown = TomoFeeling.Amounts.well   // `feeling`, eased
    private var feelingWas: TomoFeeling?
    private var breathLag: CGFloat = 0     // how far a feeling has moved the breath's phase, slowing or quickening it
    private var slump: (seed: String, age: Int, R: CGFloat, sag: CGFloat, body: Path)?   // the sagged outline, kept
    // Mossy's patches and greens, and the egg's outline and speckles, kept for the look (and the egg's size): they
    // come from its seed alone, never from a script or a birthday's morph, so they're the same every frame.
    private var mossKept: (seed: String, light: Double, patches: [(x: CGFloat, y: CGFloat, r: CGFloat)],
                           greens: (base: Color, light: Color))?
    private var eggKept: (seed: String, w: CGFloat, h: CGFloat, outline: Path, spots: [(x: CGFloat, y: CGFloat, r: CGFloat)])?
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
    private var shell = false              // in its egg (`inEgg`), from when the script taking it there starts
    private var peekAt: Double = -10       // when it last peeked out of its egg
    private var nextPeek: Double = 0
    private var eggPoke: Double = -10      // when its egg was last poked: a wobble
    private var mossBrushed: CGFloat = 0   // the moss a brush-off is sweeping away (`Pose.brushed`)

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
        if shell {                                          // in its egg: the egg wobbles, and Tomo peeks out
            guard cue == nil else { return }
            let now = clock()
            eggPoke = now
            if now - peekAt > 1.8 {
                peekAt = now + 0.12
                nextPeek = max(nextPeek, peekAt + 1.8)      // the next peek waits for this one to end
            }
            return
        }
        stir()
        let now = clock()
        add(.squish, 0.35)
        flash = (.squeeze, now + 0.5)
        if !reduceMotion {
            swayVel += (Bool.random() ? 1 : -1) * 16
            jiggleVel += 5 * material.springs.kick
        }
        pokes = pokes.filter { now - $0 < 2.5 } + [now]
        if pokes.count >= 3 {
            pokes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        }
    }

    /// A new level: the level-up script (`levelUpCue`). The game's win and `.proud`, sent with it, add nothing (`play`).
    public func levelUp() { play(Self.levelUpCue) }

    /// A visit arrives: Tomo drips down from the notch (`dripInCue`), hanging from `strandAnchor`. Under Reduce Motion it
    /// fades in where it sits.
    public func dripIn() {
        isAway = false
        play(Self.dripInCue)
    }

    /// Leaving: Tomo is pulled up into the notch (`pullUpCue`), then it's away until `dripIn` or `appear`. Under Reduce
    /// Motion it fades out where it sits. Already leaving (or gone): nothing more.
    public func pullUp() {
        guard !isLeaving else { return }
        play(Self.pullUpCue)
    }

    /// Being pulled up into the notch, or up there already (`pullUp`).
    public var isLeaving: Bool { isAway || cue?.goesAway == true }

    /// Tomo's hello (#137), when the app starts or the Mac wakes, in its material's way (`helloCue`): jelly's is a drop
    /// that falls from `strandAnchor` (else the canvas's top edge) and gathers into Tomo, with a gold light; under Reduce
    /// Motion it fades in with the light. Not while Tomo is away or leaving, in its egg, or while another script plays (an
    /// arrival or a big moment already shows it). False if it didn't play, or the material has no hello.
    @discardableResult
    public func hello() -> Bool {
        guard !isLeaving, cue == nil, !shell, let script = Self.helloCue(material) else { return false }
        play(script)
        return true
    }

    /// Back without dripping in (small Tomo beside the notch after a visit, or the card reopened while Tomo was being
    /// pulled up): a quick fade in. Nothing to do if Tomo is here.
    public func appear() {
        guard isLeaving else { return }
        isAway = false
        play(Self.appearCue)
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

    /// Grow up (or reset) to an age step. Growing up plays the birthday script (`birthdayCue`): the new form comes at
    /// once, its outline flowing out of the old one (`morph`).
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

    /// Jump straight to an age step (no animation). A birthday playing keeps going, without its swap or its morph.
    public func setGrowth(_ value: CGFloat) {
        age = Self.ageStep(value)
        cue?.swap = nil
        morph = nil
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

    /// The feeling on show (`feeling`): eased toward its amounts, the breath's phase following its pace, the colours
    /// repainted when the tint moves; back to well, the happy hop and wiggle with a few sparkles, or from mossy the
    /// brush-off (not during a big moment, or in its egg).
    private func stepFeeling(_ now: Double, dt: CGFloat) {
        if feeling != feelingWas {
            if feeling == nil, cue == nil, !shell, feelingWas == .mossy {
                play(Self.brushCue)
            } else if feeling == nil, cue == nil, !shell {
                stir()
                add(.hop(0.22), 0.45); add(.wiggle(4), 0.6)
                flash = (.happy, now + 1.1)
                emit(.sparkle, 3)
                nextFidget = max(nextFidget, now + 2.5)
            }
            feelingWas = feeling
        }
        let goal = TomoFeeling.Amounts(feeling), easing = feelingShown != goal
        if easing { feelingShown.ease(toward: goal, dt: dt) }
        if feelingShown.breathRate != 1 { breathLag += dt * CGFloat(look.breathRate) * (feelingShown.breathRate - 1) }
        guard easing || painted == nil else { return }      // the tint moves only with the feeling, or a new look
        let tint = feelingShown.tint
        if painted.map({ $0 != tint }) ?? true {
            painted = tint
            paint = tint == TomoFeeling.Amounts.well.tint ? look
                : look.tinted(sat: Double(tint.sat) / 40, green: Double(tint.green) / 40)
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
            feelingShown = TomoFeeling.Amounts(feeling)     // a Tomo that appears feeling something already shows it
            feelingWas = feeling
            shell = inEgg                                   // and one that appears in its egg is in it
            nextPeek = now + .random(in: 1.5...3)
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
        if inEgg != shell, cue == nil {                     // into its egg, or out: once any script playing is over
            play(inEgg ? Self.intoEggCue : Self.hatchCue)
            shell = inEgg
            if shell { nextPeek = now + (cue?.length ?? 0) + .random(in: 1.2...2.5) } else { onHatch?() }
        }
        if shell, cue == nil, now > nextPeek { peekAt = now; nextPeek = now + .random(in: 4...6.5) }
        stepFeeling(now, dt: dt)

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
        if feelingShown.gaze > 0 {                          // droopy: down at the floor
            target.x += (TomoFeeling.floor.x - target.x) * feelingShown.gaze
            target.y += (TomoFeeling.floor.y - target.y) * feelingShown.gaze
        }
        let kLook = 1 - pow(0.0005, dt), kSoft = 1 - pow(0.001, dt)
        look2.x += (target.x - look2.x) * kLook
        look2.y += (target.y - look2.y) * kLook
        tilt += (Self.tilt(for: state) - tilt) * kSoft
        puff += (puffTarget - puff) * kSoft
        blush += (0 - blush) * (1 - pow(0.4, dt))
        callGlowShown += (min(max(callGlow, 0), 1) - callGlowShown) * (1 - pow(0.02, dt))
        if callGlowShown < 0.001 && callGlow <= 0 { callGlowShown = 0 }
        let wears = showsBadges ? badge : nil              // a new badge fades in; none fades the last one out
        if let wears, wears != badgeShown.badge, badgeShown.alpha < 0.05 { badgeShown.badge = wears }
        let badgeTarget: CGFloat = wears == badgeShown.badge ? 1 : 0
        badgeShown.alpha += (badgeTarget - badgeShown.alpha) * (1 - pow(0.0005, dt))
        if badgeShown.alpha < 0.005 && badgeTarget == 0 { badgeShown.alpha = 0 }
        if let w = weather, w != weatherShown.weather, weatherShown.alpha < 0.05 { weatherShown.weather = w }
        let weatherTarget: CGFloat = weather == weatherShown.weather ? 1 : 0
        weatherShown.alpha += (weatherTarget - weatherShown.alpha) * (1 - pow(0.02, dt))
        if weatherShown.alpha < 0.005 && weatherTarget == 0 { weatherShown.alpha = 0 }
        let dancing = reduceMotion ? nil : dance
        if let d = dancing {
            if danceShown.amount < 0.01 { stir() }          // the music starts: awake (from a doze, with a start)
            if d != danceShown.dance, danceShown.amount < 0.05 { danceShown.dance = d }
            lastStir = now                                  // no dozing off while it dances
        }
        let danceTarget: CGFloat = dancing != nil && dancing == danceShown.dance ? 1 : 0
        danceShown.amount += (danceTarget - danceShown.amount) * (1 - pow(0.03, dt))
        if danceShown.amount < 0.002 && danceTarget == 0 { danceShown.amount = 0 }

        // Springs, in small substeps: the sprout, which lags behind the body's moves and wobbles back,
        // and the body's jelly wobble when it lands. How loose they are is the material's.
        if dt > 0 {
            let spring = material.springs
            let vy = (pose.dy - lastDy) / dt
            let vx = (pose.dx - lastDx) / dt
            let vr = (pose.rot + tilt - lastRot) / dt
            let swayTarget = max(-0.6, min(0.6, -vr * 0.08 - vx * 0.6 - look2.x * 0.1))
            var left = dt
            while left > 0 {
                let h = min(left, 1.0 / 120)
                let ws = spring.swayW, zs = spring.swayZ
                swayVel += (ws * ws * (swayTarget - sway) - 2 * zs * ws * swayVel - vy * 4) * h
                sway += swayVel * h
                let wj = spring.wobbleW, zj = spring.wobbleZ
                jiggleVel += (-wj * wj * jiggle - 2 * zj * wj * jiggleVel + vy * spring.lift) * h
                jiggle += jiggleVel * h
                left -= h
            }
            jiggle = max(-spring.most, min(spring.most, jiggle))
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
        let calm = cue == nil && danceShown.amount == 0 && (state == .idle || state == .question || state == .thinking)
        if calm, !drowsy, flash == nil, moves.isEmpty, glance == nil, now > nextFidget {
            switch feeling {                                // a feeling has its own, slower fidget; asleep or in its egg, none
            case _ where shell, .mossy?: nextFidget = now + .random(in: 3...5)
            case .droopy?: add(.sigh, 1.8); nextFidget = now + .random(in: 5...7)
            case .sickly?: add(.shiver(0.022), 0.8); nextFidget = now + .random(in: 3.5...5.5)
            case nil: fidget(); nextFidget = now + .random(in: 2.5...6)
            }
        } else if !calm {
            nextFidget = max(nextFidget, now + 2)
        }
        if !isMini, state == .idle, !drowsy, !shell, now - lastStir > dozeAfter { drowsy = true }
        if state != .idle || shell { drowsy = false }

        // Sleeping z's (small Tomo wears its Zz badge instead; mossy's are drawn from the clock, `drawSnore`)
        if (state == .sleeping || drowsy) && !showsBadges && !shell && feelingShown.sleep < 0.5
            && now - lastAmbient > (drowsy ? 3 : 1.4) {
            lastAmbient = now
            emit(.z, 1)
        }

        for i in bits.indices {
            let pace = bits[i].pace
            bits[i].age += elapsed
            bits[i].pos.x += bits[i].vel.dx * dt * pace
            bits[i].pos.y += bits[i].vel.dy * dt * pace
            bits[i].vel.dy += bits[i].kind.gravity * dt * pace
            if bits[i].kind == .confetti { bits[i].vel.dx *= pow(0.25, dt * pace) }   // paper slows sideways
        }
        bits.removeAll { $0.age >= $0.life }
    }

    // MARK: Drawing

    public func draw(_ context: GraphicsContext, size: CGSize) {
        guard !isAway else { return }                       // up in the notch
        let now = clock()
        let p = started ? pose : pose(at: now)
        let own = look.form(age), shown = morphFrame(now)       // a birthday's morph draws its own frame of the form
        let form = shown?.form ?? own
        let R = size.width * 0.27
        let ground = form.bottom * R
        let t = CGFloat(now - born)
        // Lean toward the cursor; nod off when drowsy.
        var rot = tilt + p.rot + look2.x * 0.06
        var dy = p.dy
        if drowsy { rot += sin(t * 0.8) * 0.05; dy += max(0, sin(t * 0.8)) * 0.03 }
        let cx = size.width / 2 + (p.dx + look2.x * 0.04) * R
        let middle = size.height / 2 + particleOverhang / 2 + R * 0.1     // where it stands, at rest
        let cy = middle + dy * R
        let moss = mossShown(p)                             // as drawn, so the size eases as a brush-off sweeps it away
        let g = form.scale * fit(form: own, R: R, ground: middle + own.bottom * R, moss: moss)
        let feel = feelingShown, breath = breath(at: t)
        rot += feel.curl * 0.1                              // mossy: curled up asleep, tipped a little

        // Anchor scaling and rocking at Tomo's base, so squashes stay on the ground.
        let sx = p.sx * p.size * puff * g * (1 - jiggle * 0.5) * feel.size * feel.wide * (1 + 0.07 * feel.curl)
        let sy = p.sy * p.size * puff * g * breath * (1 + jiggle) * (shown?.beat.stretch ?? 1) * feel.size * feel.tall
            * (1 - 0.13 * feel.curl)

        if weatherShown.alpha > 0 { drawWeather(context, size: size, center: CGPoint(x: cx, y: cy), R: R, now: now) }
        if callGlowShown > 0 { drawCallGlow(context, center: CGPoint(x: cx, y: cy), R: R * g, now: now, fade: p.opacity) }
        if let strand = p.strand, let anchor = strandAnchor {
            // From the notch to the top of Tomo's head, a little inside it so the two join (the same steps as below).
            let place = CGAffineTransform(translationX: cx, y: cy + ground).rotated(by: rot).scaledBy(x: sx, y: sy)
                .translatedBy(x: 0, y: -ground)
            let top = CGPoint(x: 0, y: (0.15 - form.top) * R).applying(place)
            drawStrand(context, from: anchor, to: top, strand, R: R * g, fade: p.opacity)
        }
        if let drop = p.drop {                              // the hello's drop, falling to where Tomo sits
            drawHelloDrop(context, drop, from: strandAnchor ?? CGPoint(x: cx, y: 0),
                          to: CGPoint(x: cx, y: cy + ground), R: R * g)
        }
        let light = TomoMaterial.Glow(call: callGlowAlpha(now), shine: p.shine)   // from inside (the material's)
        let glow = max(p.glow, shown?.beat.glow ?? 0)
        // One form at its own size on its own ground (Reduce Motion's crossfade draws the old one too), its topper faded.
        let tomo = { (layer: GraphicsContext, side: TomoForm, sideAge: Int, topper: CGFloat) in
            let base = side.bottom * R, k = side.scale / form.scale
            var ctx = layer
            ctx.translateBy(x: cx, y: cy + base)
            ctx.rotate(by: .radians(Double(rot)))
            ctx.scaleBy(x: sx * k, y: sy * k)
            ctx.translateBy(x: 0, y: -base)
            if topper >= 1 {
                self.drawTopper(ctx, form: side, R: R, age: sideAge)
            } else if topper > 0.01 {
                var c = ctx
                c.opacity *= Double(topper)
                c.drawLayer { self.drawTopper($0, form: side, R: R, age: sideAge) }
            }
            self.drawBody(ctx, form: side, R: R, glow: glow, light: light, moss: moss, t: t)
            if feel.sweat > 0.02 { self.drawSweat(ctx, form: side, R: R, t: t) }
            self.drawFace(ctx, form: side, R: R, now: now, mouth: p.mouth)
        }
        let whole = { (layer: GraphicsContext) in
            guard let old = shown?.old else { tomo(layer, form, self.age, shown?.topper ?? 1); return }
            for (side, sideAge, alpha) in [(old.form, old.age, old.alpha), (form, self.age, 1 - old.alpha)] where alpha > 0.004 {
                var c = layer                               // each as one piece, the new one over the old
                c.opacity *= Double(alpha)
                c.drawLayer { tomo($0, side, sideAge, 1) }
            }
        }
        // In its egg (`inEgg`), or going in or coming out: Tomo shows as one piece, as much as the script says, and the
        // egg stands where it stands, over it; as it hatches, the halves fly off behind it, as the first run's do.
        let (shows, egg) = eggShown(p)
        let behind = egg?.split != nil, room = eggRoom(size: size)
        let scene = { (layer: GraphicsContext) in
            let theEgg = { (at: GraphicsContext) in
                if let egg { self.drawEgg(at, egg, floor: room.floor, top: room.top, R: R, now: now, t: t) }
            }
            if behind { theEgg(layer) }
            if shows >= 0.996 {
                whole(layer)
            } else if shows > 0.004 {
                var c = layer
                c.opacity *= Double(shows)
                c.drawLayer { whole($0) }
            }
            if !behind { theEgg(layer) }
        }
        if p.opacity < 1 {                                  // fading in or out: as one piece, so parts don't show through
            var faded = context
            faded.opacity = Double(max(p.opacity, 0))
            faded.drawLayer { scene($0) }
        } else {
            scene(context)
        }

        if !isMini {
            let center = CGPoint(x: cx, y: cy)
            // Only as much as Tomo shows (none in its egg, or a closed egg about to hatch), and none asleep (mossy): its
            // Zz say it instead.
            let asks = shows * max(0, 1 - 2 * feel.sleep)
            if state == .question, asks > 0.004 {
                var c = context
                c.opacity *= Double(asks)
                drawQuestionMark(c, center: center, R: R * g, t: t)
            }
            if feel.sleep > 0.01, !showsBadges {
                drawSnore(context, center: center, R: R * g, t: t, alpha: feel.sleep * shows * p.opacity)
            }
            drawBits(context, center: center, R: R * g)
            if p.bubble > 0.01, R > 14, let hatchWord {
                drawBubble(context, hatchWord, size: size, center: center, R: R, reach: R * g, alpha: p.bubble * p.opacity)
            }
        }
        if badgeShown.alpha > 0 {
            drawBadge(context, badgeShown.badge, at: badgeAnchor(center: CGPoint(x: cx, y: cy), r: R * g), unit: badgeUnit(R * g),
                      alpha: badgeShown.alpha * p.opacity, now: now)
        }
    }

    /// How much of the moss shows in pose `p`, 0…1: what `feeling` has grown, or what a brush-off is sweeping away.
    private func mossShown(_ p: Pose) -> CGFloat { max(feelingShown.moss, mossBrushed * p.brushed) }

    /// How much of Tomo shows in pose `p` (0: inside its egg), and its egg (nil: none): a script's frame of it, or
    /// resting in it.
    private func eggShown(_ p: Pose) -> (tomo: CGFloat, egg: TomoEgg.Frame?) {
        if p.egg != nil { return (p.tomo, p.egg) }
        return shell ? (0, TomoEgg.Frame(resting: true)) : (p.tomo, nil)
    }

    /// Where Tomo's egg stands in a canvas of `size` (its floor, under Tomo at rest) and the highest it may reach (`top`):
    /// the top of Tomo's frame, below the room the canvas keeps above it for particles (`particleOverhang`), or under a
    /// ceiling, the ceiling. On the card that keeps it under the header, and on the iPhone on its canvas.
    func eggRoom(size: CGSize) -> (floor: CGPoint, top: CGFloat) {
        let R = size.width * 0.27
        let floor = CGPoint(x: size.width / 2, y: size.height / 2 + particleOverhang / 2 + R * 0.1 + look.form(age).bottom * R)
        return (floor, max(particleOverhang, ceiling ?? 0))
    }

    /// How far into its breath Tomo is drawn (1: between breaths), `t` seconds after it was born: at its own pace, deeper
    /// asleep or dozing (or as a feeling falls asleep, mossy's), and at the feeling's pace and depth (`breathLag` keeps
    /// it smooth as that pace changes).
    func breath(at t: CGFloat) -> CGFloat {
        let asleep = max(state == .sleeping || drowsy ? 1 : 0, feelingShown.sleep)
        let deep: CGFloat = 0.018 + 0.017 * asleep
        return 1 + sin(t * CGFloat(look.breathRate) + breathLag) * deep * feelingShown.breathDepth
    }

    /// Mossy's Zz drifting up from Tomo as it sleeps, `alpha` solid: worked out from the clock on the path an emitted z
    /// takes (`Bit.Kind.z`, one every 1.4 s, each living 1.8 s), so nothing is emitted; under a `ceiling` each fades out
    /// before it reaches it. Under Reduce Motion, at the calm pace.
    private func drawSnore(_ context: GraphicsContext, center: CGPoint, R: CGFloat, t: CGFloat, alpha: CGFloat) {
        let pace: CGFloat = reduceMotion ? Self.calmPace : 1, every: CGFloat = 1.4, life: CGFloat = 1.8, fs = R * 0.42
        var a = t.truncatingRemainder(dividingBy: every)
        while a < life {
            let u = a * pace
            let at = CGPoint(x: center.x + (0.6 + 0.25 * u) * R, y: center.y - (0.8 + 0.45 * u + 0.075 * u * u) * R)
            let room = ceiling.map { min(1, max(0, (at.y - fs * 0.6 - $0) / fs)) } ?? 1
            var c = context
            c.opacity *= Double(alpha * (1 - a / life) * room)
            if c.opacity > 0.004 {
                c.draw(Text("z").font(.system(size: fs, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8)),
                       at: at)
            }
            a += every
        }
    }

    // MARK: - The egg (#258)

    /// Tomo's egg (`inEgg`, the first run's, `TomoEgg`) standing on `floor`, in a script's frame or resting: then it rocks
    /// every few seconds and breathes, wobbles when poked, and now and then lifts its top to peek out with Tomo's eyes.
    /// It's 1.45 R wide, narrower under a ceiling so its peek stays under it. Its top half drops on from the lab's 1.1
    /// egg heights up, or from as high as the room under `top` allows (`eggRoom`). Under
    /// Reduce Motion it doesn't rock or wobble, and peeks half as far.
    func drawEgg(_ context: GraphicsContext, _ e: TomoEgg.Frame, floor: CGPoint, top roomTop: CGFloat, R: CGFloat,
                 now: Double, t: CGFloat) {
        guard e.alpha > 0.004 else { return }
        var w = R * 1.45
        if let ceiling { w = min(w, max(1, floor.y - ceiling) / (1.28 * 1.1)) }
        let h = w * 1.28, cY = TomoEgg.crackY(height: h)
        // The room above the egg's top, in egg heights, less its breath and outline.
        let above = max(0, (floor.y - h * 1.02 - roomTop) / h - 0.02)
        var rot = e.rot, lift: CGFloat = 0
        if e.resting {
            if !reduceMotion {
                rot += sin(t * 2.1) * 0.035
                let beat = t.truncatingRemainder(dividingBy: 2.8)          // a rock every 2.8 s
                if beat < 0.5 { rot += sin(beat * 38) * 0.09 * (1 - beat / 0.5) }
                let poked = CGFloat(now - eggPoke)
                if poked >= 0, poked < 0.6 { rot += sin(poked * 40) * 0.1 * (1 - poked / 0.6) }
            }
            let peek = CGFloat((now - peekAt) / 1.7)
            if peek >= 0, peek <= 1 { lift = h * (reduceMotion ? 0.035 : 0.065) * Self.hold(peek) }
        }
        let breath = 1 + sin(t * CGFloat(look.breathRate) + breathLag) * 0.012
        if eggKept?.seed != look.seed || eggKept?.w != w || eggKept?.h != h {
            eggKept = (look.seed, w, h, TomoEgg.path(width: w, height: h), TomoEgg.spots(seed: look.seed))
        }
        let outline = eggKept?.outline ?? TomoEgg.path(width: w, height: h), spots = eggKept?.spots
        let shell = { (c: GraphicsContext) in
            TomoEgg.drawShell(c, outline, width: w, height: h, look: self.look, outline: max(0.6, w * 0.012), spots: spots)
        }
        let egg = { (layer: GraphicsContext) in
            // Its shadow, smaller as it hops, and fading as it splits (as the first run's, in 0.4 s of its 0.7 s).
            let shade = 0.16 * max(0, 1 - (e.split ?? 0) / (0.4 / 0.7))
            if shade > 0.004 {
                let rx = w * 0.42 * (1 - min(0.4, e.hop)), ry = w * 0.07
                layer.fill(Path(ellipseIn: CGRect(x: floor.x - rx, y: floor.y + w * 0.03 - ry, width: rx * 2, height: ry * 2)),
                           with: .color(.black.opacity(shade)))
            }
            var ctx = layer
            if e.clipFloor { ctx.clip(to: Path(CGRect(x: -1e4, y: -1e4, width: 2e4, height: 1e4 + floor.y))) }
            ctx.translateBy(x: floor.x, y: floor.y - e.hop * w)
            ctx.scaleBy(x: 1, y: breath)
            ctx.translateBy(x: 0, y: -h / 2)
            ctx.rotate(by: .radians(Double(rot)))
            guard e.split != nil || e.top != nil || e.bottom != nil || lift > 0.01 else {
                shell(ctx)
                TomoEgg.drawCrack(ctx, outline, width: w, y: cY, shown: e.crack, lineWidth: max(0.8, w * 0.02))
                return
            }
            if lift > 0.01 {                                                // peeking: Tomo's colour and eyes in the gap
                var inside = ctx
                inside.clip(to: outline)
                inside.fill(Path(CGRect(x: -w, y: cY - lift - w * 0.12, width: w * 2, height: lift + w * 0.24)),
                            with: .color(self.paint.body))
                let since = now - self.blinkAt
                let open: CGFloat = since < 0.09 ? CGFloat(1 - since / 0.09) : since < 0.2 ? CGFloat((since - 0.09) / 0.11) : 1
                let r = w * 0.05, ry = max(0.4, min(lift * 0.42, r) * max(0.1, open))
                for side: CGFloat in self.look.cyclops ? [0] : [-1, 1] {
                    let c = CGPoint(x: side * w * 0.15, y: cY - lift * 0.5)
                    inside.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - ry, width: r * 1.6, height: ry * 2)),
                                with: .color(self.paint.ink))
                }
            }
            if let k = e.split {                                            // behind Tomo
                TomoEgg.drawSplit(ctx, k: k, width: w, height: h, shell: shell)
                return
            }
            var bottom = ctx
            if let b = e.bottom { bottom.opacity *= Double(min(1, max(0, b.alpha))); bottom.translateBy(x: 0, y: b.dy * h) }
            bottom.clip(to: TomoEgg.half(crackY: cY, width: w, height: h, top: false))
            shell(bottom)
            var top = ctx
            if let a = e.top {                                              // dropping on, from as high as there's room
                top.opacity *= Double(min(1, max(0, a.alpha)))
                top.translateBy(x: 0, y: a.dy * h * min(1, above / TomoEgg.dropFrom))
            }
            top.translateBy(x: 0, y: -lift)
            top.clip(to: TomoEgg.half(crackY: cY, width: w, height: h, top: true))
            shell(top)
        }
        if e.alpha >= 0.996 {
            egg(context)
        } else {                                                            // fading: as one piece
            var c = context
            c.opacity *= Double(e.alpha)
            c.drawLayer { egg($0) }
        }
    }

    /// What Tomo says as it hatches (`hatchWord`) in a white bubble above it on its left, its tail toward Tomo, kept on
    /// the canvas; `R` sets its size, and `reach` (Tomo's radius as drawn) where it sits.
    private func drawBubble(_ context: GraphicsContext, _ word: String, size: CGSize, center: CGPoint, R: CGFloat,
                            reach: CGFloat, alpha: CGFloat) {
        var ctx = context
        ctx.opacity *= Double(min(1, max(0, alpha)))
        let fs = max(11, R * 0.4)
        let text = ctx.resolve(Text(word).font(.system(size: fs, weight: .heavy, design: .rounded)).foregroundColor(Self.bubbleInk))
        let tw = text.measure(in: CGSize(width: size.width, height: fs * 3)).width
        let pw = tw + fs * 0.9, ph = fs * 1.5
        let x = min(max(center.x - reach * 0.7 - pw, 4), size.width - pw - 4)
        let y = min(max(center.y - reach * 1.5 - ph, 4), size.height - ph - 4)
        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: pw, height: ph), cornerRadius: ph * 0.45), with: .color(.white))
        var tail = Path()
        tail.move(to: CGPoint(x: x + pw * 0.6, y: y + ph - 1))
        tail.addLine(to: CGPoint(x: x + pw * 0.92, y: y + ph + fs * 0.45))
        tail.addLine(to: CGPoint(x: x + pw * 0.82, y: y + ph - 1))
        tail.closeSubpath()
        ctx.fill(tail, with: .color(.white))
        ctx.draw(text, at: CGPoint(x: x + fs * 0.45, y: y + ph * 0.54), anchor: .leading)
    }

    private static let bubbleInk = Color(hex: "#141625")

    // MARK: - Weather

    /// Where the weather's flakes or petals are now, in the canvas, and how solid each is (`weather`): a few, each falling
    /// on its own loop from just above Tomo's head to the canvas's bottom and swaying, all worked out from the clock, so
    /// nothing is stored or emitted. Under Reduce Motion, a third as many, at the calm pace.
    func weatherFlakes(size: CGSize, center c: CGPoint, R: CGFloat, now: Double) -> [(at: CGPoint, alpha: CGFloat, k: CGFloat)] {
        let n = reduceMotion ? 2 : 7, pace = reduceMotion ? Self.calmPace : 1
        let snow = weatherShown.weather == .snow
        let top = max(0, c.y - R * 2.6), h = max(1, size.height - top), t = CGFloat(now) * pace
        func frac(_ x: CGFloat) -> CGFloat { x - floor(x) }
        return (0..<n).map { i in
            let k = CGFloat(i)
            let fall = R * (snow ? 0.8 : 0.6) * (0.75 + 0.5 * frac(k * 0.37 + 0.5))     // points a second
            let u = frac(k * 0.29 + 0.11 + t * fall / h)                               // how far down its loop
            let x = size.width * (0.08 + 0.84 * frac(k * 0.618 + 0.13)) + sin(t * 0.9 + k * 1.7) * R * (snow ? 0.12 : 0.3)
            let edge = min(1, u / 0.1, (1 - u) / 0.1)                                 // in and out at the ends
            return (CGPoint(x: x, y: top + u * h), max(0, edge), k)
        }
    }

    private func drawWeather(_ ctx: GraphicsContext, size: CGSize, center: CGPoint, R: CGFloat, now: Double) {
        let pace: CGFloat = reduceMotion ? Self.calmPace : 1, t = CGFloat(now) * pace
        for f in weatherFlakes(size: size, center: center, R: R, now: now) {
            var c = ctx
            c.opacity = Double(f.alpha * weatherShown.alpha)
            c.translateBy(x: f.at.x, y: f.at.y)
            switch weatherShown.weather {
            case .snow:
                let r = R * (0.045 + 0.03 * (f.k * 0.71 - floor(f.k * 0.71)))
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.92)))
            case .petals:                      // a 桜 petal, notched at its tip, turning and flipping as it drifts
                c.rotate(by: .radians(Double(t * (1.1 + 0.3 * f.k.truncatingRemainder(dividingBy: 3)) + f.k)))
                c.scaleBy(x: max(0.25, abs(cos(t * 1.6 + f.k))), y: 1)
                let p = R * 0.11
                var petal = Path()
                petal.move(to: CGPoint(x: 0, y: p))
                petal.addCurve(to: CGPoint(x: -p * 0.16, y: -p * 0.86), control1: CGPoint(x: -p, y: p * 0.2),
                               control2: CGPoint(x: -p * 0.62, y: -p))
                petal.addLine(to: CGPoint(x: 0, y: -p * 0.58))
                petal.addLine(to: CGPoint(x: p * 0.16, y: -p * 0.86))
                petal.addCurve(to: CGPoint(x: 0, y: p), control1: CGPoint(x: p * 0.62, y: -p), control2: CGPoint(x: p, y: p * 0.2))
                c.fill(petal, with: .color(Self.petal))
            }
        }
    }

    private static let petal = Color(hex: "#FFB0C8")

    // MARK: - Badges

    /// Small Tomo's badges: what it's doing, never how many of anything.
    public enum Badge: CaseIterable, Sendable {
        case checking          // a "…" thought bubble: it's checking an answer (`.thinking`)
        case dozing            // a tiny Zz: dozing off when ignored, or asleep
    }

    /// The badge Tomo would wear now (shown only with `showsBadges`): none while a big moment, an arrival or the hello
    /// plays (they own its face), while it's up in the notch, or in its egg. Mossy is asleep, so it dozes.
    public var badge: Badge? {
        guard cue == nil, !isAway, !shell else { return nil }
        if state == .thinking { return .checking }
        if state == .sleeping || drowsy || feelingShown.sleep > 0.5 { return .dozing }
        return nil
    }

    /// Where a badge sits for a canvas of `size` (Tomo drawn as `draw` draws it): beside its head on its right, the room
    /// a host leaves for it, in the canvas's coordinates. It reaches past the canvas's right edge.
    public func badgeFrame(size: CGSize) -> CGRect {
        let form = look.form(age), R = size.width * 0.27
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + particleOverhang / 2 + R * 0.1)
        let r = R * form.scale * fit(form: form, R: R, ground: center.y + form.bottom * R, moss: mossShown(pose))
        let a = badgeAnchor(center: center, r: r), u = badgeUnit(r)
        return CGRect(x: a.x - u * 0.15, y: a.y - u * 0.8, width: u * 1.9, height: u * 1.45)
    }

    /// A badge's size: Tomo's radius, at most 11 pt.
    private func badgeUnit(_ r: CGFloat) -> CGFloat { min(r, 11) }

    /// Just off Tomo's body on its right, a little above its middle (the body's edge there is about 0.9 r out), low
    /// enough that the badge stays under the top of a 24 pt island at every age.
    private func badgeAnchor(center c: CGPoint, r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * 0.9 + badgeUnit(r) * 0.25, y: c.y - r * 0.3)
    }

    /// How far each part of a badge bobs now, in units: the bubble's three dots hop in turn, and the Z's float. Still
    /// under Reduce Motion.
    func badgeBob(_ part: Int, now: Double) -> CGFloat {
        guard !reduceMotion else { return 0 }
        switch badgeShown.badge {
        case .checking: return 0.18 * max(0, CGFloat(sin(now * 6 - Double(part) * 0.9)))
        case .dozing: return 0.1 * CGFloat(sin(now * 1.3)) * (part == 0 ? 1 : -0.6)
        }
    }

    private func drawBadge(_ ctx: GraphicsContext, _ b: Badge, at a: CGPoint, unit u: CGFloat, alpha: CGFloat, now: Double) {
        var c = ctx
        c.opacity = Double(min(1, alpha))
        switch b {
        case .checking:                    // a thought bubble: two little puffs from Tomo's head, then "…"
            let mid = CGPoint(x: a.x + u * 0.95, y: a.y - u * 0.2)
            let soft = GraphicsContext.Shading.color(.white.opacity(0.2))
            for (dx, dy, r) in [(0.0, 0.45, 0.09), (0.2, 0.25, 0.13)] as [(CGFloat, CGFloat, CGFloat)] {
                c.fill(Path(ellipseIn: CGRect(x: a.x + dx * u - r * u, y: a.y + dy * u - r * u, width: r * u * 2, height: r * u * 2)),
                       with: soft)
            }
            c.fill(Path(roundedRect: CGRect(x: mid.x - u * 0.72, y: mid.y - u * 0.5, width: u * 1.44, height: u),
                        cornerRadius: u * 0.5), with: soft)
            for i in 0..<3 {
                let d = CGPoint(x: mid.x + CGFloat(i - 1) * u * 0.4, y: mid.y - badgeBob(i, now: now) * u)
                c.fill(Path(ellipseIn: CGRect(x: d.x - u * 0.12, y: d.y - u * 0.12, width: u * 0.24, height: u * 0.24)),
                       with: .color(.white.opacity(0.9)))
            }
        case .dozing:                      // Zz: a bigger Z, and a smaller one up and to its right
            let line = StrokeStyle(lineWidth: u * 0.13, lineCap: .round, lineJoin: .round)
            for (i, (dx, dy, k)) in ([(0.3, 0.05, 0.6), (0.98, -0.45, 0.4)] as [(CGFloat, CGFloat, CGFloat)]).enumerated() {
                let o = CGPoint(x: a.x + dx * u, y: a.y + (dy + badgeBob(i, now: now)) * u), h = k * u
                var z = Path()
                z.move(to: CGPoint(x: o.x - h * 0.4, y: o.y - h * 0.5)); z.addLine(to: CGPoint(x: o.x + h * 0.4, y: o.y - h * 0.5))
                z.addLine(to: CGPoint(x: o.x - h * 0.4, y: o.y + h * 0.5)); z.addLine(to: CGPoint(x: o.x + h * 0.4, y: o.y + h * 0.5))
                c.stroke(z, with: .color(.white.opacity(0.8)), style: line)
            }
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
        public static let amber = Color(hex: "#F2B04A")        // the island's countdown line's amber
    }

    /// The call glow's strength now (`callGlow`, eased): a soft pulse every 2.6 s, or steady under Reduce Motion.
    private func callGlowAlpha(_ now: Double) -> CGFloat {
        guard callGlowShown > 0 else { return 0 }
        if reduceMotion { return callGlowShown * 0.62 }
        let pulse = 0.5 - 0.5 * CGFloat(cos(now * 2 * .pi / 2.6))
        return callGlowShown * (0.4 + 0.5 * pulse)
    }

    /// Small Tomo's amber call glow: a radial around it, behind everything else.
    private func drawCallGlow(_ ctx: GraphicsContext, center c: CGPoint, R: CGFloat, now: Double, fade: CGFloat) {
        let a = Double(callGlowAlpha(now) * fade)
        guard a > 0.002 else { return }
        let r = R * 1.8
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: Palette.amber.opacity(a), location: 0),
                    .init(color: Palette.amber.opacity(a * 0.45), location: 0.5),
                    .init(color: Palette.amber.opacity(0), location: 1),
                 ]), center: c, startRadius: 0, endRadius: r))
    }

    /// The goo strand from the notch (`a`) to Tomo's head (`b`), in Tomo's colour: wide where it meets each, thin in the
    /// middle. Once it lets go, its two ends spring back, into the notch and into Tomo.
    private func drawStrand(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, _ s: Strand, R: CGFloat,
                            fade: CGFloat) {
        let tip = CGPoint(x: a.x + (b.x - a.x) * s.reach, y: a.y + (b.y - a.y) * s.reach)
        let len = hypot(tip.x - a.x, tip.y - a.y)
        guard len > 0.5 else { return }
        let n = CGPoint(x: -(tip.y - a.y) / len, y: (tip.x - a.x) / len)        // across the strand
        func at(_ u: CGFloat, _ w: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (tip.x - a.x) * u + n.x * w, y: a.y + (tip.y - a.y) * u + n.y * w)
        }
        // A tapered piece from u0 (width w0) to u1 (width w1), pinched to `mid` halfway.
        func piece(_ u0: CGFloat, _ w0: CGFloat, _ u1: CGFloat, _ w1: CGFloat, mid: CGFloat) -> Path {
            let um = (u0 + u1) / 2, pinch = 2 * mid - (w0 + w1) / 2
            var p = Path()
            p.move(to: at(u0, w0))
            p.addQuadCurve(to: at(u1, w1), control: at(um, pinch))
            p.addLine(to: at(u1, -w1))
            p.addQuadCurve(to: at(u0, -w0), control: at(um, -pinch))
            p.closeSubpath()
            return p
        }
        var c = ctx
        c.opacity = Double(max(0, fade) * (1 - 0.4 * s.recoil))
        let top = R * 0.2, joint = R * 0.3
        if s.recoil == 0 {
            c.fill(piece(0, top, 1, s.reach < 1 ? R * 0.06 : joint, mid: R * (0.025 + 0.11 * s.neck)),
                   with: .color(paint.body))
        } else {                                           // let go: each end springs back to where it hangs from
            let k = 1 - s.recoil
            c.fill(piece(0, top, 0.5 * k, 0.01 * R, mid: top * 0.35), with: .color(paint.body))
            c.fill(piece(1 - 0.3 * k, 0.01 * R, 1, joint * k, mid: joint * 0.4 * k), with: .color(paint.body))
        }
    }

    /// The hello's drop: a bead swelling at the notch (`from`), then falling faster and faster to Tomo's base (`to`),
    /// growing as it goes; Tomo gathers out of it as it lands (`.hello`).
    private func drawHelloDrop(_ ctx: GraphicsContext, _ d: CGFloat, from a: CGPoint, to b: CGPoint, R: CGFloat) {
        let form = Self.helloBead
        if d < form {                                       // swelling where it hangs
            let r = R * 0.14 * Self.inOut(d / form)
            material.drawDrop(ctx, at: CGPoint(x: a.x, y: a.y + r * 1.15), r: r, stretch: 0.2, look: paint)
            return
        }
        let u = (d - form) / (1 - form), r = R * (0.14 + 0.16 * u)
        let start = a.y + R * 0.14 * 1.15, end = b.y - r * 1.15
        material.drawDrop(ctx, at: CGPoint(x: a.x + (b.x - a.x) * u, y: start + (end - start) * u * u), r: r,
                          stretch: 0.3 + 1.2 * u, look: paint)
    }

    private func drawBody(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, glow: CGFloat, light: TomoMaterial.Glow,
                          moss: CGFloat, t: CGFloat) {
        let top = -form.top * R, bottom = form.bottom * R
        let body = feelingShown.sag > 0.005 ? slumped(form, R: R, top: top, bottom: bottom) : form.path(R: R)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [paint.bodyLight, paint.body]),
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
        material.drawInside(inner, form: form, body: body, R: R, top: top, bottom: bottom, glow: light)
        if glow > 0.01 { inner.fill(body, with: .color(.white.opacity(Double(glow)))) }
        if moss > 0.01 { drawMoss(ctx, inner: inner, form: form, R: R, top: top, amount: moss, t: t) }
    }

    /// How far above its body's top mossy's sprout reaches, upright, in units of R, the moss `moss` grown (`drawMoss`).
    static func sproutReach(moss: CGFloat) -> CGFloat {
        moss > 0.6 ? max(0, sproutSize * eOut((moss - 0.6) / 0.4) * 1.45 - 0.06) : 0
    }

    /// The sprout's height, in units of R (`TomoFeeling.sprout`), and its foot below the body's top.
    private static let sproutSize: CGFloat = 0.24

    /// Mossy's moss, `amount` grown (#258, the states lab's Patches): its seeded patches (`TomoFeeling.mossPatches`)
    /// spreading from its crown to just over its eyes, inside its outline, in greens that show on its colour; then a
    /// sprout that grows and sways on the sway spring (still under Reduce Motion). Fixed fills from the clock.
    private func drawMoss(_ ctx: GraphicsContext, inner: GraphicsContext, form: TomoForm, R: CGFloat, top: CGFloat,
                          amount: CGFloat, t: CGFloat) {
        let light = look.drawnTones.head.l
        if mossKept?.seed != look.seed || mossKept?.light != light {
            mossKept = (look.seed, light, TomoFeeling.mossPatches(seed: look.markSeed),
                        TomoFeeling.mossColours(headLightness: light))
        }
        guard let kept = mossKept else { return }
        let greens = kept.greens
        let eyes = (form.faceY + look.eyeY - 0.3) * R
        var patches = Path(), lights = Path()
        for (i, m) in kept.patches.enumerated() {
            let k = TomoFeeling.patchGrowth(i, amount: amount)
            guard k > 0 else { continue }
            let x = m.x * form.rx * R, y = top + (eyes - top) * m.y, r = m.r * R * k, l = r * 0.26
            patches.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            lights.addEllipse(in: CGRect(x: x - r * 0.3 - l, y: y - r * 0.35 - l, width: l * 2, height: l * 2))
        }
        inner.fill(patches, with: .color(greens.base))
        inner.fill(lights, with: .color(greens.light))
        guard amount > 0.6 else { return }
        let size = R * Self.sproutSize * Self.eOut((amount - 0.6) / 0.4)
        guard size > 0.5 else { return }
        var c = ctx
        c.translateBy(x: -0.18 * form.rx * R, y: top + R * 0.06)
        c.rotate(by: .radians(Double(-0.2 + (reduceMotion ? 0 : sin(t * 1.3) * 0.08 + sway * 0.9))))
        let sprout = TomoFeeling.sprout(size)
        c.stroke(sprout.stem, with: .color(Palette.leafDark), style: StrokeStyle(lineWidth: max(0.8, size * 0.16), lineCap: .round))
        c.fill(sprout.leaves, with: .color(Palette.leaf))
    }

    /// Droopy's outline: the warp of whatever outline `form` draws (`TomoFeeling.sagged`), so it slumps through a
    /// birthday's morph too, kept while the sag holds so a slumped Tomo at rest doesn't build it every frame. Only an
    /// age's own form is kept: while a birthday's morph is on show (#282) the outline changes every frame, and Reduce
    /// Motion's crossfade draws two forms, so it's built fresh then and never kept, whatever script plays over it.
    private func slumped(_ form: TomoForm, R: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        let sag = feelingShown.sag, keeps = form.morphed == nil && morph == nil
        if keeps, let s = slump, s.seed == look.seed, s.age == age, s.R == R, s.sag == sag { return s.body }
        let body = TomoFeeling.sagged(form.path(R: R), top: top, bottom: bottom, by: sag)
        slump = keeps ? (look.seed, age, R, sag, body) : nil
        return body
    }

    /// Sickly's sweat drop, at the side of its head, sliding down and fading on a loop from the clock (fixed under
    /// Reduce Motion): a fill, nothing emitted.
    private func drawSweat(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, t: CGFloat) {
        let phase = reduceMotion ? 0.3 : (t * 0.32).truncatingRemainder(dividingBy: 1)
        let c = CGPoint(x: form.rx * 0.7 * R, y: (form.faceY - 0.42) * R + phase * 0.32 * R), s = R * 0.075
        var drop = ctx
        drop.opacity = Double(feelingShown.sweat * (reduceMotion ? 1 : min(1, (1 - phase) * 4, phase * 8 + 0.2)))
        drop.fill(TomoFeeling.sweatDrop(at: c, s: s), with: .color(TomoFeeling.sweat))
        drop.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.48, y: c.y - s * 0.11, width: s * 0.36, height: s * 0.52)),
                  with: .color(.white.opacity(0.8)))
    }

    /// Its markings, in its second colour, kept off the face.
    private func drawPattern(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, top: CGFloat, bottom: CGFloat) {
        let accent = GraphicsContext.Shading.color(paint.accent)
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
                     with: .linearGradient(Gradient(colors: [paint.accent, paint.accent.opacity(0)]),
                                           startPoint: CGPoint(x: -w, y: top), endPoint: CGPoint(x: w * 0.4, y: bottom)))
        }
    }

    /// The idle moves' room under a `ceiling`: its stretch (9% taller) as it breathes in (1.8%; asleep, 3.5% and no
    /// stretch), and a hop as it wakes (0.18 R up). A birthday's morph, overshoot and stretch included, stays within it
    /// (`ceilingSelfTest`); a big moment's leap, which is rare and quick, may still reach past it.
    static let idleStretch: CGFloat = 1.09 * 1.018
    static let idleLift: CGFloat = 0.18

    /// How much smaller than its age's size Tomo is drawn to stand under `ceiling` (1: its own size), for where its
    /// ground is at rest (canvas points): its body and topper (and mossy's sprout), stretched and hopping as it does when
    /// idle, reach no higher than the ceiling. Never under half its size.
    func fit(form: TomoForm, R: CGFloat, ground: CGFloat, moss: CGFloat) -> CGFloat {
        guard let ceiling else { return 1 }
        let top = max(standingTop(form), form.top + Self.sproutReach(moss: moss))
        let tall = (top + form.bottom) * R * form.scale * Self.idleStretch
        let room = ground - ceiling - Self.idleLift * R
        return tall > room ? max(0.5, room / tall) : 1
    }

    /// How far above its middle Tomo reaches at rest, upright, in units of R: its body's outline or its topper, whichever
    /// is higher. Kept for its look and age, so the outline isn't built every frame.
    private func standingTop(_ form: TomoForm) -> CGFloat {
        if let s = standing, s.seed == look.seed, s.age == age { return s.top }
        let top = max(-form.path(R: 1).boundingRect.minY, topperTop(form))
        standing = (look.seed, age, top)
        return top
    }

    /// How far above its middle its topper reaches, upright, in units of R (0 without one): `drawTopper`'s shapes, with
    /// their tips. Ears lean out as they're drawn, so they reach a little less.
    func topperTop(_ form: TomoForm) -> CGFloat {
        guard age >= 1 else { return 0 }
        let grow = Self.topperGrow(age), lift = -Self.topperLift(form)
        let size = Self.topperSize(look.topper) * grow
        switch look.topper {
        case .none: return 0
        case .cat, .bunny, .horns: return lift + size
        case .bear: return lift + size * 1.5
        case .antenna: return form.top - 0.08 + size + 0.09     // its ball
        case .sprout: return form.top - 0.06 + size + 0.16      // its leaves
        }
    }

    /// A topper grows with age, from 1さい's 0.8.
    private static func topperGrow(_ age: Int) -> CGFloat { 0.8 + 0.06 * CGFloat(age) }
    /// Where a pair (ears, horns) stands on the head, in R from its middle (negative: up).
    private static func topperLift(_ form: TomoForm) -> CGFloat {
        form.drop - form.ry * 0.74
    }
    /// Each topper's size in R before it grows: an ear's or a horn's height, a bear ear's radius, a stem's length.
    private static func topperSize(_ topper: TomoLook.Topper) -> CGFloat {
        switch topper {
        case .none: 0
        case .cat: 0.48
        case .bunny: 0.8
        case .bear: 0.21
        case .horns: 0.36
        case .antenna: 0.42
        case .sprout: 0.3
        }
    }

    /// What grows on its head from 2さい (ears, horns, an antenna or a sprout), swaying after every move. `age`: the
    /// form's (a birthday's crossfade draws the old one too). Droopy flops it (`feelingShown.flop`): ears and horns tip
    /// out and down, the longer the floppier, and a stem bends over and droops.
    private func drawTopper(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, age: Int) {
        guard age >= 1, look.topper != .none else { return }
        let lift = Self.topperLift(form)
        let size = R * Self.topperSize(look.topper) * Self.topperGrow(age)
        let spread = form.rx * form.earSpread
        let fill = GraphicsContext.Shading.color(paint.bodyLight)
        let inside = GraphicsContext.Shading.color(paint.cheek.opacity(0.55))
        let fl = feelingShown.flop, lean: CGFloat = form.sproutLean < 0 ? -1 : 1
        func pair(floppy k: CGFloat, _ draw: (GraphicsContext, CGFloat) -> Void) {
            for side: CGFloat in [-1, 1] {
                var c = ctx
                c.translateBy(x: side * spread * R, y: (lift + 0.05 * fl * k) * R)
                c.rotate(by: .radians(Double(side * (0.3 + k * fl) + sway * 0.5)))
                draw(c, side)
            }
        }
        switch look.topper {
        case .none:
            break
        case .cat:
            pair(floppy: 0.9) { c, _ in
                let h = size, b = R * 0.24
                c.fill(triangle(b, h), with: fill)
                c.fill(triangle(b * 0.55, h * 0.62), with: inside)
            }
        case .bunny:
            pair(floppy: 1.4) { c, _ in
                let h = size
                c.fill(Path(ellipseIn: CGRect(x: -R * 0.13, y: -h, width: R * 0.26, height: h + R * 0.1)), with: fill)
                c.fill(Path(ellipseIn: CGRect(x: -R * 0.065, y: -h * 0.85, width: R * 0.13, height: h * 0.75)), with: inside)
            }
        case .bear:
            pair(floppy: 0.3) { c, _ in
                let r = size
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 1.5, width: r * 2, height: r * 2)), with: fill)
                c.fill(Path(ellipseIn: CGRect(x: -r * 0.5, y: -r, width: r, height: r)), with: inside)
            }
        case .horns:
            pair(floppy: 0.2) { c, _ in
                c.fill(triangle(R * 0.11, size), with: .color(Palette.horn))
            }
        case .antenna:
            var c = ctx
            c.translateBy(x: 0, y: -form.top * R + R * 0.08)
            c.rotate(by: .radians(Double(form.sproutLean + sway * 0.9 + lean * fl * 0.9)))
            let L = size, tip = CGPoint(x: lean * fl * R * 0.2, y: -L * (1 - 0.3 * fl))   // flopped: bent over, lower
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: tip, control: CGPoint(x: R * 0.1 + tip.x, y: -L * 0.5))
            c.stroke(stem, with: .color(paint.ink.opacity(0.7)), style: StrokeStyle(lineWidth: R * 0.04, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: tip.x - R * 0.09, y: tip.y - R * 0.09, width: R * 0.18, height: R * 0.18)),
                   with: .color(look.pattern == .none ? paint.cheek : paint.accent))
        case .sprout:
            var c = ctx
            c.translateBy(x: 0, y: -form.top * R + R * 0.06)
            c.rotate(by: .radians(Double(form.sproutLean + sway * 0.9 + lean * fl * 0.8)))
            let L = size * (1 - 0.2 * fl)
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: -R * 0.08, y: -L * 0.5))
            c.stroke(stem, with: .color(Palette.leafDark), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
            for side: CGFloat in [-1, 1] {
                var leaf = Path()
                leaf.move(to: CGPoint(x: 0, y: -L))
                leaf.addQuadCurve(to: CGPoint(x: side * R * 0.24, y: -L - R * 0.1), control: CGPoint(x: side * R * 0.1, y: -L - R * 0.16))
                leaf.addQuadCurve(to: CGPoint(x: 0, y: -L), control: CGPoint(x: side * R * 0.16, y: -L + R * 0.02))
                if fl > 0 {                                 // flopped: the leaves droop, turning about the tip
                    leaf = leaf.applying(CGAffineTransform(translationX: 0, y: -L).rotated(by: fl * 0.35 * side)
                        .translatedBy(x: 0, y: L))
                }
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

    /// The face on show: a big moment's, else a flash, else the state's (asleep while mossy, sleepy while dozing).
    private var shownFace: Face {
        cue?.face ?? flash?.face ?? (feelingShown.sleep > 0.5 ? .sleep : drowsy ? .sleepy : baseFace)
    }

    private func drawFace(_ ctx: GraphicsContext, form: TomoForm, R: CGFloat, now: Double, mouth: CGFloat) {
        let face = shownFace
        let fit = min(1, form.faceW / 0.8) * (isMini ? 1.4 : 1)       // a small face gets smaller eyes
        let one: CGFloat = look.cyclops ? 1.55 : 1
        let faceY = form.faceY + 0.08 * feelingShown.sag                  // a slumped face sits lower
        let fx = look2.x * R * 0.16 * form.faceW, fy = -look2.y * R * 0.1 + (faceY + look.eyeY * fit) * R
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
                         with: .color(paint.cheek.opacity(Double(cheekA))))
            }
        }
        if form.details.contains(.freckles) {
            for side: CGFloat in [-1, 1] {
                for (dx, dy) in [(-0.06, 0.0), (0.05, -0.02), (0.0, 0.06)] as [(CGFloat, CGFloat)] {
                    let c = CGPoint(x: side * cheekX + fx * 0.6 + dx * R, y: low + dy * R)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.018, y: c.y - R * 0.018, width: R * 0.036, height: R * 0.036)),
                             with: .color(paint.ink.opacity(0.35)))
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
                          cornerRadius: mw), with: .color(paint.ink))
            return
        }
        var m = ctx
        m.translateBy(x: fx * 1.2, y: my + R * 0.02)
        let ink = GraphicsContext.Shading.color(paint.ink)
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
        let ink = GraphicsContext.Shading.color(paint.ink)
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
        /// Sickly's heavy lids (`feelingShown.lid`), tipped down at the outer corners into a worry (`worry`); a lidded eye's
        /// own lid stays at least where it was.
        func tired() {
            let rw = w, rh = h * open, f = feelingShown
            let lid = max(f.lid, look.eyeStyle == .lidded ? 0.375 : 0)
            var c = ctx
            c.clip(to: TomoFeeling.underLid(rw: rw, rh: rh, lid: lid, tilt: f.worry * rh * 0.9, side: side))
            c.fill(TomoForm.superellipse(rx: rw, ry: rh, n: look.eyeN), with: ink)
            guard open > 0.6, look.eyeStyle != .bead, lid < 0.6 else { return }
            let s = rw * (look.eyeStyle == .big ? 0.38 : 0.3), gy = max(-rh * 0.45, -rh + 2 * rh * lid + rh * 0.3)
            ctx.fill(Path(ellipseIn: CGRect(x: rw * 0.2 - s, y: gy - s, width: s * 2, height: s * 2)), with: .color(.white.opacity(0.9)))
        }
        switch face {
        case .normal: if feelingShown.lid > 0.02 || feelingShown.worry > 0.02 { tired() } else { eye(1) }
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
            case dust                          // a level-up's sparkle dust: fine glitter that bursts out and twinkles
            case confetti                      // a birthday's confetti, in Tomo's own colours
            case spore                         // the brush-off's moss spores, puffed up off its top
            public var gravity: CGFloat {
                switch self {
                case .pop: return 2.6
                case .sparkle: return 0.6
                case .dust: return 0.25
                case .spore: return 0.3
                case .confetti: return 2
                case .heart, .z: return -0.15
                }
            }
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
        /// Which of its colours (confetti: Tomo's palette, `confettiColor`; dust: gold, white or pale gold).
        public var tint = 0
        /// Where its twinkle (dust) or its tumble and flutter (confetti) start.
        public var phase: CGFloat = 0
    }

    /// A moment's particles never live longer than this, and are gone when the moment ends (`particleSelfTest`).
    static let momentParticleLife: Double = 2

    /// Particles fly at this pace under Reduce Motion, and only a third of them.
    private static let calmPace: CGFloat = 0.4

    /// While a big moment plays, only its own particles fly (`fromCue`). Every draw comes from `dice`.
    private func emit(_ kind: Bit.Kind, _ count: Int, fromCue: Bool = false) {
        guard !isMini, !isAway, cue == nil || fromCue else { return }
        let count = reduceMotion ? max(1, Int((Double(count) / 3).rounded())) : count
        let first = bits.count
        func draw(_ range: ClosedRange<CGFloat>) -> CGFloat { .random(in: range, using: &dice) }
        for _ in 0..<count {
            switch kind {
            case .sparkle:
                let a = draw(0...(2 * .pi))
                let speed = draw(0.7...1.2)
                bits.append(Bit(kind: kind, pos: CGPoint(x: cos(a) * 0.9, y: sin(a) * 0.9 - 0.1),
                                vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 0.5),
                                life: draw(0.6...0.9), size: draw(0.12...0.2), spin: draw(-4...4)))
            case .heart:
                bits.append(Bit(kind: kind, pos: CGPoint(x: draw(-0.6...0.6), y: -0.9),
                                vel: CGVector(dx: draw(-0.3...0.3), dy: draw(-0.9 ... -0.6)),
                                life: draw(1.0...1.4), size: draw(0.22...0.3), spin: 0))
            case .z:
                bits.append(Bit(kind: kind, pos: CGPoint(x: 0.6, y: -0.8),
                                vel: CGVector(dx: 0.25, dy: -0.45), life: 1.8, size: 0.3, spin: 0))
            case .pop:                         // drops of Tomo's own colour, flung out as it evolves
                let a = draw(0...(2 * .pi))
                let speed = draw(1.2...2.0)
                bits.append(Bit(kind: kind, pos: CGPoint(x: cos(a) * 0.6, y: sin(a) * 0.6),
                                vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 1.2),
                                life: draw(0.7...1.0), size: draw(0.08...0.15), spin: 0))
            case .dust:                        // out from all round Tomo, drifting up, then slowly settling
                let a = draw(0...(2 * .pi)), d = draw(0.3...1.0)
                let speed = draw(0.35...1.1)
                var b = Bit(kind: kind, pos: CGPoint(x: cos(a) * d, y: sin(a) * d - 0.15),
                            vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 0.6),
                            life: draw(1.0...1.6), size: draw(0.045...0.09), spin: 0)
                b.tint = Int.random(in: 0..<3, using: &dice)
                b.phase = draw(0...(2 * .pi))
                bits.append(b)
            case .confetti:                    // tossed up from its head, tumbling and fluttering down
                let a = draw((-0.67 * .pi)...(-0.33 * .pi)), speed = draw(1.6...2.6)
                var b = Bit(kind: kind, pos: CGPoint(x: draw(-0.35...0.35), y: -0.5),
                            vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed),
                            life: draw(1.2...1.8), size: draw(0.06...0.1), spin: draw(-6...6))
                b.tint = Int.random(in: 0..<4, using: &dice)
                b.phase = draw(0...(2 * .pi))
                bits.append(b)
            case .spore:                       // puffed up off its top, drifting and settling
                bits.append(Bit(kind: kind, pos: CGPoint(x: draw(-0.6...0.6), y: -0.7),
                                vel: CGVector(dx: draw(-0.6...0.6), dy: draw(-0.9 ... -0.4)),
                                life: draw(0.9...1.4), size: draw(0.04...0.07), spin: 0))
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
            case .dust:                        // a tiny four-point glint, twinkling as it fades
                c.opacity *= Double(0.7 + 0.3 * sin(CGFloat(b.age) * 16 * b.pace + b.phase))
                var glint = Path()
                glint.move(to: CGPoint(x: 0, y: -s)); glint.addLine(to: CGPoint(x: s * 0.3, y: 0))
                glint.addLine(to: CGPoint(x: 0, y: s)); glint.addLine(to: CGPoint(x: -s * 0.3, y: 0)); glint.closeSubpath()
                glint.addPath(Path(ellipseIn: CGRect(x: -s * 0.35, y: -s * 0.35, width: s * 0.7, height: s * 0.7)))
                c.fill(glint, with: .color(Self.dustColors[b.tint % Self.dustColors.count]))
            case .confetti:                    // a paper rectangle, flipping as it tumbles, held till its last third
                let q = b.age / b.life
                c.opacity = max(0, min(1, (1 - q) / 0.35))
                c.translateBy(x: sin(CGFloat(b.age) * 7 * b.pace + b.phase) * R * 0.12, y: 0)
                c.scaleBy(x: 1, y: max(0.15, abs(cos(CGFloat(b.age) * 9 * b.pace + b.phase))))
                c.fill(Path(CGRect(x: -s, y: -s * 0.6, width: s * 2, height: s * 1.2)), with: .color(confettiColor(b.tint)))
            case .spore:
                c.fill(Path(ellipseIn: CGRect(x: -s, y: -s, width: s * 2, height: s * 2)), with: .color(TomoFeeling.spore))
            }
        }
    }

    private static let dustColors = [Color(hex: "#FFE27A"), .white, Color(hex: "#FFF3B0")]

    /// Birthday confetti is Tomo's own: its body, its lighter top, its markings' colour and its cheeks.
    func confettiColor(_ tint: Int) -> Color {
        [look.body, look.bodyLight, look.accent, look.cheek][tint % 4]
    }

    // MARK: - Moves

    private enum Face { case normal, happy, sleep, sleepy, squeeze, surprised, love, confused, dizzy, wink, flat, star }

    /// The star eyes' rock, in radians: still under Reduce Motion (it's a face, so the stars stay).
    private func starRock(_ now: Double) -> CGFloat { reduceMotion ? 0 : CGFloat(sin(now * 5)) * 0.2 }

    private struct Move {
        public enum Kind {
            case hop(CGFloat), nudge, shake, wiggle(Int), gulp, rock, squish, wobble, mouth
            case peep, stretch, tiltHold(CGFloat), shuffle, lean(CGFloat)
            case sigh                          // droopy's fidget: it sinks a little, mouth a little open, and back
            case shiver(CGFloat)               // sickly's fidget: a quick side-to-side tremble that dies away
            case puff                          // Reduce Motion's stand-in for the others: a small swell
            // The cue scripts' moves. Each starts and ends at rest, so they add up; times are in seconds.
            case crouch                        // squeeze down, then let go to take off
            case leap(CGFloat)                 // up that high (in body radii) and down, stretched and twirling
            case settle                        // a few small rocks, dying away
            case evolve(squeeze: Double)       // squeeze down until then (the new shape), then pop out past size
            case glow(CGFloat, peak: Double)   // glow up to that brightness at that time (0: a flash), then fade
            case drip                          // down from the notch on a goo strand, stretched, landing with a bounce
            case pull                          // a strand reaches down, and Tomo is pulled up into the notch
            case fade(in: Bool)                // Reduce Motion's arrival or leaving: in or out where it sits
            case shine(peak: Double)           // a gold light from inside (the material's), up by then, then fading
            case hello                         // a drop falls from the notch, and Tomo gathers out of it as it lands
            case brush                         // the brush-off: the moss swept away in its first 45%
            case intoEgg(calm: Bool)           // curls up and the egg closes round it (calm: it fades into it, glowing)
            case hatch(calm: Bool)             // the egg shakes, cracks and splits, and Tomo springs out (calm: a fade)

            /// Carries Tomo off its spot, tips or squashes it: under Reduce Motion it becomes a puff, and during a big
            /// moment it's skipped (`add`). The mouth moves only open the mouth then, and a glow only glows (`pose`).
            public var movesBody: Bool {
                switch self {
                case .mouth, .peep, .gulp, .glow, .fade, .shine, .brush: return false
                case .intoEgg(let calm), .hatch(let calm): return !calm
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
        public var opacity: CGFloat = 1
        /// The goo strand to the notch, while dripping in or pulled up.
        public var strand: Strand?
        /// A moment's gold light from inside, 0…1 (the hello's).
        public var shine: CGFloat = 0
        /// The hello's drop on its way down from the notch, 0 … 1 (`drawHelloDrop`); nil once Tomo has gathered.
        public var drop: CGFloat?
        /// The egg while a script takes Tomo into it or out (`drawEgg`); nil: none, or resting in it.
        var egg: TomoEgg.Frame?
        /// How much of Tomo shows, as one piece (0: inside its egg), and how big (curling up, springing out).
        public var tomo: CGFloat = 1, size: CGFloat = 1
        /// The hatch's speech bubble (`hatchWord`), 0…1.
        public var bubble: CGFloat = 0
        /// How much of the moss a brush-off has left, 0…1 (`mossBrushed`).
        public var brushed: CGFloat = 0
    }

    /// The goo strand between the notch and Tomo's head (`drawStrand`).
    private struct Strand: Equatable {
        public var reach: CGFloat = 1                  // how far down from the notch it has got (1: to Tomo)
        public var neck: CGFloat = 1                   // its thinnest part, 1 thick … 0 about to let go
        public var recoil: CGFloat = 0                 // after letting go, 0 … 1: the two ends spring back and are gone
    }

    /// The drip's strand lets go this far through it (#130: by about 75%), once Tomo has landed.
    private static let letGo: CGFloat = 0.75

    /// The hello's drop lands this far through its move, after swelling at the notch for the first `helloBead` of the
    /// fall; then Tomo gathers out of it, from a puddle 1.85 wide and 0.3 tall, springing past its size and back.
    private static let helloLands: CGFloat = 0.4
    private static let helloBead: CGFloat = 0.25

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
            case .sigh:
                p.sy *= 1 - 0.06 * arc; p.dy += 0.04 * arc; p.mouth = max(p.mouth, 0.25 * arc)
            case .shiver(let a):
                p.dx += sin(q * 18 * .pi) * a * (1 - q * 0.5)
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
            case .drip:                            // falls stretched from about 1.9 R up, lands at 62% with a bounce
                let land: CGFloat = 0.62
                if q < land {
                    let e = q / land
                    p.dy -= 1.9 * (1 - e * e)
                    p.sy *= 1 + 0.55 * (1 - e); p.sx *= 1 - 0.28 * (1 - e)
                } else {
                    let k = (q - land) / (1 - land), w = sin(2 * .pi * k) * (1 - k)
                    p.sy *= 1 - 0.22 * w; p.sx *= 1 + 0.16 * w
                }
                p.opacity *= min(1, q / 0.1)
                let l = Self.letGo
                if q < l {
                    p.strand = Strand(neck: 1 - q / l)
                } else if q < l + 0.2 {
                    p.strand = Strand(neck: 0, recoil: (q - l) / 0.2)
                }
            case .pull:                            // a small crouch while the strand reaches down, then up and gone
                let lift: CGFloat = 0.3
                if q < lift {
                    let a = sin(.pi * q / lift)
                    p.sy *= 1 - 0.1 * a; p.sx *= 1 + 0.07 * a
                } else {
                    let e = (q - lift) / (1 - lift)
                    p.dy -= 1.9 * e * e
                    p.sy *= 1 + 0.55 * e; p.sx *= 1 - 0.28 * e
                }
                p.opacity *= 1 - Self.inOut(max(0, (q - 0.85) / 0.15))
                p.strand = Strand(reach: min(1, q / 0.2))
            case .fade(let appearing):
                let e = Self.inOut(q)
                p.opacity *= appearing ? e : 1 - e
            case .shine(let peak):
                let at = CGFloat(peak / m.duration)
                p.shine = max(p.shine, q < at ? Self.inOut(q / at) : 1 - (q - at) / max(1 - at, 0.001))
            case .hello:
                let land = Self.helloLands
                if q < land {
                    p.opacity = 0
                    p.drop = q / land
                } else {
                    let k = (q - land) / (1 - land), s = Self.gather(k)   // as solid as the drop it was
                    p.sx *= 1.85 - 0.85 * s; p.sy *= 0.3 + 0.7 * s
                }
            case .brush:
                p.brushed = max(p.brushed, 1 - Self.eOut(Self.seg(q, 0, 0.45)))
            case .intoEgg(let calm):               // the states lab's Shell, in seconds (`e`)
                let e = q * CGFloat(m.duration)
                if calm {
                    p.tomo *= 1 - Self.inOut(Self.seg(q, 0, 0.6))
                    p.egg = TomoEgg.Frame(alpha: Self.inOut(Self.seg(q, 0.35, 1)))
                    p.glow = max(p.glow, Self.bump(q) * 0.8)
                } else {                           // curls up, the bottom rises, the top drops on, and it settles
                    let curl = Self.inOut(Self.seg(e, 0, 0.7))
                    p.sy *= 1 - 0.16 * curl; p.sx *= 1 + 0.05 * curl; p.size *= 1 - 0.2 * curl
                    let rise = Self.eOut(Self.seg(e, 0.5, 1.2)), drop = Self.seg(e, 1, 1.6), land = Self.seg(e, 1.6, 2.4)
                    p.tomo *= 1 - Self.seg(e, 1.3, 1.6)
                    p.egg = TomoEgg.Frame(rot: sin(land * 14) * 0.07 * (1 - land),
                                          top: .init(dy: -(1 - Self.eIn(drop)) * TomoEgg.dropFrom, alpha: Self.seg(e, 1, 1.15)),
                                          bottom: .init(dy: (1 - rise) * 0.62, alpha: Self.seg(e, 0.5, 0.65)), clipFloor: true)
                }
            case .hatch(let calm):                 // the first run's hatch, in seconds (`e`)
                let e = q * CGFloat(m.duration), cracked = CGFloat(TomoEgg.crackTime)
                if calm {
                    p.egg = TomoEgg.Frame(alpha: 1 - Self.inOut(Self.seg(e, 0, 0.55)))
                    p.tomo *= Self.inOut(Self.seg(e, 0.3, 0.9))
                    p.glow = max(p.glow, Self.bump(Self.seg(e, 0, 1.4)) * 0.8)
                    p.bubble = max(p.bubble, Self.seg(e, 0.4, 0.55) * (1 - Self.seg(e, 1.3, 1.6)))
                } else if e < cracked {            // shaking and hopping as the crack runs across
                    p.tomo = 0
                    p.egg = TomoEgg.Frame(rot: sin(e * 60) * 0.12 * min(1, e * 3), hop: abs(sin(e * 14)) * 0.0345,
                                          crack: e / cracked)
                } else {                           // the halves fly apart, and Tomo springs out from half its size
                    p.egg = TomoEgg.Frame(split: Self.seg(e, cracked, 1.6))
                    p.size *= 0.5 + 0.5 * Self.springTo(Self.seg(e, cracked, 1.8), 5, 1.3)
                    p.bubble = max(p.bubble, Self.seg(e, 1, 1.15) * (1 - Self.seg(e, 2.4, 2.8)))
                }
            }
        }
        if puffed > 0 {
            p.sx *= 1 + 0.045 * puffed; p.sy *= 1 + 0.045 * puffed
            p.glow = max(p.glow, 0.16 * puffed)
        }
        if danceShown.amount > 0, cue == nil, !reduceMotion { danceStep(&p, now: now, amount: danceShown.amount) }
        return p
    }

    /// Beats a second at the dance's fixed 112 BPM.
    static let danceBeat: Double = 112.0 / 60

    /// The dance's part of Tomo's pose now: `amount` 0…1 as it fades in or out.
    private func danceStep(_ p: inout Pose, now: Double, amount k: CGFloat) {
        let beat = CGFloat(now * Self.danceBeat)          // beats so far
        switch danceShown.dance {
        case .bounce:                    // up on every beat, a squash as it lands, swaying side to side every two
            let up = abs(sin(.pi * beat)), side = sin(.pi * beat)
            p.dy -= 0.16 * up * k
            p.sy *= 1 + (0.06 * up - 0.07 * pow(1 - up, 6)) * k
            p.sx *= 1 - (0.04 * up - 0.06 * pow(1 - up, 6)) * k
            p.rot += 0.12 * side * k
            p.dx += 0.05 * side * k
        case .bonOdori:                  // 盆踊り at half speed: a step to one side, a bob, a step back
            let step = sin(.pi * beat / 2), bob = abs(sin(.pi * beat / 2))
            p.dx += 0.14 * step * k
            p.dy -= 0.06 * bob * k
            p.rot += 0.08 * step * k
            p.sy *= 1 - 0.03 * (1 - bob) * k
        }
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

    /// 0 → 1 on a loose spring: past 1 by about a quarter, back under, and settled exactly at 1 (the hello's gather).
    private static func gather(_ k: CGFloat) -> CGFloat {
        1 - (1 - k) * exp(-3 * k) * cos(3 * .pi * k)
    }

    /// The states lab's easing, for the egg's scripts and the moss: `seg` is how far `q` is from `a` to `b` (0…1),
    /// `eOut` and `eIn` ease out and in (cubic), `bump` rises and falls once, and `springTo` springs past 1 and settles.
    private static func seg(_ q: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(1, max(0, (q - a) / (b - a))) }
    private static func eOut(_ u: CGFloat) -> CGFloat { let v = 1 - min(1, max(0, u)); return 1 - v * v * v }
    private static func eIn(_ u: CGFloat) -> CGFloat { let v = min(1, max(0, u)); return v * v * v }
    private static func bump(_ u: CGFloat) -> CGFloat { sin(.pi * min(1, max(0, u))) }
    private static func springTo(_ u: CGFloat, _ b: CGFloat, _ f: CGFloat) -> CGFloat {
        u <= 0 ? 0 : u >= 1 ? 1 : 1 - exp(-b * u) * cos(f * 2 * .pi * u)
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
            case face(Face?)                   // worn from then on, until the next face or the end (nil: its own again)
            case move(Move.Kind, Double)       // a move for that many seconds, starting exactly at the step's time
            case sparkles(Int)
            case dust(Int)                     // sparkle dust (a level-up's)
            case confetti(Int)                 // confetti in Tomo's own colours (a birthday's)
            case drops(Int)                    // drops of Tomo's own colour
            case kick(CGFloat)                 // a jiggle, as on landing
            case swap                          // the new shape: the age or look the script was started with
            case morph(Double)                 // the swap, with the old outline flowing into the new for that long
            case away                          // gone up into the notch, until `dripIn` or `appear`
            case spores(Int)                   // moss spores (the brush-off's)
            case brushMoss                     // the moss grown so far is swept away by the script's `brush` move
        }
        let length: Double
        let lively: [(at: Double, step: Step)]
        let calm: [(at: Double, step: Step)]
        /// How long the calm version is, when it isn't `length`.
        var calmLength: Double?
    }

    /// A new level (about 2.1 s): squeeze, then flash and leap with star eyes in a burst of sparkles and sparkle dust,
    /// land with a jiggle kick, settle with happy eyes.
    private static let levelUpCue = Cue(length: 2.1, lively: [
        (0, .face(.squeeze)), (0, .move(.crouch, 0.35)),
        (0.35, .face(.star)), (0.35, .move(.leap(0.55), 0.6)), (0.35, .move(.glow(0.85, peak: 0), 0.45)),
        (0.38, .sparkles(5)), (0.38, .dust(26)),
        (0.95, .move(.squish, 0.35)), (0.95, .kick(6)), (0.95, .sparkles(3)),
        (1.3, .move(.settle, 0.8)), (1.3, .face(.happy)),
    ], calm: [
        (0, .face(.star)), (0, .move(.glow(0.5, peak: 0.25), 0.5)), (0, .move(.puff, 0.5)),
        (0.15, .sparkles(5)), (0.15, .dust(26)),
        (1.7, .face(.happy)),
    ])

    /// A birthday (about 2.6 s): the old outline flows into the new one (1.2 s, the states lab's Flubber option,
    /// `TomoFormMorph.flubber`), reaching it at 0.2 s with drops of Tomo's colour, confetti in its own colours and star
    /// eyes, springing past it and back, wobbling; then it lands with a jiggle and settles, happy. Under Reduce Motion
    /// the new form fades in over the old (0.9 s), glowing softly, with star eyes from 0.135 s.
    private static let birthdayCue = Cue(length: 2.6, lively: [
        (0, .morph(1.2)),
        (0.2, .face(.star)), (0.2, .drops(12)), (0.2, .confetti(26)), (0.22, .sparkles(6)),
        (1.2, .kick(6)), (1.2, .sparkles(3)), (1.2, .move(.settle, 0.8)),
        (1.8, .face(.happy)),
    ], calm: [
        (0, .morph(0.9)),
        (0.135, .face(.star)),
        (0.45, .drops(12)), (0.45, .confetti(26)), (0.45, .move(.puff, 0.5)), (0.5, .sparkles(6)),
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

    /// A visit arrives (about 0.75 s): Tomo drips down from the notch, stretched 1.55 × 0.72 from about 1.9 R up, and
    /// lands with a jiggle while the strand thins and lets go at 75%. Under Reduce Motion: a fade in and a small puff.
    private static let dripInCue = Cue(length: 0.75, lively: [
        (0, .move(.drip, 0.75)),
        (0.47, .kick(5)),
    ], calm: [
        (0, .move(.fade(in: true), 0.4)), (0, .move(.puff, 0.5)),
    ])

    /// Leaving (about 0.45 s), the drip in reverse: a strand reaches down, and Tomo is pulled up into the notch,
    /// stretching. Under Reduce Motion: a fade out. Then Tomo is away.
    private static let pullUpCue = Cue(length: 0.45, lively: [
        (0, .move(.pull, 0.45)),
        (0.45, .away),
    ], calm: [
        (0, .move(.fade(in: false), 0.45)),
        (0.45, .away),
    ])

    /// Each material's hello (`hello`), or none. Lit clay, paper cut and lantern would add theirs here (#137).
    private static func helloCue(_ material: TomoMaterial) -> Cue? {
        switch material {
        case .classic: return nil
        case .jelly: return jellyHelloCue
        }
    }

    /// Jelly's hello (about 1.8 s): a drop swells at the notch and falls (0–0.46 s), and Tomo gathers out of it as it
    /// lands, sleepy-eyed, from a puddle to past its size and back, lit gold from inside; then it opens its eyes, beams
    /// and wiggles. Under Reduce Motion: a fade in with the same gold light and faces, and a small puff.
    private static let jellyHelloCue = Cue(length: 1.8, lively: [
        (0, .face(.sleep)), (0, .move(.hello, 1.15)),
        (0.46, .move(.shine(peak: 0.3), 1.1)),
        (0.8, .face(.normal)),
        (1.15, .kick(4)), (1.15, .face(.happy)), (1.2, .move(.wiggle(4), 0.5)),
    ], calm: [
        (0, .face(.sleep)), (0, .move(.fade(in: true), 0.6)), (0, .move(.shine(peak: 0.3), 1.4)), (0, .move(.puff, 0.5)),
        (0.36, .face(.happy)),
    ])

    /// Back into its egg (#258, about 2.4 s, the states lab's Shell): Tomo curls up and falls asleep, the egg's bottom
    /// rises round it, its top drops on, and it settles with a rock. Under Reduce Motion (0.9 s) Tomo fades into the egg
    /// with a glow and star eyes. Then it rests in its egg (`drawEgg`).
    private static let intoEggCue = Cue(length: 2.4, lively: [
        (0, .move(.intoEgg(calm: false), 2.4)), (0.3, .face(.sleep)),
    ], calm: [
        (0, .face(.star)), (0, .move(.intoEgg(calm: true), 0.9)),
    ], calmLength: 0.9)

    /// The hatch (#258, about 2.8 s, the first run's): the egg shakes and hops as its crack runs across (0.9 s), the
    /// halves fly apart in a few sparkles, and Tomo springs out from half its size, surprised, saying `hatchWord`. Under
    /// Reduce Motion (1.6 s) the egg fades and Tomo fades in with a glow, star eyes and a puff.
    private static let hatchCue = Cue(length: 2.8, lively: [
        (0, .move(.hatch(calm: false), 2.8)),
        (0.9, .sparkles(5)), (0.9, .face(.surprised)),
        (1.5, .face(nil)),
    ], calm: [
        (0, .move(.hatch(calm: true), 1.6)), (0, .move(.puff, 0.5)), (0, .face(.star)),
        (1.2, .face(nil)),
    ], calmLength: 1.6)

    /// The brush-off (#258, about 1.5 s): back to well from mossy, Tomo shakes the moss off its top, happy, in a puff of
    /// spores and a few sparkles; the moss is gone in the first 0.6 s, and the script outlasts its spores (1.4 s at
    /// most). Under Reduce Motion the shake is a puff, and the spores and sparkles are a third, slower.
    private static let brushCue = Cue(length: 1.5, lively: [
        (0, .face(.happy)), (0, .move(.shake, 0.6)), (0, .brushMoss), (0, .move(.brush, 1.4)),
        (0, .spores(12)), (0, .sparkles(4)),
        (1.2, .face(nil)),
    ], calm: [
        (0, .face(.happy)), (0, .move(.puff, 0.5)), (0, .brushMoss), (0, .move(.brush, 1.4)),
        (0, .spores(12)), (0, .sparkles(4)),
        (1.2, .face(nil)),
    ])

    /// Back from the notch without the drip (`appear`): a quick fade in.
    private static let appearCue = Cue(length: 0.25, lively: [(0, .move(.fade(in: true), 0.25))],
                                       calm: [(0, .move(.fade(in: true), 0.25))])

    /// A script playing: its steps (lively or calm, picked when it starts), how far it has got, and what it opened.
    private final class Playing {
        let length: Double
        let start: Double
        let steps: [(at: Double, step: Cue.Step)]
        var next = 0                           // the first step not fired yet
        var fired: [Double] = []               // the clock when each step fired (the self-test reads it)
        var face: Face?
        var swap: (age: Int, look: TomoLook)?  // what `.swap` changes to; nil once it has
        /// It ends with Tomo up in the notch (`pullUp`).
        let goesAway: Bool
        /// The calm steps, under Reduce Motion.
        let calm: Bool

        init(_ cue: Cue, start: Double, calm: Bool, swap: (age: Int, look: TomoLook)?) {
            length = calm ? cue.calmLength ?? cue.length : cue.length
            self.start = start
            steps = calm ? cue.calm : cue.lively
            self.swap = swap
            self.calm = calm
            goesAway = steps.contains { if case .away = $0.step { return true } else { return false } }
        }
    }

    /// A birthday's morph playing (`Cue.Step.morph`): the two forms, the ages and Tomo they belong to, and when it
    /// started on Tomo's clock. It isn't the script's, so a newer script doesn't stop it: it still lands on the new form.
    private struct Morphing {
        let shapes: TomoFormMorph
        let fromAge: Int, toAge: Int
        let seed: String
        let start: Double, length: Double
        let calm: Bool                         // Reduce Motion's crossfade
    }

    /// A morph drawn: the frame of the form on show, how far a first topper (2さい's) has grown in, and under Reduce
    /// Motion the old form still showing over the new one.
    struct MorphFrame {
        let form: TomoForm
        let beat: TomoFormMorph.Beat
        let topper: CGFloat
        let old: (form: TomoForm, age: Int, alpha: CGFloat)?
    }

    /// The morph's frame `now`, while one is playing into the form on show (nil once it's done, or Tomo has become
    /// another Tomo or age since).
    func morphFrame(_ now: Double) -> MorphFrame? {
        guard let m = morph else { return nil }
        let e = now - m.start
        guard e < m.length, m.toAge == age, m.seed == look.seed else { morph = nil; return nil }
        if m.calm {
            let b = TomoFormMorph.crossfade(e, length: m.length)
            return MorphFrame(form: m.shapes.to, beat: b, topper: 1, old: (m.shapes.from, m.fromAge, b.fade))
        }
        let b = TomoFormMorph.flubber(e, length: m.length)
        let topper = m.fromAge < 1 ? min(1, max(0, (b.u - 0.35) / 0.3)) : 1     // the lab's seg(u, 0.35, 0.65)
        return MorphFrame(form: m.shapes.form(at: b.u, wobble: b.wobble, phase: b.phase), beat: b, topper: topper, old: nil)
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
    /// app in the background) only swaps the shape, or goes away.
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
            case .morph(let length):
                if let s = c.swap {
                    let old = (form: look.form(age), age: age)
                    age = s.age; look = s.look; c.swap = nil
                    if !over {
                        morph = Morphing(shapes: TomoFormMorph(old.form, look.form(age)), fromAge: old.age, toAge: age,
                                         seed: look.seed, start: c.start + at, length: length, calm: c.calm)
                    }
                }
            case .away:
                isAway = true
            case _ where over:
                break
            case .face(let f):
                c.face = f
            case .move(let kind, let duration):
                moves.append(Move(kind: kind, start: c.start + at, duration: duration, byCue: true))
            case .sparkles(let n):
                emit(.sparkle, n, fromCue: true)
            case .dust(let n):
                emit(.dust, n, fromCue: true)
            case .confetti(let n):
                emit(.confetti, n, fromCue: true)
            case .drops(let n):
                emit(.pop, n, fromCue: true)
            case .kick(let v):
                if !reduceMotion { jiggleVel += v * material.springs.kick }
            case .spores(let n):
                emit(.spore, n, fromCue: true)
            case .brushMoss:
                mossBrushed = feelingShown.moss
                feelingShown.moss = 0
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
    /// tell. Each material runs it well, droopy, sickly and mossy (#257, #258).
    static func motionSelfTest(_ check: (Bool, String) -> Void) {
        struct Run {
            var moved: CGFloat = 0, swell: CGFloat = 0, squash: CGFloat = 0, glow: CGFloat = 0
            var sparkles = 0, age = 0, blinks = 0, stars = 0
        }
        func run(reduce: Bool, _ material: TomoMaterial, _ feeling: TomoFeeling?) -> Run {
            let blob = TomoBlob(look: .mascot, material: material)
            blob.reduceMotion = reduce
            blob.feeling = feeling
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
        // Every material keeps these rules, whatever Tomo feels: its springs never move Tomo under Reduce Motion.
        let materials = TomoMaterial.allCases, feelings: [TomoFeeling?] = [nil] + TomoFeeling.allCases
        let names = materials.map(\.rawValue).joined(separator: ", ") + "; well, droopy, sickly and mossy"
        let calms = materials.flatMap { m in feelings.map { run(reduce: true, m, $0) } }
        let livelies = materials.flatMap { m in feelings.map { run(reduce: false, m, $0) } }
        let swell = calms.map(\.swell).max() ?? 1
        check(livelies.allSatisfy { $0.moved > 0.2 },
              "Tomo hops and shakes for a win, a miss, a poke, a level-up and a birthday (\(names))")
        check(calms.allSatisfy { $0.moved == 0 && $0.squash == 0 && $0.swell <= 0.046 },
              String(format: "under Reduce Motion they're a puff (%.1f%% at most): no hop, shake, tip, squash or wobble (%@)",
                     swell * 100, names))
        check(calms.allSatisfy { $0.glow > 0.4 && $0.stars > 120 },
              String(format: "under Reduce Motion a level-up and a birthday still glow (%.2f) with star eyes (%.1f s)",
                     calms[0].glow, Double(calms[0].stars) / 60))
        check(calms.allSatisfy { $0.age == 1 }, "under Reduce Motion a birthday still swaps Tomo's shape")
        check(calms.allSatisfy { $0.sparkles == 2 } && livelies.allSatisfy { $0.sparkles == 6 },
              "under Reduce Motion a win has a third of the sparkles (6 → 2)")
        check(calms.allSatisfy { $0.blinks > 0 }, "under Reduce Motion Tomo still blinks")
    }

    /// The small touches: a poke flops the ears or sprout (not under Reduce Motion), a level-up shows star eyes that
    /// rock (still under Reduce Motion), and love from resting on Tomo waits 6 s between shows.
    static func touchesSelfTest(_ check: (Bool, String) -> Void) {
        func flop(reduce: Bool, _ material: TomoMaterial = .classic) -> (sway: CGFloat, jiggle: CGFloat) {
            let blob = TomoBlob(look: .mascot, material: material)
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
        let lively = TomoMaterial.allCases.map { flop(reduce: false, $0) }
        let calm = TomoMaterial.allCases.map { flop(reduce: true, $0) }
        check(lively.allSatisfy { $0.sway > 0.3 && $0.jiggle > 0.05 },
              String(format: "a poke flops Tomo's ears or sprout (%.2f rad classic, %.2f jelly) and wobbles it",
                     lively[0].sway, lively[1].sway))
        // What sway is left follows the eyes' small darts (a few hundredths), not the poke.
        let calmSway = calm.map(\.sway).max() ?? 1
        check(calmSway < 0.05 && calm.allSatisfy { $0.jiggle == 0 },
              String(format: "under Reduce Motion a poke doesn't flop (%.3f rad) or wobble, in either material", calmSway))

        let blob = TomoBlob(look: .mascot, material: .classic)
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
            let b = TomoBlob(look: .mascot, material: .classic)
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
        check(onTime && exact && swappedAt == 0,
              "a script's steps each fire once, at their times (a birthday's new shape from 0 s, flowing out of the old), "
              + "however the frames fall")

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

        // A newer script closes what an older one opened: a level-up while another Tomo pops in (its swap at 0.62 s)
        // shows that Tomo now. A birthday's shape is new from its start, so nothing over it can lose it (the morph's
        // own check: TomoBlob.morphSelfTest).
        let b3 = blob(), other = TomoLook(seed: "selftest-other")
        b3.play(Self.newTomoCue, swap: (0, other))
        t = 100.3
        b3.step()
        let before = b3.look == TomoLook.mascot
        b3.levelUp()
        let closed = b3.look == other && b3.cue?.swap == nil
            && !b3.moves.contains { if case .evolve = $0.kind { return true } else { return false } }
        t = 100.5
        b3.step()
        b3.grow(to: 1)                                  // a birthday over the level-up: the new shape at once
        let grown = b3.age == 1
        t = 100.6
        b3.step()
        b3.grow(to: 1)                                  // the same birthday heard again: nothing more
        t = 100.75
        b3.step()
        let partying = b3.shownFace == .star            // 0.25 s into the first, past its star eyes at 0.2 s
        b3.grow(to: 2)                                  // then a birthday over a birthday
        let again = b3.age == 2
        t = 105
        b3.step()
        check(before && closed && grown && partying && again && b3.age == 2 && b3.cue == nil,
              "a newer script closes an older one's pending shape swap; a birthday's new shape comes at once, heard twice "
              + "or over another birthday")

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

    /// Arrivals, on a clock only the check moves (#130): the drip in (about 0.75 s, from about 1.9 R up, stretched
    /// 1.55 × 0.72, landing with a small bounce, the strand letting go at about 75%), the pull up (about 0.45 s, the
    /// reverse, then away), neither travelling under Reduce Motion, and small Tomo's call glow (off at 0, a 2.6 s pulse,
    /// steady under Reduce Motion).
    static func arrivalSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(reduce: Bool = false, _ material: TomoMaterial = .classic) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: .mascot, material: material)
            b.reduceMotion = reduce
            b.clock = { t }
            b.step()
            return b
        }
        func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.02) -> Bool { abs(a - b) <= e }

        // Drip in: where it starts, when it lands, the bounce, the strand thinning and letting go, and rest at the end.
        let d = blob()
        d.dripIn()
        d.step()
        let first = d.pose
        var landed: Double?, letGo: Double?, squash: CGFloat = 1, bounce: CGFloat = 1, thinning = true
        var lastNeck: CGFloat = 2
        for i in 1...60 {
            t = 100 + Double(i) / 60
            d.step()
            let p = d.pose, s = Double(i) / 60
            if landed == nil, p.dy == 0, s < 0.75 { landed = s }
            if landed != nil, s < 0.75 { squash = min(squash, p.sy); bounce = max(bounce, p.sy) }
            if let st = p.strand, st.recoil == 0 { thinning = thinning && st.neck < lastNeck; lastNeck = st.neck }
            if letGo == nil, let st = p.strand, st.recoil > 0 { letGo = s }
        }
        let rest = d.pose
        check(near(first.dy, -1.9) && near(first.sy, 1.55) && near(first.sx, 0.72) && first.strand == Strand()
              && landed.map { $0 > 0.42 && $0 < 0.5 } == true && squash < 0.9 && bounce > 1.02
              && d.cue == nil && rest.dy == 0 && rest.sx == 1 && rest.sy == 1 && rest.opacity == 1 && rest.strand == nil,
              String(format: "Tomo drips in from 1.9 R up, stretched 1.55 × 0.72, lands at %.2f s with a bounce, at rest by 0.75 s",
                     landed ?? -1))
        check(thinning && letGo.map { $0 > 0.55 && $0 < 0.6 } == true,
              String(format: "the drip's strand thins and lets go at %.0f%% of it", (letGo ?? 0) / 0.75 * 100))

        // Pulled up: the strand reaches down, Tomo goes up stretched, and is away at 0.45 s until it drips in again.
        let u = blob()
        u.pullUp()
        var top: CGFloat = 0, stretch: CGFloat = 1, reached = false, awayEarly = false
        for i in 1...27 {                                  // to 0.45 s
            t = 100 + Double(i) / 60
            u.step()
            top = min(top, u.pose.dy); stretch = max(stretch, u.pose.sy)
            reached = reached || u.pose.strand?.reach == 1
            awayEarly = awayEarly || (u.isAway && i < 27)
        }
        t = 100.46
        u.step()
        let away = u.isAway
        u.dripIn()
        let back = !u.isAway
        // Reopened mid-pull (a click on the island as it closes): it comes back instead of going away. A second pull up
        // while one plays (the shell hearing the fold twice) changes nothing.
        u.pullUp()
        t = 100.7
        u.step()
        let started = u.cue?.start
        u.pullUp()
        let once = u.cue?.start == started && u.isLeaving
        u.appear()
        t = 101.3
        u.step()
        check(top < -1.8 && stretch > 1.5 && reached && !awayEarly && away && back && once && !u.isAway && u.cue == nil,
              String(format: "Tomo is pulled up (to %.2f R, stretched %.2f tall) into the notch by 0.45 s, away until it drips in or appears",
                     top, stretch))

        // Reduce Motion: a fade and a puff, where it sits.
        func calm(_ material: TomoMaterial = .classic, _ start: (TomoBlob) -> Void)
            -> (moved: CGFloat, swell: CGFloat, squash: CGFloat, faded: [CGFloat], strand: Bool) {
            let b = blob(reduce: true, material)
            start(b)
            var r: (moved: CGFloat, swell: CGFloat, squash: CGFloat, faded: [CGFloat], strand: Bool) = (0, 0, 0, [], false)
            for i in 0...60 {
                t = 100 + Double(i) / 60
                b.step()
                let p = b.pose
                r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(b.jiggle))
                r.swell = max(r.swell, p.sx - 1, p.sy - 1)
                r.squash = max(r.squash, 1 - p.sx, 1 - p.sy)
                r.strand = r.strand || p.strand != nil
                if i % 12 == 0 { r.faded.append(b.isAway ? 0 : p.opacity) }
            }
            return r
        }
        let calms = TomoMaterial.allCases.map { m in (calm(m) { $0.dripIn() }, calm(m) { $0.pullUp() }) }
        check(calms.allSatisfy { inCalm, upCalm in
            [inCalm, upCalm].allSatisfy { $0.moved == 0 && $0.squash == 0 && $0.swell <= 0.046 && !$0.strand }
                && inCalm.faded.first == 0 && inCalm.faded.last == 1 && upCalm.faded.first == 1 && upCalm.faded.last == 0
        }, "under Reduce Motion Tomo fades in and out where it sits: no drop, no pull, no strand (classic, jelly)")

        // The call glow: nothing at 0; with it on, a pulse that repeats every 2.6 s; under Reduce Motion, steady.
        func glow(_ on: CGFloat, reduce: Bool = false) -> [CGFloat] {
            let b = blob(reduce: reduce)
            b.callGlow = on
            var seen: [CGFloat] = []
            for i in 1...(60 * 9) {
                t = 100 + Double(i) / 60
                b.step()
                if i > 60 * 4 { seen.append(b.callGlowAlpha(t)) }
            }
            return seen
        }
        let off = glow(0), on = glow(1), steady = glow(1, reduce: true)
        let period = 156                                   // 2.6 s of frames
        let repeats = (0..<(on.count - period)).allSatisfy { abs(on[$0] - on[$0 + period]) < 0.01 }
        check(off.allSatisfy { $0 == 0 } && (on.max() ?? 0) - (on.min() ?? 0) > 0.3 && repeats
              && (steady.min() ?? 0) > 0.3 && (steady.max() ?? 0) - (steady.min() ?? 0) < 0.005,
              "small Tomo's call glow: none at 0, a pulse every 2.6 s, steady under Reduce Motion")
    }

    /// The material seam (#137): a Tomo keeps the material its host gave it; the learner's own is jelly; classic keeps
    /// today's springs (the shipped frame font is rendered from it); jelly's springs overshoot further and wobble longer,
    /// and both settle back to stillness.
    static func materialSelfTest(_ check: (Bool, String) -> Void) {
        let given = TomoMaterial.allCases.allSatisfy { m in
            let b = TomoBlob(look: .mascot, material: m)
            var t = 100.0
            b.clock = { t }
            b.step(); b.grow(to: 1); b.levelUp()
            t = 104
            b.step()
            return b.material == m
        }
        check(given && TomoMaterial.own == .jelly && TomoBlob(material: .own).material == .jelly,
              "a Tomo keeps the material its host gives it, and the learner's own is jelly")
        check(TomoMaterial.classic.springs == .init(swayW: 18, swayZ: 0.18, wobbleW: 22, wobbleZ: 0.2, lift: 0.9, most: 0.12,
                                                     kick: 1),
              "classic keeps today's springs, so the widgets' frames don't change")

        // The same landing (a level-up's), then the body's wobble: how far it goes, how many of its swings show (past 1%),
        // and when it's still again.
        func wobble(_ m: TomoMaterial) -> (most: CGFloat, swings: Int, still: Double, rest: CGFloat) {
            let b = TomoBlob(look: .mascot, material: m)
            var t = 100.0
            b.clock = { t }
            b.step()
            b.levelUp()
            var most: CGFloat = 0, swings = 0, still = 0.0, last: CGFloat = 0
            for i in 1...(60 * 4) {
                t = 100 + Double(i) / 60
                b.step()
                if t > 101.25 {                        // after the landing at 0.95 s and its squish
                    most = max(most, abs(b.jiggle))
                    if abs(b.jiggle) > 0.01 && abs(last) <= 0.01 { swings += 1 }
                    if abs(b.jiggle) > 0.004 { still = t - 100 }
                }
                last = b.jiggle
            }
            return (most, swings, still, max(abs(b.jiggle), abs(b.jiggleVel) / 60))
        }
        let firm = wobble(.classic), loose = wobble(.jelly)
        check(loose.most > firm.most * 1.5 && loose.swings > firm.swings && loose.still > firm.still + 0.3
              && max(firm.rest, loose.rest) < 0.002 && loose.still < 3.2,
              String(format: "after a landing jelly wobbles further (%.3f vs %.3f), in more swings (%d vs %d) and longer (still by %.1f s vs %.1f s), then rests (%.4f)",
                     loose.most, firm.most, loose.swings, firm.swings, loose.still, firm.still, max(firm.rest, loose.rest)))
    }

    /// Jelly's hello (#137), on a clock only the check moves: hidden while its drop falls, then Tomo gathers out of it,
    /// past its size and back, lit gold, sleepy then happy, at rest by 1.8 s; under Reduce Motion a fade in with the same
    /// light and faces, and nothing moves; never over another script or while away; classic has none.
    static func helloSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(_ m: TomoMaterial = .jelly, reduce: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: .mascot, material: m)
            b.reduceMotion = reduce
            b.clock = { t }
            b.strandAnchor = CGPoint(x: 120, y: 0)
            b.step()
            return b
        }
        struct Run {
            var hiddenUntil = 0.0, dropRises = true, lastDrop: CGFloat = -1, gatherFrom = CGSize.zero
            var tallest: CGFloat = 0, widest: CGFloat = 0, moved: CGFloat = 0, shine: (CGFloat, Double) = (0, 0)
            var faces: [Face] = [], end = Pose(), over = false, firstOpacity: CGFloat = 1, lastOpacity: CGFloat = 0
        }
        func play(_ b: TomoBlob) -> Run {
            var r = Run()
            let played = b.hello()
            for i in 1...(60 * 2) {
                t = 100 + Double(i) / 60
                b.step()
                let p = b.pose, s = Double(i) / 60
                if i == 1 { r.firstOpacity = p.opacity }
                if p.opacity == 0 { r.hiddenUntil = s }
                if let d = p.drop { r.dropRises = r.dropRises && d > r.lastDrop; r.lastDrop = d }
                if r.gatherFrom == .zero, p.drop == nil, p.opacity > 0, s > 0.3 { r.gatherFrom = CGSize(width: p.sx, height: p.sy) }
                r.tallest = max(r.tallest, p.sy); r.widest = max(r.widest, p.sx)
                r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(b.jiggle), 1 - p.sx, 1 - p.sy)
                if p.shine > r.shine.0 { r.shine = (p.shine, s) }
                if [24, 54, 75].contains(i) { r.faces.append(b.shownFace) }   // at 0.4, 0.9 and 1.25 s
                if i == 108 { r.end = p; r.over = b.cue == nil; r.lastOpacity = p.opacity }   // at 1.8 s
            }
            r.over = r.over && played
            return r
        }
        let lively = play(blob())
        check(lively.firstOpacity == 0 && abs(lively.hiddenUntil - 0.45) < 0.03 && lively.dropRises && lively.lastDrop > 0.95
              && lively.gatherFrom.width > 1.7 && lively.gatherFrom.height < 0.45,
              String(format: "jelly's hello: Tomo is hidden while its drop falls from the notch (to %.2f s), then gathers from a puddle (%.2f × %.2f)",
                     lively.hiddenUntil, lively.gatherFrom.width, lively.gatherFrom.height))
        check(lively.tallest > 1.12 && lively.shine.0 > 0.9 && abs(lively.shine.1 - 0.76) < 0.05
              && lively.faces == [.sleep, .normal, .happy] && lively.over
              && lively.end.sx == 1 && lively.end.sy == 1 && lively.end.opacity == 1 && lively.end.drop == nil && lively.end.shine == 0,
              String(format: "it springs past its size (%.2f tall), lit gold (brightest at %.2f s), sleepy, then awake, then happy, at rest by 1.8 s",
                     lively.tallest, lively.shine.1))

        let calm = play(blob(reduce: true))
        check(calm.moved == 0 && calm.widest <= 1.046 && calm.lastDrop < 0 && calm.shine.0 > 0.9
              && calm.firstOpacity < 0.1 && calm.lastOpacity == 1 && calm.faces == [.happy, .happy, .happy] && calm.over,
              "under Reduce Motion the hello fades in with the same gold light and a happy face: no drop, no squash, no wobble")

        // Not over another script, not while away, and again once it's done (the Mac waking twice); classic has none.
        let b = blob()
        b.dripIn()
        let overDrip = b.hello()
        t = 101; b.step()
        b.pullUp()
        t = 101.2; b.step()
        let whileLeaving = b.hello()
        t = 102; b.step()
        let whileAway = b.isAway && !b.hello()
        b.appear()
        t = 103; b.step()
        let again = b.hello()
        t = 103.2; b.step()
        let twice = b.hello()
        b.dripIn()                                      // a visit arriving mid-hello takes over, and Tomo shows
        t = 105; b.step()
        let shown = b.pose.opacity == 1 && b.cue == nil && b.pose.drop == nil
        let classic = blob(.classic)
        check(!overDrip && !whileLeaving && whileAway && again && !twice && shown && !classic.hello() && classic.cue == nil,
              "the hello never plays over an arrival or a moment, or while Tomo is away; a visit arriving takes over; classic has none")
    }
}


extension TomoBlob {
    /// Small Tomo's badges (#137), on a clock only the check moves: a "…" bubble while it checks an answer and a Zz while
    /// it dozes or sleeps, and nothing that counts; none while a script plays or it's away; with badges on, no drifting
    /// z's; they fade in and out; under Reduce Motion they don't bob.
    static func badgeSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(badges: Bool = true, reduce: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: .mascot, material: .own)
            b.showsBadges = badges
            b.reduceMotion = reduce
            b.clock = { t }
            b.step()
            return b
        }
        func run(_ b: TomoBlob, _ seconds: Double) {
            let end = t + seconds
            while t < end - 1e-9 { t += 1.0 / 60; b.step() }
        }

        check(Badge.allCases == [.checking, .dozing], "small Tomo's badges are a \"…\" bubble and a Zz: nothing that counts")

        let b = blob()
        let awake = b.badge
        b.setState(.thinking)
        run(b, 0.1)
        let early = b.badgeShown.alpha
        run(b, 0.4)
        let checking = b.badge, shown = b.badgeShown
        b.setState(.idle)
        run(b, 0.6)
        let gone = b.badge == nil && b.badgeShown.alpha < 0.02
        b.dozeAfter = 2
        run(b, 2.6)
        let dozing = b.badge
        b.setState(.sleeping)
        run(b, 0.5)
        let asleep = b.badge
        check(awake == nil && checking == .checking && shown.badge == .checking && early > 0.2 && early < 0.95
              && shown.alpha > 0.95 && gone && dozing == .dozing && asleep == .dozing,
              String(format: "a \"…\" bubble while Tomo checks an answer, a Zz while it dozes or sleeps, none awake; each fades in (%.0f%% at 0.1 s) and out",
                     early * 100))

        // During a big moment or the hello, and while it's up in the notch, no badge.
        let m = blob()
        m.setState(.thinking)
        run(m, 0.5)
        m.levelUp()
        run(m, 0.2)
        let moment = m.badge
        run(m, 2.5)
        let after = m.badge
        m.pullUp()
        run(m, 0.6)
        check(moment == nil && after == .checking && m.isAway && m.badge == nil,
              "no badge while a big moment plays (it owns Tomo's face) or while Tomo is up in the notch; back after")

        // Badges on: no drifting z's while it dozes; off (the card, the iPhone): the z's as before.
        func zs(_ badges: Bool) -> Int {
            let z = blob(badges: badges)
            z.dozeAfter = 1
            var seen = 0
            for _ in 0..<(60 * 8) { t += 1.0 / 60; z.step(); seen = max(seen, z.bits.filter { $0.kind == .z }.count) }
            return seen
        }
        let withBadges = zs(true), without = zs(false)
        check(withBadges == 0 && without > 0, "wearing its Zz, small Tomo has no drifting z's (\(without) without badges)")

        // Reduce Motion: the bubble's dots and the Z's hold still; otherwise they hop and float.
        let still = blob(reduce: true), lively = blob()
        for x in [still, lively] { x.setState(.thinking); run(x, 0.5) }
        let times = (0..<40).map { 100 + Double($0) * 0.05 }
        let calmBob = times.flatMap { now in (0..<3).map { still.badgeBob($0, now: now) } }
        let liveBob = times.flatMap { now in (0..<3).map { lively.badgeBob($0, now: now) } }
        check(calmBob.allSatisfy { $0 == 0 } && (liveBob.max() ?? 0) > 0.15 && still.badgeShown.alpha > 0.95,
              "under Reduce Motion the badges show without bobbing")
    }
}

/// Random numbers for Tomo's particles (`TomoBlob.dice`): the system's, or the same numbers every run from a seed
/// (SplitMix64), so a check on a burst of particles never fails on a rare draw (#203).
struct TomoDice: RandomNumberGenerator {
    private var seeded: UInt64?

    /// The system's random numbers: the app's.
    init() {}
    /// The same numbers from the same seed: the checks'.
    init(seed: UInt64) { seeded = seed }

    mutating func next() -> UInt64 {
        guard var z = seeded else {
            var system = SystemRandomNumberGenerator()
            return system.next()
        }
        z &+= 0x9E37_79B9_7F4A_7C15
        seeded = z
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension TomoBlob {
    /// Big moments' particles and the season's weather (#137), on a clock only the check moves: a level-up bursts sparkle
    /// dust and a birthday tosses confetti in Tomo's own colours, each piece living 2 s at most and all gone when the
    /// moment ends; under Reduce Motion a third as many, slower; nothing emits at rest (small Tomo resting, glowing and
    /// dozing for two minutes, or in the card with its weather); the weather is a few flakes inside the canvas, worked out
    /// from the clock, fewer and slower under Reduce Motion. Each Tomo's particles are drawn from `seed`, so every run
    /// sees the same bursts: unseeded, a birthday's 26 pieces of confetti missed one of its four colours about once in
    /// 450 runs (#203).
    static func particleSelfTest(seed: UInt64 = 203, _ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(reduce: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: TomoLook(seed: "particles"), material: .own)
            b.reduceMotion = reduce
            b.dice = TomoDice(seed: seed)
            b.clock = { t }
            b.step()
            return b
        }
        struct Run { var most: [Bit.Kind: Int] = [:]; var longest = 0.0; var leftAtEnd = -1; var paces = Set<CGFloat>(); var tints = Set<Int>() }
        func moment(reduce: Bool, _ start: (TomoBlob) -> Void) -> Run {
            let b = blob(reduce: reduce)
            start(b)
            var r = Run()
            for _ in 0..<(60 * 3) {
                t += 1.0 / 60
                b.step()
                for kind in [Bit.Kind.dust, .confetti] { r.most[kind] = max(r.most[kind] ?? 0, b.bits.filter { $0.kind == kind }.count) }
                for bit in b.bits { r.longest = max(r.longest, bit.life); r.paces.insert(bit.pace); if bit.kind == .confetti { r.tints.insert(bit.tint) } }
                if r.leftAtEnd < 0, b.cue == nil { r.leftAtEnd = b.bits.count }
            }
            return r
        }
        let level = moment(reduce: false) { $0.levelUp() }, birthday = moment(reduce: false) { $0.grow(to: 1) }
        let calmLevel = moment(reduce: true) { $0.levelUp() }, calmBirthday = moment(reduce: true) { $0.grow(to: 1) }
        check((level.most[.dust] ?? 0) >= 20 && (level.most[.confetti] ?? 0) == 0 && (birthday.most[.confetti] ?? 0) >= 20
              && (birthday.most[.dust] ?? 0) == 0 && birthday.tints == [0, 1, 2, 3],
              "a level-up bursts sparkle dust (\(level.most[.dust] ?? 0)) and a birthday tosses confetti (\(birthday.most[.confetti] ?? 0)) in Tomo's own four colours")
        let b = blob()
        check([0, 1, 2, 3].map(b.confettiColor) == [b.look.body, b.look.bodyLight, b.look.accent, b.look.cheek],
              "birthday confetti is Tomo's body, its lighter top, its markings' colour and its cheeks")
        check([level, birthday, calmLevel, calmBirthday].allSatisfy { $0.longest <= Self.momentParticleLife && $0.leftAtEnd == 0 },
              String(format: "a moment's particles live %.1f s at most and are all gone when it ends (level-up 2.1 s, birthday 2.6 s)",
                     max(level.longest, birthday.longest)))
        check((calmLevel.most[.dust] ?? 0) == 9 && (calmBirthday.most[.confetti] ?? 0) == 9
              && calmLevel.paces == [Self.calmPace] && calmBirthday.paces == [Self.calmPace],
              "under Reduce Motion a moment has a third of its dust and confetti (26 → 9), slower")

        // At rest nothing emits: small Tomo resting beside the notch, glowing and dozing, for two minutes; and Tomo in the
        // card with the season's weather.
        func emitted(_ setUp: (TomoBlob) -> Void) -> Int {
            let r = blob()
            setUp(r)
            var most = 0
            for _ in 0..<(60 * 120) { t += 1.0 / 60; r.step(); most = max(most, r.bits.count) }
            return most
        }
        let resting = emitted { $0.showsBadges = true; $0.callGlow = 1 }
        let card = emitted { $0.weather = .petals; $0.dozeAfter = 1e9 }
        check(resting == 0 && card == 0, "nothing emits at rest: small Tomo resting, glowing and dozing for 2 min, or Tomo in the card with its weather")

        // The weather: a few flakes, inside the canvas below Tomo's head; a third as many and slower under Reduce Motion.
        func flakes(reduce: Bool) -> (count: Int, inside: Bool, moved: CGFloat) {
            let w = blob(reduce: reduce)
            w.weather = .snow
            for _ in 0..<60 { t += 1.0 / 60; w.step() }
            let size = CGSize(width: 120, height: 192), c = CGPoint(x: 60, y: 135), R: CGFloat = 32.4
            let a = w.weatherFlakes(size: size, center: c, R: R, now: t), z = w.weatherFlakes(size: size, center: c, R: R, now: t + 0.5)
            let inside = a.allSatisfy { $0.at.x >= 0 && $0.at.x <= size.width && $0.at.y >= c.y - R * 2.6 && $0.at.y <= size.height }
            let moved = zip(a, z).map { abs($1.at.y - $0.at.y) }.filter { $0 < size.height / 2 }.reduce(0, +) / CGFloat(a.count)
            return (a.count, inside, moved)
        }
        let lively = flakes(reduce: false), calm = flakes(reduce: true)
        check(lively.count == 7 && calm.count == 2 && lively.inside && calm.inside && calm.moved > 0
              && abs(calm.moved / lively.moved - Self.calmPace) < 0.1,
              String(format: "the weather is %d flakes inside the canvas (%d, at %.0f%% of the pace, under Reduce Motion)",
                     lively.count, calm.count, calm.moved / lively.moved * 100))
    }
}

extension TomoBlob {
    /// Dancing to music (#130), on a clock only the check moves: Tomo bounces on every beat at 112 BPM and sways, fading
    /// in over about 0.8 s and out again; the 盆踊り side-steps at half speed; under Reduce Motion it doesn't move; a big
    /// moment owns the body while it plays; while dancing Tomo doesn't doze off, fidget or emit anything.
    static func danceSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(reduce: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: .mascot, material: .own)
            b.reduceMotion = reduce
            b.clock = { t }
            b.step()
            return b
        }
        func run(_ b: TomoBlob, _ seconds: Double, _ each: (Double, Pose) -> Void = { _, _ in }) {
            let end = t + seconds
            while t < end - 1e-9 { t += 1.0 / 120; b.step(); each(t, b.pose) }
        }

        // The bounce: up on every beat, 60/112 s apart, once it has faded in.
        let b = blob()
        b.dance = .bounce
        var early: CGFloat = 0
        run(b, 0.25) { _, p in early = max(early, -p.dy) }
        run(b, 1.0)
        var tops: [Double] = [], last: (dy: CGFloat, falling: Bool) = (0, false), most: CGFloat = 0, sway: CGFloat = 0
        run(b, 6) { now, p in
            most = max(most, -p.dy); sway = max(sway, abs(p.rot))
            let rising = p.dy < last.dy
            if !rising, !last.falling, last.dy < -0.1 { tops.append(now) }
            last = (p.dy, !rising)
        }
        let gaps = zip(tops, tops.dropFirst()).map { $1 - $0 }, beat = 60.0 / 112
        let onBeat = !gaps.isEmpty && gaps.allSatisfy { abs($0 - beat) < 0.03 }
        check(onBeat && most > 0.14 && sway > 0.1 && early < most * 0.6 && b.danceShown.amount > 0.99,
              String(format: "dancing, Tomo bounces on every beat at 112 BPM (%d tops, %.3f s apart) and sways, fading in over about 0.8 s",
                     tops.count, gaps.reduce(0, +) / Double(max(gaps.count, 1))))
        let busy = b.moves.isEmpty && !b.drowsy && b.bits.isEmpty
        b.dance = nil
        run(b, 2)
        check(busy && b.danceShown.amount == 0,
              "while it dances Tomo doesn't fidget, doze or emit anything; when the music stops the dance fades out")

        // The 盆踊り: a side-step to and fro every four beats (half speed), more sideways than up.
        let o = blob()
        o.dance = .bonOdori
        run(o, 1.2)
        var side: (lo: CGFloat, hi: CGFloat) = (0, 0), up: CGFloat = 0, crossings: [Double] = [], lastDx: CGFloat = 0
        run(o, 6.5) { now, p in
            side = (min(side.lo, p.dx), max(side.hi, p.dx)); up = max(up, -p.dy)
            if lastDx < 0, p.dx >= 0 { crossings.append(now) }
            lastDx = p.dx
        }
        let period = zip(crossings, crossings.dropFirst()).map { $1 - $0 }
        check(side.hi > 0.12 && side.lo < -0.12 && up < 0.08 && !period.isEmpty && period.allSatisfy { abs($0 - 4 * beat) < 0.05 },
              String(format: "the bon odori side-steps (%.2f each way) at half speed: to and fro every %.2f s, four beats", side.hi, period.first ?? 0))

        // Under Reduce Motion: no dance at all.
        let calm = blob(reduce: true)
        calm.dance = .bounce
        var moved: CGFloat = 0
        run(calm, 3) { _, p in moved = max(moved, abs(p.dy), abs(p.dx), abs(p.rot)) }
        check(moved == 0 && calm.danceShown.amount == 0, "under Reduce Motion Tomo doesn't dance")

        // A level-up while dancing: the moment owns the body, the same as without the music.
        func levelUp(dancing: Bool) -> [CGFloat] {
            let l = blob()
            l.dance = dancing ? .bounce : nil
            run(l, 1.5)
            l.levelUp()
            var poses: [CGFloat] = []
            run(l, 2.0) { _, p in poses += [p.dx, p.dy, p.rot, p.sx, p.sy] }
            return poses
        }
        check(levelUp(dancing: true) == levelUp(dancing: false), "a level-up while Tomo dances plays as it would without the music")
    }
}

extension TomoBlob {
    /// How Tomo feels (#257), on a clock only the check moves, at every age: a feeling eases in over about a second (and
    /// shows at once on a Tomo that starts with it) and changes only how Tomo is drawn, never its age or look; droopy
    /// slumps wider without getting taller, and through a birthday's morph, looks at the floor, breathes slower and
    /// sighs every 5 to 7 s; sickly breathes quicker and shallower, shivers every few seconds and is repainted; under
    /// Reduce Motion the sigh and the shiver are a puff and it still breathes and blinks; nothing emits at rest; and
    /// back to well it gives a happy wiggle with a few sparkles.
    static func feelingSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        let look = TomoLook(seed: "feelings")
        func blob(_ f: TomoFeeling?, age: Int = 0, reduce: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: look, material: .own)
            b.reduceMotion = reduce
            b.dice = TomoDice(seed: 257)
            b.dozeAfter = 1e9
            b.clock = { t }
            b.feeling = f
            b.setGrowth(CGFloat(age))
            b.step()
            return b
        }
        struct Run {
            var moved: CGFloat = 0, swell: CGFloat = 0, squash: CGFloat = 0, dx: CGFloat = 0
            var blinks = 0, sighs = 0, shivers = 0, emitted = 0, peaks = 0, deepest: CGFloat = 0, gazeY: CGFloat = 0
        }
        func run(_ f: TomoFeeling?, age: Int = 0, reduce: Bool = false, seconds: Double = 120) -> (Run, TomoBlob) {
            let b = blob(f, age: age, reduce: reduce)
            var r = Run(), lastBlink = b.blinkAt, last = b.breath(at: CGFloat(t - b.born)), rising = false
            for _ in 0..<Int(seconds * 60) {
                t += 1.0 / 60
                b.step()
                let p = b.pose
                r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(b.jiggle))
                r.dx = max(r.dx, abs(p.dx))
                r.swell = max(r.swell, p.sx - 1, p.sy - 1)
                r.squash = max(r.squash, 1 - p.sx, 1 - p.sy)
                r.emitted = max(r.emitted, b.bits.count)
                if b.blinkAt != lastBlink { r.blinks += 1; lastBlink = b.blinkAt }
                for m in b.moves where abs(m.start - t) < 1e-9 {
                    if case .sigh = m.kind { r.sighs += 1 }
                    if case .shiver = m.kind { r.shivers += 1 }
                    if case .puff = m.kind { if f == .droopy { r.sighs += 1 } else { r.shivers += 1 } }
                }
                let breath = b.breath(at: CGFloat(t - b.born))
                if rising, breath < last { r.peaks += 1 }
                rising = breath > last
                last = breath
                r.deepest = max(r.deepest, abs(breath - 1))
                r.gazeY += b.look2.y / CGFloat(seconds * 60)      // its gaze on average
            }
            return (r, b)
        }

        // It eases in, and a Tomo that starts feeling something shows it from its first frame.
        let easing = blob(nil)
        easing.feeling = .droopy
        var sags: [CGFloat] = []
        for _ in 0..<180 { t += 1.0 / 60; easing.step(); sags.append(easing.feelingShown.sag) }
        check(sags[0] < 0.2 && abs(sags[59] - 0.85) < 0.1 && sags[179] == 0.85 && blob(.sickly).feelingShown == .init(.sickly),
              String(format: "a feeling eases in (%.0f%% of droopy's slump after 1 s, there by 3 s) and shows at once on a Tomo that starts with it",
                     sags[59] / 0.85 * 100))

        // Only how it's drawn: its age, its look and its own colours stay.
        var kept = true
        for f in TomoFeeling.allCases {
            for age in 0..<TomoLook.ages {
                let (_, b) = run(f, age: age, seconds: 6)
                if b.age != age || b.look.seed != look.seed || b.look.body != look.body || b.look.forms.count != look.forms.count {
                    kept = false
                }
            }
        }
        let ill = blob(.sickly), well = blob(nil)
        check(kept && ill.paint.body != look.body && ill.paint.seed == look.seed && well.paint.body == look.body,
              "a feeling changes only how Tomo is drawn: sickly is repainted, and its age and look stay its own at every age")

        // Droopy's outline: as tall as its own, its lower half wider, for every silhouette.
        let forms = (0..<400).lazy.map { TomoLook(seed: "slump-\($0)").form(3) }
        var shapes: [TomoForm.Silhouette: TomoForm] = [:]
        for form in forms where shapes[form.silhouette] == nil { shapes[form.silhouette] = form; if shapes.count == 10 { break } }
        let slumps = shapes.values.allSatisfy { form in
            let own = form.path(R: 100), top = -form.top * 100, bottom = form.bottom * 100
            let low = TomoFeeling.sagged(own, top: top, bottom: bottom, by: 0.85)
            let a = own.boundingRect, b = low.boundingRect
            return abs(a.minY - b.minY) < 0.5 && abs(a.maxY - b.maxY) < 0.5 && b.width > a.width * 1.02
        }
        check(shapes.count == 10 && slumps, "droopy slumps every silhouette wider at the bottom, no taller and no lower at the top")

        // Through a birthday's morph droopy slumps whatever outline is on show, and once the morph is over it slumps
        // the new form's own, kept again: even when shorter scripts play over the birthday and end before the morph
        // does (pulled up into the notch at 0.1 s, back with a quick fade at 0.55 s, all over by 0.8 s, the morph on until
        // 1.2 s, or 0.9 s for Reduce Motion's crossfade), lively and under Reduce Motion. Each frame calls `slumped` as `drawBody` would, while Tomo is drawn.
        let R: CGFloat = 100
        func box(_ path: Path) -> CGRect { path.boundingRect }
        func near(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.5 && abs(a.maxX - b.maxX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.maxY - b.maxY) < 0.5
        }
        func fresh(_ b: TomoBlob, _ f: TomoForm) -> CGRect {
            box(TomoFeeling.sagged(f.path(R: R), top: -f.top * R, bottom: f.bottom * R, by: b.feelingShown.sag))
        }
        var morphProblems: [String] = []
        for calm in [false, true] {
            let mid = blob(.droopy, age: 1, reduce: calm), what = calm ? "Reduce Motion" : "lively"
            mid.grow(to: 2)
            var pulled = false, back = false, coverFrames = 0, followed = true
            for i in 1...(60 * 2) {
                t = 100 + Double(i) / 60
                if !pulled, t >= 100.1 { pulled = true; mid.pullUp() }
                if !back, t >= 100.55 { back = true; mid.appear() }
                mid.step()
                guard !mid.isAway else { continue }
                if let frame = mid.morphFrame(t) {
                    if mid.cue == nil { coverFrames += 1 }
                    for f in [frame.old?.form, frame.form].compactMap({ $0 }) {
                        let drawn = box(mid.slumped(f, R: R, top: -f.top * R, bottom: f.bottom * R))
                        if !near(drawn, fresh(mid, f)) { followed = false }
                    }
                } else {
                    let f = mid.look.form(mid.age)
                    _ = mid.slumped(f, R: R, top: -f.top * R, bottom: f.bottom * R)
                }
            }
            let own = mid.look.form(2)
            let after = box(mid.slumped(own, R: R, top: -own.top * R, bottom: own.bottom * R))
            if coverFrames == 0 { morphProblems.append("\(what): no frame of the morph after the scripts over it ended") }
            if !followed { morphProblems.append("\(what): a frame of the morph wasn't its own outline slumped") }
            if mid.age != 2 || mid.morphFrame(t) != nil || !near(after, fresh(mid, own)) || mid.slump == nil {
                morphProblems.append("\(what): after the morph it isn't the new age's own outline slumped, kept")
            }
        }
        check(morphProblems.isEmpty,
              "droopy slumps a birthday's morph frame by frame and then the new form's own outline, kept, even when "
              + "being pulled up and coming back end before the morph does, lively and under Reduce Motion"
              + (morphProblems.isEmpty ? "" : ": " + morphProblems.joined(separator: "; ")))

        // Each one's own life: droopy looks down, breathes slower and sighs every 5 to 7 s; sickly breathes quicker and
        // shallower and shivers every few seconds. All at every age, with nothing emitted.
        let (calmWell, _) = run(nil)
        let (droopy, _) = run(.droopy), (sickly, _) = run(.sickly)
        check(droopy.gazeY < -0.4 && calmWell.gazeY > -0.2,
              String(format: "droopy looks at the floor (gaze %.2f, well %.2f)", droopy.gazeY, calmWell.gazeY))
        let slow = CGFloat(droopy.peaks) / CGFloat(calmWell.peaks), quick = CGFloat(sickly.peaks) / CGFloat(calmWell.peaks)
        check(abs(slow - 0.75) < 0.06 && abs(quick - 1.9) < 0.1 && abs(sickly.deepest / calmWell.deepest - 0.55) < 0.03,
              String(format: "droopy breathes at %.2f× the pace, sickly at %.2f× and %.0f%% as deep", slow, quick,
                     sickly.deepest / calmWell.deepest * 100))
        check((17...24).contains(droopy.sighs) && droopy.squash > 0.04 && (20...34).contains(sickly.shivers) && sickly.dx > 0.015,
              "droopy sighs every 5 to 7 s (\(droopy.sighs) in 2 min) and sickly shivers every few seconds (\(sickly.shivers))")
        var calm = true, still = true, quiet = true
        for f in TomoFeeling.allCases {
            for age in 0..<TomoLook.ages {
                let (r, _) = run(f, age: age, reduce: true, seconds: 30)
                if r.moved != 0 || r.squash != 0 || r.swell > 0.046 || r.blinks == 0 || r.peaks == 0 { calm = false }
                if f != .mossy, (f == .droopy ? r.sighs : r.shivers) == 0 { still = false }   // mossy sleeps (mossSelfTest)
                let (lively, _) = run(f, age: age, seconds: 30)
                if r.emitted > 0 || lively.emitted > 0 { quiet = false }
            }
        }
        check(calm && still, "under Reduce Motion droopy's sigh and sickly's shiver are a puff: nothing moves, and it still breathes and blinks")
        check(quiet && droopy.emitted == 0 && sickly.emitted == 0, "nothing emits while Tomo is droopy, sickly or mossy, at any age")

        // Back to well: a happy hop and wiggle, a few sparkles (a puff and the happy face under Reduce Motion).
        func recover(reduce: Bool) -> (hop: CGFloat, happy: Bool, sparkles: Int, well: Bool) {
            let b = blob(.droopy, reduce: reduce)
            for _ in 0..<60 { t += 1.0 / 60; b.step() }
            b.feeling = nil
            var hop: CGFloat = 0, happy = false, sparkles = 0
            for _ in 0..<(60 * 3) {
                t += 1.0 / 60
                b.step()
                hop = max(hop, -b.pose.dy); happy = happy || b.shownFace == .happy; sparkles = max(sparkles, b.bits.count)
            }
            return (hop, happy, sparkles, b.feelingShown == .well && b.paint.body == look.body)
        }
        let up = recover(reduce: false), calmUp = recover(reduce: true)
        check(up.hop > 0.15 && up.happy && up.sparkles == 3 && up.well && calmUp.hop == 0 && calmUp.happy && calmUp.sparkles == 1
              && calmUp.well,
              "back to well Tomo hops and wiggles happily with 3 sparkles (a puff, the happy face and 1 under Reduce Motion), in its own colours")

        #if os(macOS)   // rendered, so macOS only (ImageRenderer can time out on the iOS simulator, #196)
        let bunny = TomoLook(seed: "en-ja-1791104407")   // long ears: the snapshots' Tomo, and the lab's
        let looks = [TomoLook.mascot, look, bunny] + (0..<16).map { TomoLook(seed: "ceiling-\($0)") }
        let reach = [nil, TomoFeeling.droopy, .sickly, .mossy].map { sideReach(looks: looks, feeling: $0) }
        let room = TomoBlobView.sideRoom
        check(reach.allSatisfy { $0.reach <= room },
              String(format: "droopy's flopped ears and topper stay inside the room its canvas has at its sides (%.2f of "
                     + "its width) at every age: %.2f at most (%@; well %.2f, sickly %.2f, mossy %.2f)",
                     room, reach[1].reach, reach[1].at, reach[0].reach, reach[2].reach, reach[3].reach))
        #endif
    }
}

extension TomoBlob {
    /// Mossy (#258), on a clock only the check moves: it falls asleep curled up, and its moss creeps over its top from
    /// the crown in about 3 s; it breathes slower and deeper than well, doesn't fidget and emits nothing for two minutes,
    /// dozing off or not (its Zz are drawn from the clock, and small Tomo wears its Zz badge); and back to well it brushes
    /// the moss off (`brushCue`): gone in 0.6 s as it shakes happily in spores and sparkles that live 2 s at most and are
    /// gone when the script ends; under Reduce Motion nothing moves, and a third as many fly, slower. Then it's well, in
    /// its own colours.
    static func mossSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        let look = TomoLook(seed: "moss")
        func blob(_ f: TomoFeeling?, reduce: Bool = false, dozeAfter: Double = 1e9, of other: TomoLook? = nil, age: Int = 1,
                  ceiling: CGFloat? = nil, overhang: CGFloat = 0) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: other ?? look, material: .own)
            b.reduceMotion = reduce
            b.dice = TomoDice(seed: 258)
            b.dozeAfter = dozeAfter
            b.clock = { t }
            b.particleOverhang = overhang
            b.ceiling = ceiling
            b.setGrowth(CGFloat(age))
            b.step()
            b.feeling = f                                   // after it appears, so it eases in
            return b
        }
        func frames(_ b: TomoBlob, _ seconds: Double, _ each: (Double) -> Void = { _ in }) {
            for i in 1...Int((seconds * 60).rounded()) { t += 1.0 / 60; b.step(); each(Double(i) / 60) }
        }

        // Growing in: asleep and curled within about a second, the moss over three, patch by patch from its crown down.
        let growing = blob(.mossy)
        var moss: [CGFloat] = [], faces = Set<Face>()
        frames(growing, 5) { s in
            moss.append(growing.mossShown(growing.pose))
            if s > 1.5 { faces.insert(growing.shownFace) }
        }
        let patches = TomoFeeling.mossPatches(seed: look.markSeed)
        let crownFirst = zip(patches, patches.dropFirst()).allSatisfy { $0.y <= $1.y }
            && TomoFeeling.patchGrowth(0, amount: 0.1) > 0.5 && TomoFeeling.patchGrowth(5, amount: 0.1) == 0
        check(moss[59] > 0.4 && moss[59] < 0.7 && moss[179] > 0.85 && moss[299] > 0.97 && faces == [.sleep]
              && growing.feelingShown.curl > 0.99 && crownFirst,
              String(format: "mossy falls asleep curled up, and its moss creeps over its top from the crown down (%.0f%% "
                     + "grown after 1 s, %.0f%% after 3 s)", moss[59] * 100, moss[179] * 100))

        // At rest for two minutes: slower, deeper breaths than well, no fidget, nothing emitted, dozing off or not.
        func rest(_ f: TomoFeeling?, dozeAfter: Double = 1e9, badges: Bool = false)
            -> (peaks: Int, deepest: CGFloat, moved: CGFloat, emitted: Int, badge: Badge?) {
            let b = blob(f, dozeAfter: dozeAfter)
            b.showsBadges = badges
            frames(b, 10)                                   // eased in
            var peaks = 0, deepest: CGFloat = 0, moved: CGFloat = 0, emitted = 0
            var last = b.breath(at: CGFloat(t - b.born)), rising = false
            frames(b, 120) { _ in
                let breath = b.breath(at: CGFloat(t - b.born))
                if rising, breath < last { peaks += 1 }
                rising = breath > last
                last = breath
                deepest = max(deepest, abs(breath - 1))
                moved = max(moved, abs(b.pose.dx), abs(b.pose.dy), abs(b.pose.rot), abs(b.jiggle), CGFloat(b.moves.count))
                emitted = max(emitted, b.bits.count)
            }
            return (peaks, deepest, moved, emitted, b.badge)
        }
        let well = rest(nil), mossy = rest(.mossy), dozing = rest(.mossy, dozeAfter: 45)
        let small = rest(.mossy, dozeAfter: 45, badges: true)
        let pace = CGFloat(mossy.peaks) / CGFloat(well.peaks), depth = mossy.deepest / well.deepest
        check(abs(pace - 0.65) < 0.06 && abs(depth - 2.72) < 0.15,
              String(format: "mossy breathes at %.2f× the pace and %.1f× as deep as well", pace, depth))
        check(mossy.moved == 0 && mossy.emitted == 0 && dozing.emitted == 0 && small.emitted == 0 && small.badge == .dozing,
              "mossy doesn't fidget and emits nothing for 2 min, dozing off or not: its Zz are drawn from the clock, and "
              + "small Tomo wears its Zz badge")

        // Back to well: the brush-off.
        struct Brush {
            var gone: Double?, moved: CGFloat = 0, squash: CGFloat = 0, happy = false, spores = 0, sparkles = 0
            var longest = 0.0, leftAtEnd = -1, endedAt = 0.0, paces = Set<CGFloat>(), well = false
        }
        func brush(reduce: Bool) -> Brush {
            let b = blob(.mossy, reduce: reduce)
            frames(b, 12)                                   // grown over
            b.feeling = nil
            var r = Brush()
            frames(b, 3) { s in
                let p = b.pose
                if r.gone == nil, b.mossShown(p) < 0.01 { r.gone = s }
                r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(b.jiggle))
                r.squash = max(r.squash, 1 - p.sx, 1 - p.sy)
                r.happy = r.happy || b.shownFace == .happy
                r.spores = max(r.spores, b.bits.filter { $0.kind == .spore }.count)
                r.sparkles = max(r.sparkles, b.bits.filter { $0.kind == .sparkle }.count)
                for bit in b.bits { r.longest = max(r.longest, bit.life); r.paces.insert(bit.pace) }
                if r.leftAtEnd < 0, b.cue == nil { r.leftAtEnd = b.bits.count; r.endedAt = s }
            }
            r.well = b.feelingShown == .well && b.paint.body == look.body && b.mossShown(b.pose) == 0
            return r
        }
        let lively = brush(reduce: false), calm = brush(reduce: true)
        check([lively, calm].allSatisfy { ($0.gone ?? 9) <= 0.65 && $0.happy && $0.well },
              String(format: "back to well mossy Tomo brushes its moss off, happy (gone in %.2f s; %.2f s under Reduce "
                     + "Motion), and is well in its own colours", lively.gone ?? 9, calm.gone ?? 9))
        check(lively.moved > 0.02 && calm.moved == 0 && calm.squash == 0,
              String(format: "the brush-off shakes Tomo (%.3f); under Reduce Motion it's a puff and nothing moves", lively.moved))
        check(lively.spores == 12 && lively.sparkles == 4 && calm.spores == 4 && calm.sparkles == 1 && calm.paces == [Self.calmPace]
              && [lively, calm].allSatisfy { $0.longest <= Self.momentParticleLife && $0.leftAtEnd == 0 && abs($0.endedAt - 1.5) < 0.05 },
              "the brush-off's 12 spores and 4 sparkles (4 and 1, slower, under Reduce Motion) live 2 s at most and are gone "
              + "when it ends at 1.5 s")

        // Under a ceiling (small Tomo on a Mac without a notch, ceilingSelfTest's room) mossy is drawn smaller so its
        // sprout fits (`fit`). As the brush-off sweeps the moss away, Tomo grows back to its size a little each frame,
        // never in a jump. Under Reduce Motion, so nothing else moves: the size Tomo is drawn at in every frame of the
        // brush-off, and rendered, its drawn width the frame before it starts and in its first frames.
        let side: CGFloat = 20 / 0.6, overhang: CGFloat = 72
        let room = CGSize(width: side, height: side + overhang), ceiling = room.height / 2 + overhang / 2 - 15 + 1
        var step: CGFloat = 0, stepAt = "", widest: CGFloat = 0, widestAt = ""
        for each in [TomoLook.mascot] + (0..<8).map({ TomoLook(seed: "ceiling-\($0)") }) {
            for age in 0..<TomoLook.ages {
                let b = blob(.mossy, reduce: true, of: each, age: age, ceiling: ceiling, overhang: overhang)
                frames(b, 12)                               // grown over
                let form = each.form(age), R = side * 0.27
                let ground = room.height / 2 + overhang / 2 + R * 0.1 + form.bottom * R
                func fitted() -> CGFloat { b.fit(form: form, R: R, ground: ground, moss: b.mossShown(b.pose)) }
                var last = fitted()
                #if os(macOS)
                var width = drawnBox(size: room, scale: 4) { c, sz in b.draw(c, size: sz) }?.width
                #endif
                b.feeling = nil
                frames(b, 1.5) { s in
                    let now = fitted()
                    if abs(now - last) > step {
                        step = abs(now - last)
                        stepAt = String(format: "%@ age %d at %.2f s", each.seed, age + 1, s)
                    }
                    last = now
                    #if os(macOS)
                    if s < 0.06, let before = width,
                       let after = drawnBox(size: room, scale: 4, { c, sz in b.draw(c, size: sz) })?.width {
                        let d = abs(after - before) / before
                        if d > widest {
                            widest = d
                            widestAt = String(format: "%@ age %d at %.2f s", each.seed, age + 1, s)
                        }
                        width = after
                    }
                    #endif
                }
            }
        }
        check(step <= 0.06 && widest <= 0.08,
              String(format: "under a ceiling, brushing its moss off, Tomo grows back to its size smoothly: at most %.1f%% a "
                     + "frame (%@), and drawn, %.1f%% wider in a frame (%@)", step * 100, stepAt, widest * 100, widestAt))
    }

    /// Back into its egg and out again (#258), on a clock only the check moves: the egg closes round Tomo, asleep, in
    /// 2.4 s (under Reduce Motion it fades in round it in 0.9 s, with star eyes), and Tomo rests in it for two minutes,
    /// peeking out every 4 to 6.5 s, with no fidget, badge, hello or anything emitted, dozing off or not, and a poke
    /// wobbles it and makes it peek; a script already playing finishes first; the hatch (2.8 s; 1.6 s calm) cracks the
    /// egg and splits it in sparkles that are gone when it ends, and Tomo springs out surprised, saying its word; under
    /// Reduce Motion nothing moves and nothing flies; and Tomo comes out as it went in, for every look, age and feeling
    /// (its seed, age, form, colours and feeling). Rendered on macOS: in its egg, and as the egg cracks to hatch, only the
    /// egg shows (not its question mark either), and under a ceiling its peek stays below it.
    static func eggSelfTest(_ check: (Bool, String) -> Void) {
        var t = 100.0
        func blob(_ look: TomoLook = TomoLook(seed: "egg"), age: Int = 1, feeling: TomoFeeling? = nil, reduce: Bool = false,
                  dozeAfter: Double = 1e9, inEgg: Bool = false) -> TomoBlob {
            t = 100
            let b = TomoBlob(look: look, material: .own)
            b.reduceMotion = reduce
            b.dice = TomoDice(seed: 258)
            b.dozeAfter = dozeAfter
            b.clock = { t }
            b.feeling = feeling
            b.inEgg = inEgg
            b.hatchWord = "!"
            b.setGrowth(CGFloat(age))
            b.step()
            return b
        }
        func frames(_ b: TomoBlob, _ seconds: Double, _ each: (Double) -> Void = { _ in }) {
            for i in 1...Int((seconds * 60).rounded()) { t += 1.0 / 60; b.step(); each(Double(i) / 60) }
        }

        // There and back, lively and under Reduce Motion.
        struct Leg {
            var length = 0.0, moved: CGFloat = 0, squash: CGFloat = 0, egg: CGFloat = 0, crack: CGFloat = 0, split = false
            var sparkles = 0, longest = 0.0, leftAtEnd = -1, bubble: CGFloat = 0, faces = Set<Face>()
        }
        func leg(_ b: TomoBlob, into: Bool) -> Leg {
            b.inEgg = into
            var r = Leg()
            frames(b, 4) { s in
                let p = b.pose
                if b.cue != nil {
                    r.moved = max(r.moved, abs(p.dx), abs(p.dy), abs(p.rot), abs(b.jiggle), abs(1 - p.size))
                    r.squash = max(r.squash, 1 - p.sx, 1 - p.sy)
                    r.faces.insert(b.shownFace)
                } else if r.leftAtEnd < 0 {
                    r.length = s
                    r.leftAtEnd = b.bits.count
                }
                if let e = p.egg {
                    r.egg = max(r.egg, abs(e.rot), e.hop, abs(e.top?.dy ?? 0), abs(e.bottom?.dy ?? 0))
                    r.crack = max(r.crack, e.crack)
                    r.split = r.split || e.split != nil
                }
                r.sparkles = max(r.sparkles, b.bits.filter { $0.kind == .sparkle }.count)
                for bit in b.bits { r.longest = max(r.longest, bit.life) }
                r.bubble = max(r.bubble, p.bubble)
            }
            return r
        }
        let lb = blob(), lin = leg(lb, into: true), lout = leg(lb, into: false)
        let cb = blob(reduce: true), cin = leg(cb, into: true), cout = leg(cb, into: false)
        check(abs(lin.length - 2.4) < 0.05 && lin.egg > 0.3 && lin.moved > 0.15 && lin.faces.contains(.sleep)
              && abs(lout.length - 2.8) < 0.05 && lout.crack > 0.99 && lout.split && lout.moved > 0.3
              && lout.faces.contains(.surprised) && lout.bubble > 0.99,
              String(format: "into its egg Tomo curls up asleep and the egg closes round it (%.2f s); the hatch cracks it, "
                     + "splits it, and Tomo springs out surprised, saying its word (%.2f s)", lin.length, lout.length))
        func still(_ r: Leg) -> Bool {
            r.moved == 0 && r.squash == 0 && r.egg == 0 && r.crack == 0 && !r.split && r.faces.contains(.star)
        }
        let calmTimes = abs(cin.length - 0.9) < 0.05 && abs(cout.length - 1.6) < 0.05
        check(calmTimes && cout.bubble > 0.99 && still(cin) && still(cout),
              "under Reduce Motion the egg fades in round Tomo (0.9 s) and away (1.6 s) with star eyes and its word, and "
              + "nothing moves")
        check(lout.sparkles == 5 && lin.sparkles == 0 && cin.sparkles == 0 && cout.sparkles == 0
              && [lin, lout, cin, cout].allSatisfy { $0.longest <= Self.momentParticleLife && $0.leftAtEnd == 0 },
              "the hatch's 5 sparkles (none under Reduce Motion) live 2 s at most and are gone when it ends")

        // Resting in its egg for two minutes, dozing off or not.
        let resting = blob(dozeAfter: 45)
        resting.showsBadges = true
        resting.inEgg = true
        frames(resting, 3)
        var peeks = 0, lastPeek = resting.peekAt, busy = 0, emitted = 0, badged = false, shown = true
        frames(resting, 120) { _ in
            if resting.peekAt != lastPeek { peeks += 1; lastPeek = resting.peekAt }
            busy = max(busy, resting.moves.count)
            emitted = max(emitted, resting.bits.count)
            badged = badged || resting.badge != nil
            let (tomo, egg) = resting.eggShown(resting.pose)
            shown = shown && tomo == 0 && egg?.resting == true
        }
        let greeted = resting.hello()
        resting.peekAt = t - 5                              // it last peeked a while ago
        resting.nextPeek = t + 0.5                          // and its next peek is due before a poke's would end
        resting.poke()
        let poked = resting.eggPoke == t && resting.peekAt == t + 0.12 && resting.moves.isEmpty && resting.bits.isEmpty
        let pokedAt = resting.peekAt
        var whole = true
        frames(resting, 2) { _ in if t < pokedAt + 1.8, resting.peekAt != pokedAt { whole = false } }
        check((17...31).contains(peeks) && busy == 0 && emitted == 0 && !badged && shown && !greeted && !resting.drowsy
              && poked && whole,
              "in its egg only the egg shows: it peeks out every 4 to 6.5 s (\(peeks) in 2 min) and a poke wobbles it and "
              + "makes it peek, the whole peek, with no fidget, badge, hello or anything emitted, dozing off or not")

        // A script already playing finishes first.
        let partying = blob()
        partying.levelUp()
        partying.inEgg = true
        var waited = true
        frames(partying, 2) { _ in if partying.shell || partying.pose.egg != nil { waited = false } }
        frames(partying, 3)
        check(waited && partying.shell && partying.cue == nil,
              "a level-up already playing finishes before Tomo goes into its egg")

        // The hatch's sounds come with the hatch (`onHatch`), once, as it starts: at once from its egg; after the
        // into-egg when Hatch comes while Tomo is still going in; and never when it's back out before it went in.
        func heard(_ b: TomoBlob, _ run: (TomoBlob) -> Void) -> [Double] {
            var at: [Double] = []
            b.onHatch = { at.append(t) }
            run(b)
            frames(b, 6)
            return at
        }
        var clicked = 0.0, wentIn = 0.0
        let resting2 = heard(blob(inEgg: true)) { b in frames(b, 1); clicked = t; b.inEgg = false }
        let restingAt = resting2.first.map { $0 - clicked } ?? -1
        let goingIn = heard(blob()) { b in
            b.inEgg = true
            frames(b, 1.0 / 60)
            wentIn = t
            frames(b, 0.5)
            b.inEgg = false
        }
        let late = goingIn.first.map { $0 - wentIn } ?? -1
        let notIn = heard(blob()) { b in b.inEgg = true; b.inEgg = false }
        check(resting2.count == 1 && restingAt >= 0 && restingAt < 0.02 && goingIn.count == 1
              && abs(late - Self.intoEggCue.length) < 0.03 && notIn.isEmpty,
              String(format: "the hatch's sounds play once as the hatch starts: at once from its egg, %.2f s after it began "
                     + "going in when Hatch comes during the into-egg, and never when it's back out before it went in", late))

        // It comes out as it went in: every look, age and feeling, lively and calm.
        var changed: [String] = []
        let feelings: [TomoFeeling?] = [nil] + TomoFeeling.allCases
        let looks = [TomoLook.mascot] + (0..<3).map { TomoLook(seed: "variety-\($0)") }
        for look in looks {
            for age in [0, 2, TomoLook.ages - 1] {
                for f in feelings {
                    for reduce in [false, true] {
                        let b = blob(look, age: age, feeling: f, reduce: reduce)
                        frames(b, 0.5)
                        let before = (b.age, b.look, b.feeling, b.feelingShown, b.paint)
                        b.inEgg = true
                        frames(b, 3.5)
                        let inside = b.shell
                        b.inEgg = false
                        frames(b, 3.5)
                        let after = (b.age, b.look, b.feeling, b.feelingShown, b.paint)
                        let p = b.pose
                        if !inside || b.shell || before != after || p.tomo != 1 || p.size != 1 || p.egg != nil
                            || p.bubble != 0 || b.eggShown(p).egg != nil {
                            changed.append("\(look.seed) age \(age + 1) \(f?.rawValue ?? "well")\(reduce ? " calm" : "")")
                        }
                    }
                }
            }
        }
        check(changed.isEmpty, "Tomo comes out of its egg as it went in: its seed, age, form, colours and feeling, for "
              + "every look, age and feeling, under Reduce Motion too"
              + (changed.isEmpty ? "" : ": not \(changed.prefix(3).joined(separator: "; "))"))

        #if os(macOS)   // rendered, so macOS only (ImageRenderer can time out on the iOS simulator, #196)
        // In its egg only the egg shows, whatever Tomo's form or feeling (no ear, topper, Zz or question mark past it), and
        // still as the egg cracks to hatch; and small Tomo under the island's ceiling (ceilingSelfTest's room) peeks out
        // below it.
        let d: CGFloat = 20, side = d / 0.6, overhang: CGFloat = 72, spot: CGFloat = 15
        let room = CGSize(width: side, height: side + overhang), roomTop = room.height / 2 + overhang / 2 - spot
        let frame = CGSize(width: 100, height: 100), R = frame.width * 0.27
        var wide: [String] = [], over: [String] = []
        for look in [TomoLook.mascot] + (0..<16).map({ TomoLook(seed: "ceiling-\($0)") }) {
            for age in 0..<TomoLook.ages {
                for f in [nil, TomoFeeling.mossy] {
                    for cracking in [false, true] {
                        let b = blob(look, age: age, feeling: f, inEgg: true)
                        b.setState(.question)
                        b.nextPeek = t + 100
                        if cracking { b.inEgg = false; frames(b, 0.5) }
                        if let box = drawnBox(size: frame, { ctx, s in b.draw(ctx, size: s) }), box.width > R * 1.55 {
                            wide.append(String(format: "%@ age %d%@: %.0f pt", look.seed, age + 1, cracking ? " cracking" : "",
                                               box.width))
                        }
                    }
                }
                let b = blob(look, age: age, inEgg: true)
                b.particleOverhang = overhang
                b.ceiling = roomTop + 1
                for peek in [-10.0, 0.85] {                 // at rest, and at the top of a peek
                    b.peekAt = peek < 0 ? peek : t - peek
                    b.nextPeek = t + 100
                    if let y = drawnTop(size: room, { ctx, s in b.draw(ctx, size: s) }), y < roomTop - 0.5 {
                        over.append(String(format: "%@ age %d %@: %.1f pt over", look.seed, age + 1,
                                           peek < 0 ? "at rest" : "peeking", roomTop - y))
                    }
                }
            }
        }
        check(wide.isEmpty && over.isEmpty,
              String(format: "in its egg, and as it cracks to hatch, only the egg shows (no wider than %.0f pt in a %.0f pt "
                     + "frame, asking or not), and under a ceiling it rests and peeks below it", R * 1.55, frame.width)
              + (wide.isEmpty ? "" : ": \(wide.prefix(3).joined(separator: "; "))")
              + (over.isEmpty ? "" : ": \(over.prefix(3).joined(separator: "; "))"))

        // Going in and hatching, in every frame of both scripts, the egg's halves stay in Tomo's room on each host: on
        // the iPhone's canvas (120 pt, no room above it), under the header on the card (its bottom is 48 pt down Tomo's
        // canvas), and under the ceiling for small Tomo on a Mac without a notch. Drawn in a canvas with room above it,
        // so what reaches past the top is seen.
        struct Host { var name: String; var size: CGSize; var overhang: CGFloat; var ceiling: CGFloat?; var top: CGFloat }
        let hosts = [Host(name: "iPhone", size: CGSize(width: 120, height: 120), overhang: 0, ceiling: nil, top: 0),
                     Host(name: "card", size: CGSize(width: 120, height: 192), overhang: 72, ceiling: nil, top: 48),
                     Host(name: "small Tomo", size: room, overhang: overhang, ceiling: roomTop + 1, top: roomTop)]
        var out: [String] = [], highest: [String: CGFloat] = [:], drawn = 0, faded = 0, fadedHigh: [String] = []
        for host in hosts {
            let pad: CGFloat = 60
            for age in 0..<TomoLook.ages {
                let b = blob(.mascot, age: age)
                b.particleOverhang = host.overhang
                b.ceiling = host.ceiling
                for into in [true, false] {
                    b.inEgg = into
                    frames(b, into ? 2.5 : 2.9) { s in
                        guard let egg = b.eggShown(b.pose).egg else { return }
                        let size = host.size, born = b.born, now = t
                        let box = drawnBox(size: CGSize(width: size.width, height: size.height + pad), scale: 1) { ctx, _ in
                            var c = ctx
                            c.translateBy(x: 0, y: pad)
                            let at = b.eggRoom(size: size)
                            b.drawEgg(c, egg, floor: at.floor, top: at.top, R: size.width * 0.27, now: now, t: CGFloat(now - born))
                        }
                        guard let y = box.map({ $0.minY - pad }) else { return }
                        drawn += 1
                        highest[host.name] = min(highest[host.name] ?? .infinity, y)
                        // Half-faded, the shell is low: everything drawn is below where the egg's middle stood.
                        if let k = egg.split, TomoEgg.splitSolid(k) < 0.98, TomoEgg.splitSolid(k) > 0.02 {
                            faded += 1
                            let at = b.eggRoom(size: size), R = size.width * 0.27
                            let w = b.ceiling.map { min(R * 1.45, max(1, at.floor.y - $0) / (1.28 * 1.1)) } ?? R * 1.45
                            if y < at.floor.y - w * 1.28 / 2 {
                                fadedHigh.append(String(format: "%@ age %d at %.2f s: %.0f pt high", host.name, age + 1, s,
                                                        at.floor.y - w * 0.64 - y))
                            }
                        }
                        if y < host.top - 0.5 {
                            out.append(String(format: "%@ age %d %@ at %.2f s: %.1f pt over", host.name, age + 1,
                                              into ? "going in" : "hatching", s, host.top - y))
                        }
                    }
                }
            }
        }
        check(out.isEmpty && drawn > 1000,
              "going into its egg and hatching, the egg's halves stay in Tomo's room in every frame: on the iPhone's canvas "
              + "(highest \(highest["iPhone"].map { String(format: "%.0f", $0) } ?? "-") pt), under the card's header "
              + "(\(highest["card"].map { String(format: "%.0f", $0) } ?? "-") pt, below 48) and under small Tomo's ceiling"
              + (out.isEmpty ? "" : ": \(out.count) over, \(out.prefix(3).joined(separator: "; "))"))
        // As it hatches, the shell's halves stay solid until their last 0.1 s, and are low by then (in the egg's lower
        // half, beside and under Tomo's foot), so half-faded cream never hangs round Tomo as a grey smudge.
        let fadedEach = Double(faded) / Double(hosts.count * TomoLook.ages) / 60
        check(faded > 0 && fadedEach <= 0.12 && fadedHigh.isEmpty,
              String(format: "hatching, the shell's halves fade only in their last %.2f s (at most 0.12), low beside Tomo's "
                     + "foot", fadedEach)
              + (fadedHigh.isEmpty ? "" : ": \(fadedHigh.count) high, \(fadedHigh.prefix(3).joined(separator: "; "))"))
        #endif
    }
}

extension TomoBlob {
    #if os(macOS)
    // Rendered checks of the ceiling, macOS only: only the Mac island sets one (its small Tomo), and on the iOS
    // simulator ImageRenderer can time out, turning a 3 s test into minutes (#196).

    /// The highest point anything is drawn at in a canvas of `size` (points, y down), from a render at `scale`; nil when
    /// nothing is drawn.
    public static func drawnTop(size: CGSize, scale: CGFloat = 2, _ draw: @escaping (GraphicsContext, CGSize) -> Void) -> CGFloat? {
        drawnBox(size: size, scale: scale, draw)?.minY
    }

    /// The box everything drawn in a canvas of `size` fits in (points, y down), from a render at `scale`; nil when
    /// nothing is drawn.
    static func drawnBox(size: CGSize, scale: CGFloat = 2, _ draw: @escaping (GraphicsContext, CGSize) -> Void) -> CGRect? {
        let renderer = ImageRenderer(content: Canvas { ctx, s in draw(ctx, s) }.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var left = w, right = -1, top = h, bottom = -1
        for row in 0..<h {
            for col in 0..<w where px[(row * w + col) * 4 + 3] > 24 {
                left = min(left, col); right = max(right, col); top = min(top, row); bottom = max(bottom, row)
            }
        }
        guard right >= 0 else { return nil }
        return CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                      width: CGFloat(right + 1 - left) / scale, height: CGFloat(bottom + 1 - top) / scale)
    }

    /// How far past its frame's sides Tomo draws at rest, in units of the frame's width, for each look at every age,
    /// feeling `feeling`: the most, and where (rendered in a canvas a frame wider on each side).
    static func sideReach(looks: [TomoLook], feeling: TomoFeeling?, width: CGFloat = 60) -> (reach: CGFloat, at: String) {
        var most: (reach: CGFloat, at: String) = (0, "")
        for look in looks {
            for age in 0..<TomoLook.ages {
                let t = 100.0, b = TomoBlob(look: look, material: .own)
                b.clock = { t }
                b.feeling = feeling
                b.setGrowth(CGFloat(age))
                b.step()
                let frame = CGSize(width: width, height: width)
                guard let box = drawnBox(size: CGSize(width: width * 3, height: width), { ctx, _ in
                    var ctx = ctx
                    ctx.translateBy(x: width, y: 0)
                    b.draw(ctx, size: frame)
                }) else { continue }
                let reach = max(width - box.minX, box.maxX - 2 * width, 0) / width
                if reach > most.reach { most = (reach, "\(look.seed) age \(age + 1)") }
            }
        }
        return most
    }

    /// Small Tomo standing in a canvas of `size` (`overhang` of it above Tomo, as its hosts give it) under `ceiling`, for
    /// each look at every age: what it draws above `top` (canvas points) at rest, at the top of its idle stretch, and at
    /// the top of a hop as it wakes, and through a birthday's morph into that age (its overshoot, wobble and stretch;
    /// the body and topper only, as its drops and confetti may fly into the room above), from renders, feeling
    /// `feeling`. Empty when nothing reaches past `top`.
    public static func pokesAbove(_ top: CGFloat, ceiling: CGFloat?, size: CGSize, overhang: CGFloat,
                                  looks: [TomoLook], feeling: TomoFeeling? = nil) -> [String] {
        var t = 100.0, out: [String] = []
        for look in looks {
            for age in 1..<TomoLook.ages {
                t = 100
                let b = TomoBlob(look: look, material: .own)
                b.clock = { t }
                b.particleOverhang = overhang
                b.ceiling = ceiling
                b.feeling = feeling
                b.setGrowth(CGFloat(age - 1))
                b.step()
                b.grow(to: CGFloat(age))
                var most: (over: CGFloat, at: Double) = (0, 0)
                for i in 1...23 {                           // every 0.05 s of the 1.2 s morph
                    t = 100 + Double(i) * 0.05
                    b.step()
                    b.bits.removeAll()
                    if let y = drawnTop(size: size, { ctx, s in b.draw(ctx, size: s) }), top - y > max(0.5, most.over) {
                        most = (top - y, t - 100)
                    }
                }
                if most.over > 0 {
                    out.append(String(format: "%@ age %d a birthday's morph at %.2f s: %.1f pt over", look.seed, age,
                                      most.at, most.over))
                }
            }
            for age in 0..<TomoLook.ages {
                for (pose, move, peak) in [("at rest", nil, 0.0), ("stretched", Move.Kind.stretch, 0.45),
                                           ("hopping", .hop(TomoBlob.idleLift), 0.2)] as [(String, Move.Kind?, Double)] {
                    t = 100
                    let b = TomoBlob(look: look, material: .own)
                    b.clock = { t }
                    b.particleOverhang = overhang
                    b.ceiling = ceiling
                    b.feeling = feeling
                    b.setGrowth(CGFloat(age))
                    b.step()
                    if let move { b.add(move, peak * 2) }
                    t += peak
                    b.step()
                    if let y = drawnTop(size: size, { ctx, s in b.draw(ctx, size: s) }), y < top - 0.5 {
                        out.append(String(format: "%@ age %d %@: %.1f pt over", look.seed, age, pose, top - y))
                    }
                }
            }
        }
        return out
    }
    #endif

    /// Under a ceiling (#196): small Tomo, in a room 30 pt tall that it stands in the middle of (the island without a
    /// notch), with the ceiling 1 pt inside the room's top, draws nothing above the room at any age, at rest, stretched or
    /// hopping, while without the ceiling the tallest forms do (rendered, macOS only: the island is the Mac's); a Tomo
    /// that fits is drawn at its own size, and none is drawn under half of it. The render finds a drawn line where it is.
    static func ceilingSelfTest(_ check: (Bool, String) -> Void) {
        let d: CGFloat = 20, side = d / 0.6, overhang: CGFloat = 72, spot: CGFloat = 15
        let size = CGSize(width: side, height: side + overhang)
        let roomTop = size.height / 2 + overhang / 2 - spot     // the canvas is centred overhang / 2 above Tomo's spot
        let looks = [TomoLook.mascot] + (0..<16).map { TomoLook(seed: "ceiling-\($0)") }
        #if os(macOS)
        let bar = drawnTop(size: CGSize(width: 20, height: 40)) { ctx, _ in
            ctx.fill(Path(CGRect(x: 2, y: 13, width: 10, height: 4)), with: .color(.white))
        }
        check(bar == 13, "a render finds the highest thing drawn in it (a bar 13 pt down: \(bar.map { "\($0)" } ?? "none"))")

        let under = pokesAbove(roomTop, ceiling: roomTop + 1, size: size, overhang: overhang, looks: looks)
        let without = pokesAbove(roomTop, ceiling: nil, size: size, overhang: overhang, looks: looks)
        check(under.isEmpty && !without.isEmpty,
              "under a ceiling small Tomo draws nothing above the room at any age, at rest, stretched, hopping or "
              + "through a birthday's morph"
              + (under.isEmpty ? " (\(without.count) of \(looks.count * (TomoLook.ages * 4 - 1)) would without it)"
                 : ": \(under.prefix(3).joined(separator: "; "))"))
        let feeling = TomoFeeling.allCases.flatMap { f in
            pokesAbove(roomTop, ceiling: roomTop + 1, size: size, overhang: overhang, looks: looks, feeling: f)
                .map { "\(f.rawValue) \($0)" }
        }
        check(feeling.isEmpty, "droopy, sickly or mossy, small Tomo still draws nothing above the room under a ceiling"
              + (feeling.isEmpty ? "" : ": \(feeling.prefix(3).joined(separator: "; "))"))
        #endif
        var fits: [CGFloat] = []
        for look in looks {
            for age in 0..<TomoLook.ages {
                let b = TomoBlob(look: look, material: .own)
                b.particleOverhang = overhang
                b.ceiling = roomTop + 1
                b.setGrowth(CGFloat(age))
                let form = look.form(age), R = side * 0.27
                fits.append(b.fit(form: form, R: R, ground: size.height / 2 + overhang / 2 + R * 0.1 + form.bottom * R, moss: 0))
            }
        }
        let same = fits.filter { $0 == 1 }.count, least = fits.min() ?? 0
        check(same > 0 && least >= 0.5 && TomoBlob(look: .mascot, material: .own).fit(form: TomoLook.mascot.form(0), R: 9,
                                                                                       ground: 100, moss: 0) == 1,
              String(format: "only a form too tall for the room is drawn smaller (%d of %d at their size, the smallest at %.0f%%); no ceiling, no change",
                     same, fits.count, least * 100))
    }
}

// MARK: - Views

/// Tomo on its own: a Canvas redrawn every frame. Shells that know where the pointer is set `gaze`.
/// `look`: nil for the learner's own Tomo; `material`: what it's made of (`TomoMaterial.own` for the learner's own).
/// `hello`: it says hello when it first appears (the iPhone's play screen, as the app starts). `feeling`: how it feels
/// (`TomoBlob.feeling`); `inEgg`: back in its egg, `hatchWord` what it says as it hatches (`TomoBlob.inEgg`), and
/// `onHatch` what the host does as the hatch starts (its sounds, `TomoGame.hatchSounds`). It follows Reduce Motion
/// (`TomoMotion`).
public struct TomoBlobView: View {
    /// The room its canvas has beyond its frame on each side, as a share of the frame's width, so a droopy Tomo's flopped
    /// ears aren't cut off by the canvas's edge (as the Mac island's `canvasRoom`). Tomo is still drawn at the frame's
    /// size and place; `TomoBlob.feelingSelfTest` checks nothing reaches further at rest. Taps land on the frame alone,
    /// whatever the host does.
    public static let sideRoom: CGFloat = 0.2

    @StateObject private var blob: TomoBlob
    @State private var greeted = false
    public var state: BotState
    public var growth: CGFloat
    public var hello: Bool
    public var feeling: TomoFeeling?
    public var inEgg: Bool
    public var hatchWord: String?
    public var onHatch: (@MainActor () -> Void)?
    public var gaze: (() -> CGPoint)?

    public init(state: BotState = .idle, growth: CGFloat, look: TomoLook? = nil, material: TomoMaterial,
                hello: Bool = false, feeling: TomoFeeling? = nil, inEgg: Bool = false, hatchWord: String? = nil,
                onHatch: (@MainActor () -> Void)? = nil, gaze: (() -> CGPoint)? = nil) {
        _blob = StateObject(wrappedValue: TomoBlob(look: look, material: material, motion: .shared))
        self.state = state
        self.growth = growth
        self.hello = hello
        self.feeling = feeling
        self.inEgg = inEgg
        self.hatchWord = hatchWord
        self.onHatch = onHatch
        self.gaze = gaze
    }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                // The frame's size from the canvas's own, not the reader's, so Tomo stays in its middle while a host
                // animates its frame (the reader reports the final size at once).
                Canvas { context, size in
                    let frame = CGSize(width: size.width / (1 + 2 * Self.sideRoom), height: size.height)
                    var context = context
                    context.translateBy(x: frame.width * Self.sideRoom, y: 0)
                    blob.frameDate = timeline.date
                    blob.feeling = feeling
                    blob.inEgg = inEgg
                    blob.hatchWord = hatchWord
                    if let g = gaze?() { blob.lookX = g.x; blob.lookY = g.y }
                    blob.step()
                    blob.draw(context, size: frame)
                }
                .frame(width: geo.size.width * (1 + 2 * Self.sideRoom), height: geo.size.height)
                .offset(x: -geo.size.width * Self.sideRoom)
                .allowsHitTesting(false)                    // its side room takes no taps: only the frame does
            }
        }
        .contentShape(Rectangle())
        .onChange(of: state) { _, s in blob.setState(s) }
        .onChange(of: growth) { _, g in blob.grow(to: g) }
        .onAppear {
            blob.setState(state, force: true)
            blob.setGrowth(growth)
            blob.onHatch = afterTheFrame(onHatch)
            if hello, !greeted { greeted = true; blob.hello() }
        }
        .tomoReactions(blob)
    }

    /// `run`, after the frame that calls it is drawn rather than in it (`TomoBlob.onHatch` is called from `step`).
    private func afterTheFrame(_ run: (@MainActor () -> Void)?) -> (@MainActor () -> Void)? {
        guard let run else { return nil }
        return { DispatchQueue.main.async { MainActor.assumeIsolated { run() } } }
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
/// their content changes (decisions-2026-10-06.md). Drawn by the same TomoBlob, half a second into
/// `state` (and `emote`), so it's never caught mid-blink and a win still has its sparkles. These places
/// show the mascot, in the classic material like the frame font beside it, unless given a look and a material.
public struct TomoBlobStill: View {
    var state: BotState
    var emote: BotEmote?
    var growth: CGFloat
    var look: TomoLook
    var material: TomoMaterial

    public init(state: BotState = .idle, emote: BotEmote? = nil, growth: CGFloat, look: TomoLook = .mascot,
                material: TomoMaterial = .classic) {
        self.state = state
        self.emote = emote
        self.growth = growth
        self.look = look
        self.material = material
    }

    public var body: some View {
        Canvas { context, size in
            let blob = TomoBlob(look: look, material: material)
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
