import SwiftUI
import TomoCore

// MARK: - The coloured light that tells the moment (#137, effect 3)
//
// TomoCore says which moment it is (`TomoMoment`); here it's drawn on the notch: in Tomo's card (CardBackground), in
// the island around the card, the peek's bar and small Tomo (`TomoIslandLight`), and in the halo behind Tomo in the
// card (`TomoMomentHalo`). Every one is lit from Tomo, so the light seems to come from it, and a moment that just
// happened ripples out from Tomo across the card and the island together (the Jelly direction's ripple, in our own
// drawing). Between moments nothing moves: a lit resting island is a still gradient, with no clock.

/// The moment's light on one surface: a soft glow pooled at Tomo that fades in as the moment starts and out as it ends,
/// and, for a moment that just happened (`TomoMoment.ripples`), a ring of it travelling out from Tomo (1.1 s). Under
/// Reduce Motion the light and its colour stay, the ring goes, and the fades are very short. The surface clips it.
struct TomoMomentLight: View {
    static let rippleDuration: Double = 1.1

    /// How long the light takes to come (`on`) or to go: quick in, slower out; under Reduce Motion, very short.
    static func fade(on: Bool, reduceMotion: Bool) -> Double {
        reduceMotion ? (on ? 0.1 : 0.15) : (on ? 0.25 : 0.8)
    }

    /// Whether a change to `new` starts a ring from Tomo: a moment that just happened, not under Reduce Motion.
    static func ripples(from old: TomoMoment?, to new: TomoMoment?, reduceMotion: Bool) -> Bool {
        guard let new, new.ripples, !reduceMotion else { return false }
        return new != old
    }

    let moment: TomoMoment?
    /// Where Tomo is, in this view's coordinates.
    let center: CGPoint
    /// How far the glow spreads from Tomo, and how much flatter than round it is (the card and the island are wide).
    let reach: CGFloat
    var squash: CGFloat = 1
    /// How far the ring travels: past the surface's far corner.
    var rippleReach: CGFloat = 640
    /// This surface's brightness, times the moment's own (`TomoMoment.strength`).
    var strength: Double = 1
    @ObservedObject var motion = TomoMotion.shared

    /// The moment the light shows, following `moment` with a fade.
    @State private var shown: TomoMoment?
    @State private var ripple = 0
    @State private var rippleColor = Color.clear

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(TomoMoment.allCases, id: \.self) { m in
                glow(m.color).opacity(m == shown ? m.strength * strength : 0)
            }
            ring
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear { shown = moment }
        .onChange(of: moment) { old, new in
            withAnimation(.easeInOut(duration: Self.fade(on: new != nil, reduceMotion: motion.reduce))) { shown = new }
            guard Self.ripples(from: old, to: new, reduceMotion: motion.reduce), let new else { return }
            rippleColor = new.color
            ripple += 1
        }
    }

    /// The light pooled at Tomo: brightest behind it, gone by `reach`.
    private func glow(_ color: Color) -> some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: color.opacity(0.5), location: 0),
                                         .init(color: color.opacity(0.24), location: 0.26),
                                         .init(color: color.opacity(0.08), location: 0.6),
                                         .init(color: color.opacity(0), location: 1)],
                                 center: .center, startRadius: 0, endRadius: reach))
            .frame(width: reach * 2, height: reach * 2)
            .scaleEffect(x: 1, y: 1 / squash)
            .position(center)
    }

    /// The ring: thin and bright as it leaves Tomo, wider and fading as it crosses the surface. Still and invisible
    /// until a moment starts it (`ripple`), so no clock runs between moments.
    private var ring: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: rippleColor.opacity(0), location: 0),
                                         .init(color: rippleColor.opacity(0), location: 0.62),
                                         .init(color: rippleColor.opacity(0.5 * strength), location: 0.86),
                                         .init(color: rippleColor.opacity(0), location: 1)],
                                 center: .center, startRadius: 0, endRadius: rippleReach))
            .frame(width: rippleReach * 2, height: rippleReach * 2)
            .keyframeAnimator(initialValue: 1.0, trigger: ripple) { ring, p in
                ring.scaleEffect(0.05 + 0.95 * p).opacity(min(1, (1 - p) * 1.8))
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: Self.rippleDuration, timingCurve: .easeOut)
            }
            .position(center)
    }
}

/// The island's own light, around the card, the peek's bar or small Tomo: the card's moment while the card is open
/// (so it spills past the card's edges), and amber while Tomo peeks, or rests small while something counts. It reads
/// the game it's given once each change has landed (`onGameSettled`), so the island doesn't redraw on every change to
/// the game; the island says where Tomo is.
struct TomoIslandLight: View {
    let game: TomoGame
    let mode: IslandMode
    let view: IslandView
    /// Tomo, in the island's coordinates (BotPlacement's `botPosition`).
    let tomo: CGPoint
    @State private var card: TomoMoment?
    @State private var counts = false

    /// Which moment the island shows: the card's while it's open, waiting while it peeks (a visit offered), the resting
    /// light while Tomo is small (`TomoMoment.resting`), and none while hidden or on the dizzy card.
    static func moment(mode: IslandMode, view: IslandView, card: TomoMoment?, somethingCounts: Bool) -> TomoMoment? {
        switch mode {
        case .hidden: return nil
        case .compact: return TomoMoment.resting(somethingCounts: somethingCounts)
        case .peek: return .waiting
        case .expanded: return view == .overview ? card : nil
        }
    }

    /// How far and how brightly it lights: across the open island around the card, along the peek's bar, and a small
    /// pool around small Tomo in the resting island.
    static func reach(_ mode: IslandMode) -> (reach: CGFloat, squash: CGFloat, strength: Double) {
        switch mode {
        case .hidden, .compact: return (120, 2.6, 1)
        case .peek: return (300, 1.9, 1)
        case .expanded: return (360, 1.6, 0.7)
        }
    }

    var body: some View {
        let r = Self.reach(mode)
        TomoMomentLight(moment: Self.moment(mode: mode, view: view, card: card, somethingCounts: counts),
                        center: tomo, reach: r.reach, squash: r.squash, strength: r.strength)
            .animation(.spring(response: 0.5, dampingFraction: 0.72), value: tomo)
            .animation(.spring(response: 0.5, dampingFraction: 0.72), value: mode)
            .onGameSettled(game) {
                card = TomoMoment.card(phase: game.phase, outcome: game.outcome, chat: game.isChat)
                counts = game.somethingCounts
            }
    }
}

/// The halo behind Tomo in the card, in the moment's colour (white between moments). Coucou's coloured glows per
/// agent state, a red one among them, are gone: the moment says what the colour means.
struct TomoMomentHalo: View {
    let game: TomoGame
    @ObservedObject var motion = TomoMotion.shared
    let diameter: CGFloat
    let opacity: Double
    @State private var moment: TomoMoment?

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: moment?.color ?? .white, location: 0),
                                         .init(color: .clear, location: 0.62)],
                                 center: .center, startRadius: 0, endRadius: diameter * 1.1))
            .frame(width: diameter * 2.2, height: diameter * 2.2)
            .blur(radius: 6)
            .opacity(opacity)
            .animation(.easeInOut(duration: TomoMomentLight.fade(on: moment != nil, reduceMotion: motion.reduce)),
                       value: moment)
            .onGameSettled(game) {
                moment = TomoMoment.card(phase: game.phase, outcome: game.outcome, chat: game.isChat)
            }
    }
}
