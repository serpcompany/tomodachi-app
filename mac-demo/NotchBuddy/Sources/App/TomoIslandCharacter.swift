import AppKit
import Combine
import SwiftUI
import TomoCore

// MARK: - Tomo in the notch island (the shared drawing is TomoBlob, in TomoCore)

/// Tomo in the island: the learner's own, in its material (`TomoMaterial.own`), a Canvas redrawn every frame, its gaze
/// on the cursor. It follows Reduce Motion (`TomoMotion`).
/// It arrives and leaves through the notch (`move`): it drips in when it comes out on its own, is pulled up before the
/// card or the peek folds (`AppState.leaving`), and fades back in beside the notch. It says hello (#137) when it first
/// appears, as the app starts, and when the Mac wakes (`wakes`). Small, in the resting island, it wears its badges
/// (`wearsBadges`: a "…" bubble while it checks an answer, a Zz while it dozes), drawn just right of its canvas
/// (`badgeRoom`). Its host says how strongly it glows to ask to play (`callGlow`), and the strand and the hello's drop
/// hang from the island's top edge, straight above it.
struct TomoCharacterView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// How strongly small Tomo glows amber to ask to play, 0…1, read every frame (BotPlacement: resting, while
    /// something counts).
    var callGlow: () -> CGFloat = { 0 }
    @StateObject private var blob = TomoBlob(material: .own, motion: .shared)
    @State private var seenArrivals = 0
    @State private var greeted = false

    /// What Tomo does when the island changes: drips in when the app brought it out (a visit, as its card or its peek:
    /// `AppState.arrivals`), is pulled up into the notch when the card or the peek closes (already, if the fold waited
    /// for it), and otherwise comes back if it was away (a click reopening the island). Opening a peek into its card is
    /// the same visit: nothing.
    enum Move: Equatable { case dripIn, pullUp, appear, none }

    nonisolated static func move(from old: IslandMode, to new: IslandMode, arriving: Bool) -> Move {
        let open = IslandWindowController.countsAsOpen
        switch (open(old), open(new)) {
        case (false, true): return arriving ? .dripIn : .appear
        case (true, false): return .pullUp
        default: return .none
        }
    }

    /// Where Tomo is small enough to wear its badges instead of its drifting z's: resting beside the notch. Not in the
    /// card, whose own line says "…" while it checks; not in the peek, where Tomo is big, a badge would reach its words,
    /// and a visit never dozes or checks; nor hidden.
    nonisolated static func wearsBadges(_ mode: IslandMode) -> Bool { mode == .compact }

    /// The room the canvas has right of its frame for a badge (the frame stays the size BotPlacement gives, so Tomo
    /// doesn't move or grow). The island's own shape still clips it: the badge stays in the ear, left of the notch.
    static let badgeRoom: CGFloat = 24

    /// TOMO_BADGE=checking|dozing: small Tomo wears that badge, for snapshots. Checking holds Tomo in `.thinking`
    /// (nothing makes it check an answer while small today: answers are choices); dozing lets it doze 2 s after the
    /// pointer stops, not 45 s.
    nonisolated static let testBadge = ProcessInfo.processInfo.environment["TOMO_BADGE"]

    /// Tomo's state, or `.thinking` for TOMO_BADGE=checking.
    private var shownState: BotState { Self.testBadge == "checking" ? .thinking : state.effectiveState }

    /// Small Tomo fades back in beside the notch this long after the island folds: once it has folded (0.34 s), or once
    /// the pull up (0.45 s) is done if it plays as it folds (Reduce Motion's fade).
    static func backAfter(pulledUp: Bool) -> TimeInterval { pulledUp ? 0.35 : 0.5 }

    /// Tomo says hello (#137) the first time it shows after the app starts, and when the Mac wakes while it shows. Never
    /// while the island is hidden (at launch with no visit, until it moves beside the notch): its timeline is paused
    /// then, so it would hold the hello's first frame.
    nonisolated static func saysHello(greeted: Bool, waking: Bool, mode: IslandMode) -> Bool {
        mode != .hidden && (waking || !greeted)
    }

    /// When Tomo says hello again: the screens waking (from sleep, or the display's own), the learner unlocking the Mac,
    /// and coming back to their session (fast user switching). No permission needed for any of them.
    /// TOMO_HELLO=<seconds>: a wake that long after Tomo first shows, for snapshots (a test run can't sleep the Mac).
    static let wakes: AnyPublisher<Void, Never> = {
        let workspace = NSWorkspace.shared.notificationCenter
        var all = [workspace.publisher(for: NSWorkspace.screensDidWakeNotification),
                   DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsUnlocked")),
                   workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)]
            .map { $0.map { _ in () }.eraseToAnyPublisher() }
        if let after = ProcessInfo.processInfo.environment["TOMO_HELLO"].flatMap(Double.init) {
            all.append(Just(()).delay(for: .seconds(after), scheduler: RunLoop.main).eraseToAnyPublisher())
        }
        return Publishers.MergeMany(all).eraseToAnyPublisher()
    }()

    var body: some View {
        GeometryReader { geo in
            // The island's top edge (the top of the screen, where the notch is), in this canvas: an arrival's strand
            // hangs from there. Read from the layout as it animates, so it stays put while the island opens or closes.
            let islandTop = -geo.frame(in: .named(IslandContainer.space)).minY
            // The Canvas must read the timeline's date, or SwiftUI won't redraw it every frame.
            TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
                // Wider than the frame on the right, for a badge; Tomo is drawn at the frame's size, where it was.
                Canvas { context, _ in
                    blob.frameDate = timeline.date
                    let g = gaze()
                    blob.lookX = g.x
                    blob.lookY = g.y
                    blob.particleOverhang = particleOverhang
                    blob.strandAnchor = CGPoint(x: geo.size.width / 2, y: islandTop - 2)
                    blob.callGlow = callGlow()
                    blob.showsBadges = Self.wearsBadges(state.mode)
                    blob.step()
                    blob.draw(context, size: geo.size)
                }
                .frame(width: geo.size.width + Self.badgeRoom, height: geo.size.height)
            }
        }
        .onChange(of: shownState) { _, s in blob.setState(s) }
        .onChange(of: state.mode) { old, new in
            let arriving = state.arrivals != seenArrivals
            seenArrivals = state.arrivals
            if Self.saysHello(greeted: greeted, waking: false, mode: new) {   // first shown: its hello, not a drip
                greeted = true
                if blob.hello() { return }
            }
            switch Self.move(from: old, to: new, arriving: arriving) {
            case .dripIn: blob.dripIn()
            case .appear: blob.appear()
            case .pullUp:
                let pulledUp = blob.isLeaving                   // the fold waited for it (`leaving`)
                blob.pullUp()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.backAfter(pulledUp: pulledUp)) { [blob] in
                    blob.appear()
                }
            case .none: break
            }
        }
        // The card or the peek is about to fold: Tomo is pulled up out of it first. Kept open after all: back it comes.
        .onChange(of: state.leaving) { _, leaving in
            if leaving { blob.pullUp() } else if IslandWindowController.countsAsOpen(state.mode) { blob.appear() }
        }
        .onAppear {
            if Self.testBadge == "dozing" { blob.dozeAfter = 2 }
            blob.setState(shownState, force: true)
            blob.setGrowth(TomoGame.shared.growthStep)
            // Tomo's first appearance, as the app starts, is its hello: beside the notch, or into the launch visit's card
            // (which can open before Tomo is first drawn), greeting it instead of dripping in. A material without a hello
            // drips in as before. Hidden at launch (no visit): it says hello once it shows (`onChange`).
            let launchVisit = state.arrivals > 0 && IslandWindowController.countsAsOpen(state.mode)
            var said = false
            if Self.saysHello(greeted: greeted, waking: false, mode: state.mode) { greeted = true; said = blob.hello() }
            if !said, launchVisit { blob.dripIn() }
            seenArrivals = state.arrivals
        }
        .onReceive(Self.wakes) { _ in
            if Self.saysHello(greeted: greeted, waking: true, mode: state.mode) { blob.hello() }
        }
        .tomoReactions(blob)
    }

    /// Cursor direction relative to Tomo, −1…1 (positive y = above).
    private func gaze() -> CGPoint {
        // Both in the island screen's coordinates: the island is centred at its top.
        let (w, h) = islandSize(mode: state.mode, view: state.view, nw: state.notchWidth, nh: state.notchHeight,
                                hasNotch: state.hasNotch, grown: state.restingHover)
        let (bx, by, _, _) = botPosition(mode: state.mode, view: state.view, islandW: w, islandH: h, hasNotch: state.hasNotch)
        let screenX = state.screenWidth / 2 - w / 2 + bx
        return CGPoint(x: tanh((state.mousePosition.x - screenX) / 260),
                       y: -tanh((state.mousePosition.y - by) / 200))
    }
}
