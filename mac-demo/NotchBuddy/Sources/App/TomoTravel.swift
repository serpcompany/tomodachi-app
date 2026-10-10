import SwiftUI
import TomoCore

// MARK: - Tomo travels between the island's states (#137, effect 1)
//
// One Tomo moves from beside the notch into the card, from the peek into the card, and back beside the notch when the
// card or the peek tucks in, instead of vanishing in one place and showing up in the other. It's a spring, with a squash
// and stretch of jelly: it gathers itself, stretches as it goes and wobbles as it lands. Arrivals from the notch (a
// visit) still drip in (#142): the drip is their move. Under Reduce Motion there's no travel: Tomo fades out where it was
// and in where it goes, quickly. It's drawn every frame from the clock while it travels and from its first drawn frame
// (so a slow first frame of the card doesn't eat it), and nothing ticks once it has landed.

/// Where Tomo is in the island (its centre, island coordinates), how big, and how opaque.
struct TomoSpot: Equatable {
    var center: CGPoint
    var diameter: CGFloat
    var opacity: Double
}

/// Tomo during a travel: its spot, and how much it's squashed or stretched (1: neither), about its bottom.
struct TomoPose: Equatable {
    var spot: TomoSpot
    var sx: CGFloat = 1
    var sy: CGFloat = 1
}

struct TomoTravel: Equatable {
    enum Style: Equatable {
        /// Into the bigger island (the card): a spring that overshoots a little, then a wobble.
        case open
        /// Back beside the notch: as fast as the island folds (`fold`), so it's home before the island is small, then a
        /// small wobble.
        case close
        /// A move within the same state (the resting island growing under the pointer, the dizzy card): a spring, no
        /// squash.
        case settle
        /// Reduce Motion: out where it was, in where it goes.
        case fade
    }

    /// TOMO_SLOW_MOTION=<factor> (snapshots): Tomo's travel and the island's opening and folding take that many times
    /// longer, so a snapshot every 0.1 s catches each step of a move that lasts well under a second.
    static let slowMotion = max(1, ProcessInfo.processInfo.environment["TOMO_SLOW_MOTION"].flatMap(Double.init) ?? 1)

    static let openDuration: TimeInterval = 0.7
    static let closeDuration: TimeInterval = 0.55
    /// How long the island takes to fold (IslandContainer's close curve): Tomo is home by then.
    static let fold: TimeInterval = 0.34
    static let fadeHalf: TimeInterval = 0.12

    let from: TomoSpot
    let to: TomoSpot
    let style: Style

    /// Which move a change of Tomo's spot is: none for an arrival (it drips in from the notch) or before Tomo was first
    /// drawn; a fade under Reduce Motion when the island's state changed, and no move at all for a small change within
    /// a state; a close when it goes back to rest (or hides), an open when it goes into the peek or the card, and a settle
    /// otherwise.
    static func style(modeChanged: Bool, closing: Bool, arrived: Bool, firstDrawn: Bool, reduceMotion: Bool) -> Style? {
        if arrived || !firstDrawn { return nil }
        if reduceMotion { return modeChanged ? .fade : nil }
        if !modeChanged { return .settle }
        return closing ? .close : .open
    }

    var duration: TimeInterval {
        switch style {
        case .open, .settle: Self.openDuration
        case .close: Self.closeDuration
        case .fade: Self.fadeHalf * 2
        }
    }

    /// How far along the way Tomo is, `t` seconds in: a spring for an open (it overshoots by a few percent) or a settle,
    /// the island's own fold curve for a close; exactly 1 from `duration` on.
    func progress(at t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        guard t < duration else { return 1 }
        switch style {
        case .open, .settle: return Self.spring(t, response: 0.5, damping: 0.72)
        case .close: return t >= Self.fold ? 1 : Self.foldCurve(t / Self.fold)
        case .fade: return t < Self.fadeHalf ? 0 : 1
        }
    }

    /// How much it squashes and stretches, by how far it goes: a short hop barely, across the card fully.
    var amplitude: CGFloat {
        guard style == .open || style == .close else { return 0 }
        return min(1, hypot(to.center.x - from.center.x, to.center.y - from.center.y) / 100)
    }

    func pose(at t: TimeInterval) -> TomoPose {
        if t >= duration { return TomoPose(spot: to) }
        if style == .fade {
            let first = t < Self.fadeHalf
            var spot = first ? from : to
            spot.opacity *= first ? 1 - t / Self.fadeHalf : (t - Self.fadeHalf) / Self.fadeHalf
            return TomoPose(spot: spot)
        }
        let p = progress(at: t), q = min(max(p, 0), 1)
        let spot = TomoSpot(center: CGPoint(x: from.center.x + (to.center.x - from.center.x) * p,
                                            y: from.center.y + (to.center.y - from.center.y) * p),
                            diameter: max(1, from.diameter + (to.diameter - from.diameter) * p),
                            opacity: from.opacity + (to.opacity - from.opacity) * q)
        let (sx, sy) = squash(at: t)
        return TomoPose(spot: spot, sx: sx, sy: sy)
    }

    /// Jelly: it gathers itself (a little taller), stretches as it goes, and lands with a wobble that dies away.
    private func squash(at t: TimeInterval) -> (CGFloat, CGFloat) {
        let a = amplitude
        guard a > 0 else { return (1, 1) }
        let land: TimeInterval = style == .open ? 0.36 : Self.fold
        let stretchEnd = land
        var sy: CGFloat = 1, sx: CGFloat = 1
        if t < stretchEnd {
            let u = t / stretchEnd
            let s = CGFloat(sin(Double.pi * u)) * (style == .open ? 0.22 : 0.16) * a
            sy += s
            sx -= s * 0.55
        } else {
            let tau = t - land
            let w = CGFloat(exp(-8 * tau) * cos(2 * Double.pi * 2.6 * tau)) * (style == .open ? 0.16 : 0.1) * a
            sy -= w
            sx += w * 0.75
        }
        return (sx, sy)
    }

    /// A spring from 0 to 1 (as `TomoWordFlight` slides): `response` its period, `damping` its damping ratio.
    static func spring(_ t: TimeInterval, response: Double, damping: Double) -> Double {
        let w = 2 * Double.pi / response, wd = w * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    /// The island's fold curve (a cubic Bézier, 0.45, 0, 0.2, 1), at `x` of the way through its time.
    static func foldCurve(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (0.45, 0.0, 0.2, 1.0)
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {   // the curve's t for this x
            let mid = (lo + hi) / 2
            if bez(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return bez((lo + hi) / 2, y1, y2)
    }
}

/// BotPlacement's Tomo on the move: where it's drawn now, travelling to where the island puts it. It starts a travel
/// when that place changes (`TomoTravel.style`), from where Tomo is drawn (so a new travel mid-way carries on from
/// there), and starts its clock at the first frame drawn after the change. `moving` keeps the frames coming only while it
/// travels.
@MainActor
final class TomoTraveller: ObservableObject {
    @Published private(set) var moving = false
    private var target: TomoSpot?
    private var mode: IslandMode?
    private var arrivals = 0
    private var travel: TomoTravel?
    private var start: Date?

    func pose(for target: TomoSpot, mode: IslandMode, arrivals: Int, reduceMotion: Bool, now: Date) -> TomoPose {
        if target != self.target {
            let modeChanged = self.mode != nil && mode != self.mode
            if !modeChanged, let travel {
                // The island settling as it changes (its size reaching the new state a moment later): the same travel,
                // to the new place, on the same clock.
                self.travel = TomoTravel(from: travel.from, to: target, style: travel.style)
            } else {
                let style = TomoTravel.style(modeChanged: modeChanged, closing: !IslandWindowController.countsAsOpen(mode),
                                             arrived: arrivals != self.arrivals, firstDrawn: self.target != nil,
                                             reduceMotion: reduceMotion)
                let here = current(now)?.spot
                travel = style.flatMap { s in here.map { TomoTravel(from: $0, to: target, style: s) } }
                // Going back beside the notch it keeps time with the island's fold, which starts now; into the card it
                // starts at its first frame, so a slow first frame of the card doesn't eat it.
                start = travel?.style == .close ? now : nil
            }
            self.target = target
            if travel != nil && !moving { DispatchQueue.main.async { [weak self] in self?.moving = true } }
        }
        self.mode = mode
        self.arrivals = arrivals
        return current(now) ?? TomoPose(spot: target)
    }

    /// Where Tomo is now: travelling, waiting for its first frame (at the start), or still.
    private func current(_ now: Date) -> TomoPose? {
        guard let travel else { return target.map { TomoPose(spot: $0) } }
        guard moving || start != nil else { return travel.pose(at: 0) }
        if start == nil { start = now }
        let t = now.timeIntervalSince(start ?? now) / TomoTravel.slowMotion
        if t >= travel.duration {
            self.travel = nil
            DispatchQueue.main.async { [weak self] in if self?.travel == nil { self?.moving = false } }
            return TomoPose(spot: travel.to)
        }
        return travel.pose(at: t)
    }
}
