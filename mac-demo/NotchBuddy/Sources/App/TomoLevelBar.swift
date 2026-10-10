import SwiftUI
import TomoCore

// MARK: - The level bar comes alive (#137, effect 7)
//
// The card's experience bar (TomoGrowthBar) with its moments. A counted answer that moves the bar sends a +1 flying
// from the result into the bar (`TomoPlusOne`); as it lands, the fill moves, glows, sheens and bounces once. At a
// birthday the bar fills with Tomo's own colour. Under Reduce Motion nothing flies, sheens or bounces: the fill moves
// at once with a brief glow, and a birthday's colour fades in. Between moments nothing moves, and no clock runs.

/// When things happen and what a change to the bar does. Pure, so the self-test checks it.
enum TomoBarMotion {
    /// The +1 leaves the result this long after the result shows (it pops in first), and flies for `flight`.
    static let delay: TimeInterval = 0.25
    static let flight: TimeInterval = 0.6
    /// When the +1 lands and the bar moves, after the answer.
    static var lands: TimeInterval { delay + flight }
    /// How long the fill glows after a landing; under Reduce Motion, a brief glow.
    static func glow(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0.6 : 1.2 }
    static let sheen: TimeInterval = 0.6
    static let bounce: TimeInterval = 0.4
    /// How long Tomo's colour takes to fill the bar at a birthday; under Reduce Motion it fades in this fast.
    static func birthdayFill(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0.15 : 0.9 }

    enum Move: Equatable {
        /// A +1 flies from the result, and the bar moves when it lands, with a glow, a sheen and a bounce.
        case fly
        /// The bar moves at once, with a brief glow (a counted answer under Reduce Motion).
        case glow
        /// The bar just moves: anything but a counted answer (a level done and emptied, a sync, practice never moves it).
        case plain
    }

    /// What a change to the bar from `old` to `new` does: a counted answer that moves it up sends a +1.
    static func move(from old: Double, to new: Double, counted: Bool, reduceMotion: Bool) -> Move {
        guard counted, new > old else { return .plain }
        return reduceMotion ? .glow : .fly
    }
}

/// A +1 on its way from the result into the bar, in TomoView's coordinates (`TomoView.space`, origin at the bar's
/// row): it rises out of the result and curves down into where the fill will end.
struct TomoPlusOne: Equatable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint

    /// The curve's pull: past the start, above the bar, so the +1 comes down into the fill from above.
    var control: CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * 0.35, y: min(from.y, to.y) - 26)
    }

    /// Where it is `t` seconds into its flight, eased: at the result at 0, in the bar at `TomoBarMotion.flight`.
    func point(at t: TimeInterval) -> CGPoint {
        let u = Self.ease(t / TomoBarMotion.flight), c = control
        let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, d = u * u
        return CGPoint(x: a * from.x + b * c.x + d * to.x, y: a * from.y + b * c.y + d * to.y)
    }

    /// It shrinks as it goes, and melts into the bar over the last fifth.
    func scale(at t: TimeInterval) -> CGFloat { 1 - 0.45 * CGFloat(Self.ease(t / TomoBarMotion.flight)) }
    func opacity(at t: TimeInterval) -> Double {
        let u = min(max(t / TomoBarMotion.flight, 0), 1)
        return u < 0.8 ? 1 : (1 - u) / 0.2
    }

    static func ease(_ x: Double) -> Double {
        let u = min(max(x, 0), 1)
        return u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
    }
}

/// Draws a `TomoPlusOne` every frame from when it first shows, while it flies (TomoView removes it as it lands).
struct TomoPlusOneView: View {
    let flight: TomoPlusOne
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = start.map { timeline.date.timeIntervalSince($0) } ?? 0
            Text(verbatim: "+1")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(TomoMoment.win.color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(TomoMoment.win.color.opacity(0.22)))
                .fixedSize()
                .scaleEffect(flight.scale(at: t))
                .opacity(flight.opacity(at: t))
                .position(flight.point(at: t))
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

/// The card's level bar: TomoGrowthBar showing what it's given, with a landing's glow, sheen and bounce (`hits`), and a
/// birthday's fill in Tomo's colour (`tomo`, from the card's host). Still between moments.
struct TomoLevelBar: View {
    static let colors = [Color(hex: "#FFD3BD"), Color(hex: "#7BD389")]

    let progress: Double
    let standing: Double
    let dimmed: Bool
    /// Counts the +1s that landed: each glows (and, without Reduce Motion, sheens and bounces) once.
    let hits: Int
    /// A birthday is on (TomoPhase.grew): the bar fills with Tomo's colour until it's over.
    let birthday: Bool
    let tomo: Color
    @ObservedObject var motion = TomoMotion.shared

    @State private var birthdayFill: CGFloat = 0
    @State private var birthdayShown = 0.0
    @State private var birthdaySheens = 0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let filled = max(TomoGrowthBar.filledWidth(w, progress: progress), h)
            ZStack(alignment: .leading) {
                // The glow, behind the bar: the fill's own colour, blurred, fading after a landing.
                Capsule().fill(Self.colors[1]).frame(width: filled, height: h)
                    .blur(radius: 3.5)
                    .keyframeAnimator(initialValue: 0.0, trigger: hits) { glow, a in glow.opacity(a) } keyframes: { _ in
                        MoveKeyframe(1.0)
                        LinearKeyframe(0.0, duration: TomoBarMotion.glow(reduceMotion: motion.reduce), timingCurve: .easeOut)
                    }
                TomoGrowthBar(progress: progress, standing: standing, dimmed: dimmed, colors: Self.colors)
                sheen(width: filled, height: h, trigger: hits)
                // A birthday: Tomo's colour fills the bar from the left, glowing, until the birthday is over.
                Capsule().fill(tomo)
                    .frame(width: w * birthdayFill, height: h)
                    .shadow(color: tomo.opacity(0.8), radius: 4)
                    .opacity(birthdayShown)
                sheen(width: w * birthdayFill, height: h, trigger: birthdaySheens)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: hits) { bar, s in
                bar.scaleEffect(x: 1, y: motion.reduce ? 1 : 1 + 0.9 * s, anchor: .center)
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: TomoBarMotion.bounce * 0.25, timingCurve: .easeOut)
                SpringKeyframe(0.0, duration: TomoBarMotion.bounce * 0.75, spring: .init(response: 0.3, dampingRatio: 0.45))
            }
        }
        .onAppear { if birthday { birthdayFill = 1; birthdayShown = 1 } }
        .onChange(of: birthday) { _, on in
            if on {
                if motion.reduce {
                    birthdayFill = 1
                    withAnimation(.easeOut(duration: TomoBarMotion.birthdayFill(reduceMotion: true))) { birthdayShown = 1 }
                } else {
                    birthdayFill = 0
                    birthdayShown = 1
                    withAnimation(.easeOut(duration: TomoBarMotion.birthdayFill(reduceMotion: false))) { birthdayFill = 1 }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(TomoBarMotion.birthdayFill(reduceMotion: false)))
                        birthdaySheens += 1
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: motion.reduce ? 0.15 : 0.5)) { birthdayShown = 0 }
            }
        }
    }

    /// A band of light sweeping once across what's filled, after a landing; nothing under Reduce Motion.
    private func sheen(width: CGFloat, height: CGFloat, trigger: Int) -> some View {
        let band: CGFloat = 30
        return LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: band, height: height)
            .keyframeAnimator(initialValue: 1.0, trigger: trigger) { light, p in
                light.offset(x: -band + (width + band) * p).opacity(p < 1 && !motion.reduce ? 1 : 0)
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: TomoBarMotion.sheen, timingCurve: .easeInOut)
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipShape(Capsule())
    }
}

/// Where the result's Win badge is in TomoView (`TomoView.space`): the +1 leaves from it.
struct TomoWinBadgeFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}
