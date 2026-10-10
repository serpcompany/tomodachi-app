import SwiftUI
import TomoCore

// MARK: - Tomo in the notch island (the shared drawing is TomoBlob, in TomoCore)

/// Tomo in the island: a Canvas redrawn every frame, its gaze on the cursor. It follows Reduce Motion (`TomoMotion`).
/// It arrives and leaves through the notch (`move`): it drips in when it comes out on its own, is pulled up before the
/// card or the peek folds (`AppState.leaving`), and fades back in beside the notch. Its host says how strongly it glows
/// to ask to play (`callGlow`), and the strand hangs from the island's top edge, straight above it.
struct TomoCharacterView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// How strongly small Tomo glows amber to ask to play, 0…1, read every frame (BotPlacement: resting, while
    /// something counts).
    var callGlow: () -> CGFloat = { 0 }
    @StateObject private var blob = TomoBlob(motion: .shared)
    @State private var seenArrivals = 0

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

    /// Small Tomo fades back in beside the notch this long after the island folds: once it has folded (0.34 s), or once
    /// the pull up (0.45 s) is done if it plays as it folds (Reduce Motion's fade).
    static func backAfter(pulledUp: Bool) -> TimeInterval { pulledUp ? 0.35 : 0.5 }

    var body: some View {
        GeometryReader { geo in
            // The island's top edge (the top of the screen, where the notch is), in this canvas: an arrival's strand
            // hangs from there. Read from the layout as it animates, so it stays put while the island opens or closes.
            let islandTop = -geo.frame(in: .named(IslandContainer.space)).minY
            // The Canvas must read the timeline's date, or SwiftUI won't redraw it every frame.
            TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
                Canvas { context, size in
                    blob.frameDate = timeline.date
                    let g = gaze()
                    blob.lookX = g.x
                    blob.lookY = g.y
                    blob.particleOverhang = particleOverhang
                    blob.strandAnchor = CGPoint(x: size.width / 2, y: islandTop - 2)
                    blob.callGlow = callGlow()
                    blob.step()
                    blob.draw(context, size: size)
                }
            }
        }
        .onChange(of: state.effectiveState) { _, s in blob.setState(s) }
        .onChange(of: state.mode) { old, new in
            let arriving = state.arrivals != seenArrivals
            seenArrivals = state.arrivals
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
            blob.setState(state.effectiveState, force: true)
            blob.setGrowth(TomoGame.shared.growthStep)
            // The launch visit can open the island before Tomo is first drawn: it drips in then.
            if state.arrivals > 0, IslandWindowController.countsAsOpen(state.mode) { blob.dripIn() }
            seenArrivals = state.arrivals
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
