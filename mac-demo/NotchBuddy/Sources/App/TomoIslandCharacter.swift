import AppKit
import Combine
import SwiftUI
import TomoCore

// MARK: - Tomo in the notch island (the shared drawing is TomoBlob, in TomoCore)

/// Tomo in the island: the learner's own, in its material (`TomoMaterial.own`), a Canvas redrawn every frame, its gaze
/// on the cursor. It follows Reduce Motion (`TomoMotion`).
/// It arrives through the notch (`move`): it drips in when it comes out on its own. Between the island's states it
/// travels (BotPlacement moves this view: TomoTravel), and it's pulled up into the notch only when the island folds
/// away (`AppState.leaving`). It says hello (#137) when it first
/// appears, as the app starts, and when the Mac wakes (`wakes`). Small, in the resting island, it wears its badges
/// (`wearsBadges`: a "…" bubble while it checks an answer, a Zz while it dozes), drawn just right of its frame. The
/// canvas reaches past its frame for them and for the call glow (`canvasRoom`). Its host says how strongly it glows to
/// ask to play (`callGlow`), and the strand and the hello's drop hang from the island's top edge, straight above it.
/// Without a notch it stands under that edge (`ceiling`). While music plays and it rests, it dances (`dance`, TomoMusic).
struct TomoCharacterView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// How strongly small Tomo glows amber to ask to play, 0…1, read every frame (BotPlacement: resting, while
    /// something counts).
    var callGlow: () -> CGFloat = { 0 }
    @StateObject private var blob = TomoBlob(material: .own, motion: .shared)
    @State private var seenArrivals = 0
    @State private var greeted = false
    /// The season's weather (TomoCalendar), looked up when the card opens.
    @State private var todaysWeather: TomoWeather?
    /// Music playing in Music or Spotify (TomoMusic), quiet hours now, and how Tomo dances today (TomoCalendar).
    @ObservedObject private var music = TomoMusic.shared
    @State private var quiet = false
    @State private var todaysDance = TomoDance.bounce

    /// What Tomo does when the island changes: drips in when the app brought it out (a visit, as its card or its peek:
    /// `AppState.arrivals`), and is pulled up into the notch when the card or the peek closes with nowhere to rest
    /// (the island hiding; already, if the fold waited for it). Otherwise it travels (TomoTravel, in BotPlacement): from
    /// beside the notch into the card on a click, from the peek into its card, and back beside the notch when the card
    /// or the peek tucks in. `appear` brings it back if it was away (the card reopened while it was being pulled up).
    enum Move: Equatable { case dripIn, pullUp, appear, none }

    nonisolated static func move(from old: IslandMode, to new: IslandMode, arriving: Bool) -> Move {
        let open = IslandWindowController.countsAsOpen
        switch (open(old), open(new)) {
        case (false, true): return arriving ? .dripIn : .appear
        case (true, false): return new == .hidden ? .pullUp : .none
        default: return .none
        }
    }

    /// Where Tomo is small enough to wear its badges instead of its drifting z's: resting beside the notch. Not in the
    /// card, whose own line says "…" while it checks; not in the peek, where Tomo is big, a badge would reach its words,
    /// and a visit never dozes or checks; nor hidden.
    nonisolated static func wearsBadges(_ mode: IslandMode) -> Bool { mode == .compact }

    /// The season's weather shows around Tomo only in Tomo's card, where it has room and the learner is looking: never
    /// resting beside the notch, in the peek, the dizzy card or hidden.
    nonisolated static func weather(mode: IslandMode, view: IslandView, today: TomoWeather?) -> TomoWeather? {
        mode == .expanded && view == .overview ? today : nil
    }

    /// Without a notch the island floats below the screen's top, so Tomo stands under its top edge, this far inside it,
    /// whatever the island shows (TomoBlob draws a form too tall for that smaller: the 3さい one resting in the capsule,
    /// #196). Under a notch the island's top is the screen's: no ceiling.
    nonisolated static let ceilingInset: CGFloat = 1
    nonisolated static func ceiling(islandTop: CGFloat, hasNotch: Bool) -> CGFloat? {
        hasNotch ? nil : islandTop + ceilingInset
    }

    /// The room the canvas has right of its frame for a badge (the frame stays the size BotPlacement gives, so Tomo
    /// doesn't move or grow). The island's own shape still clips it: the badge stays in the ear, left of the notch.
    nonisolated static let badgeRoom: CGFloat = 24

    /// The room the canvas has beyond its frame on each side, so nothing Tomo draws is cut off by the canvas's edge: the
    /// call glow reaches 1.8 R from Tomo's middle (0.66 of the frame's width at 6さい, past its sides and its bottom),
    /// and a badge sits on its right (`badgeRoom`). Tomo is still drawn at the frame's size and place.
    nonisolated static func canvasRoom(width w: CGFloat) -> (left: CGFloat, right: CGFloat, bottom: CGFloat) {
        let glow = ceil(w * 0.2)
        return (glow, max(glow, badgeRoom), glow)
    }

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

    /// Tomo dances while music plays (TomoMusic) and it rests beside the notch: visits win (the card, the peek), and so
    /// do quiet hours. How it dances is the day's (`TomoCalendar.danceToday`: the 盆踊り during お盆).
    nonisolated static func dance(playing: Bool, mode: IslandMode, quiet: Bool, today: TomoDance) -> TomoDance? {
        playing && mode == .compact && !quiet ? today : nil
    }

    /// The learner unlocking the Mac, delivered at once even though Tomodachi isn't the active app (TomoDistributed).
    static let unlocks = TomoDistributed(["com.apple.screenIsUnlocked"])

    /// When Tomo says hello again: the screens waking (from sleep, or the display's own), the learner unlocking the Mac,
    /// and coming back to their session (fast user switching). No permission needed for any of them.
    /// TOMO_HELLO=<seconds>: a wake that long after Tomo first shows, for snapshots (a test run can't sleep the Mac).
    static let wakes: AnyPublisher<Void, Never> = {
        let workspace = NSWorkspace.shared.notificationCenter
        var all = [workspace.publisher(for: NSWorkspace.screensDidWakeNotification).eraseToAnyPublisher(),
                   unlocks.publisher,
                   workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification).eraseToAnyPublisher()]
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
            let room = Self.canvasRoom(width: geo.size.width)
            TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
                // Bigger than the frame, for the glow and a badge (`canvasRoom`); Tomo is drawn at the frame's size,
                // where it was.
                Canvas { context, _ in
                    var context = context
                    context.translateBy(x: room.left, y: 0)
                    blob.frameDate = timeline.date
                    let g = gaze()
                    blob.lookX = g.x
                    blob.lookY = g.y
                    blob.particleOverhang = particleOverhang
                    blob.strandAnchor = CGPoint(x: geo.size.width / 2, y: islandTop - 2)
                    blob.ceiling = Self.ceiling(islandTop: islandTop, hasNotch: state.hasNotch)
                    blob.callGlow = callGlow()
                    blob.showsBadges = Self.wearsBadges(state.mode)
                    blob.weather = Self.weather(mode: state.mode, view: state.view, today: todaysWeather)
                    blob.dance = Self.dance(playing: music.playing, mode: state.mode, quiet: quiet, today: todaysDance)
                    blob.feeling = TomoGame.shared.feeling   // the Testing menu's look (#257)
                    blob.step()
                    blob.draw(context, size: geo.size)
                }
                .frame(width: geo.size.width + room.left + room.right, height: geo.size.height + room.bottom)
                .offset(x: -room.left)
            }
        }
        .onChange(of: shownState) { _, s in blob.setState(s) }
        .onChange(of: state.mode) { old, new in
            if new == .expanded { todaysWeather = TomoCalendar.weatherToday }
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
            TomoMusic.shared.start()
            checkDay()
            todaysWeather = TomoCalendar.weatherToday
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
        // Music starting, and once a minute while it plays: quiet hours, and the day's dance.
        .onChange(of: music.playing) { _, playing in if playing { checkDay() } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in if music.playing { checkDay() } }
        .tomoReactions(blob)
    }

    private func checkDay() {
        quiet = DropIn.quietEnds() != nil
        todaysDance = TomoCalendar.danceToday
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
