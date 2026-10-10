import SwiftUI
import TomoCore

/// Top-level SwiftUI view rendered inside the transparent island panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
            // A peek opening: its word slides from the bar into the card's word slot, over both (panel coordinates).
            if let flight = state.wordFlight {
                TomoWordFlightView(flight: flight) { if state.wordFlight?.id == flight.id { state.wordFlight = nil } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .id(flight.id)
            }
        }
        .ignoresSafeArea()
        .onChange(of: state.mode) { old, new in
            if new != .expanded { state.wordFlight = nil }   // the card went before the word landed
            // Under Reduce Motion the word doesn't slide: the card shows it in its place.
            guard old == .peek, new == .expanded, !TomoMotion.shared.reduce else { return }
            let flight = TomoWordFlight(word: TomoGame.shared.round.say, script: TomoLanguages.shared.target.script,
                                        peek: TomoPeekLayout(hasNotch: state.hasNotch, notchHeight: state.notchHeight),
                                        panelWidth: IslandWindowController.panelSize.width)
            state.wordFlight = flight   // nil: nothing to say, so the card's word just shows
        }
    }
}

// MARK: - Island container

struct IslandContainer: View {
    /// The island's own coordinates (origin top-left, at the top of the screen), where Tomo's canvas finds the island's
    /// top edge for an arrival's strand (TomoCharacterView).
    static let space = "island"

    @ObservedObject var state: AppState
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    var body: some View {
        // Tomo's character draws itself (TomoCharacterView).
        return ZStack(alignment: .topLeading) {
            // Black island shape, lit by the moment's light from Tomo: past the card's edges while it's open, along the
            // peek's bar, and around small Tomo while something counts (TomoIslandLight).
            IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius)
                .fill(Color.black)
                .overlay(alignment: .topLeading) {
                    TomoIslandLight(game: TomoGame.shared, mode: state.mode, view: state.view, tomo: tomoCenter)
                        .frame(width: islandWidth, height: islandHeight)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius))
                }

            // Content
            if state.mode == .expanded {
                IslandContentView(state: state)
                    .frame(width: islandWidth, height: islandHeight)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius))
                    .transition(.opacity)
            }

            // A visit offered as a peek: the invite over the visit's word, beside Tomo (TomoPeekLayout).
            if state.mode == .peek {
                TomoPeekWord(game: TomoGame.shared, layout: peekLayout)
                    .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius))
                    .allowsHitTesting(false)   // a click anywhere on the bar opens the card (IslandWindowController)
                    // Opening, its word flies on into the card (TomoWordFlight): the bar's own goes at once.
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.08))))
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position.
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }

            // Resting: あそぼ！ (or when words are back) and Tomo's level ring, right of the notch. Never a count.
            if state.mode == .compact {
                let side = IslandRestingLayout(width: islandWidth, height: islandHeight).rightSide
                TomoRestingSide()
                    .frame(width: side.width, height: side.height)
                    .position(x: side.midX, y: side.midY)
                    .allowsHitTesting(false)   // a click anywhere on the island opens it (IslandWindowController)
                    .transition(.opacity)
            }

            // Open or peeking: when an ignored visit tucks back in, as an amber line under the card (never under the help
            // panel) or the peek's bar.
            if state.mode == .expanded || state.mode == .peek {
                let barHeight = state.mode == .peek ? peekLayout.size.height : IslandConst.layout(state.view).height
                TomoVisitCountdownLine(game: TomoGame.shared)
                    .frame(width: max(0, islandWidth - TomoCountdownLine.inset * 2), height: TomoCountdownLine.height)
                    .position(x: islandWidth / 2, y: TomoCountdownLine.centerY(cardHeight: barHeight))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = islandSize(mode: newMode, view: state.view, nw: state.notchWidth, nh: state.notchHeight,
                                    hasNotch: state.hasNotch, grown: state.restingHover)
            let cr = newMode == .expanded || newMode == .peek ? IslandConst.expandedCorner : IslandConst.roundedCorner
            withAnimation(anim) {
                islandWidth  = w
                islandHeight = h + (newMode == .expanded ? state.helpPanelHeight : 0)
                cornerRadius = cr
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            let (w, h) = islandSize(mode: .expanded, view: newView, nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = h + state.helpPanelHeight
            }
        }
        .onChange(of: state.helpPanelHeight) { _, extra in
            guard state.mode == .expanded else { return }
            let (_, h) = islandSize(mode: .expanded, view: state.view, nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(extra > 0 ? openSpring : closeEase) { islandHeight = h + extra }
        }
        // The resting island under the pointer: a little bigger (IslandWindowController keeps the click area in step).
        .onChange(of: state.restingHover) { _, grown in
            guard state.mode == .compact else { return }
            let (w, h) = islandSize(mode: .compact, view: state.view, nw: state.notchWidth, nh: state.notchHeight,
                                    hasNotch: state.hasNotch, grown: grown)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                islandWidth = w
                islandHeight = h
            }
        }
        // The island moved to another screen (displays changed): fit its notch, or the lack of one.
        .onChange(of: state.notchWidth) { _, _ in fitToScreen() }
        .onChange(of: state.notchHeight) { _, _ in fitToScreen() }
        .onAppear {
            fitToScreen()
            cornerRadius = state.mode == .expanded || state.mode == .peek ? IslandConst.expandedCorner
                : IslandConst.roundedCorner
        }
    }

    private var peekLayout: TomoPeekLayout { TomoPeekLayout(hasNotch: state.hasNotch, notchHeight: state.notchHeight) }

    /// Where Tomo sits in the island now (BotPlacement's place), where the island's light comes from.
    private var tomoCenter: CGPoint {
        let (x, y, _, _) = botPosition(mode: state.mode, view: state.view, islandW: islandWidth, islandH: islandHeight,
                                       hasNotch: state.hasNotch)
        return CGPoint(x: x, y: y)
    }

    private func fitToScreen() {
        let (w, h) = islandSize(mode: state.mode, view: state.view, nw: state.notchWidth, nh: state.notchHeight,
                                hasNotch: state.hasNotch, grown: state.restingHover)
        islandWidth  = w
        islandHeight = h + (state.mode == .expanded ? state.helpPanelHeight : 0)
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .peek: return 2; case .expanded: return 3 }
    }
}

// MARK: - Island shape
//
// Square top corners (glued to the top of the screen), rounded bottom corners.

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(.init(width, height), cornerRadius) }
        set {
            width        = newValue.first.first
            height       = newValue.first.second
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: width, y: 0))
        // Right edge
        p.addLine(to: CGPoint(x: width, y: height - cr))
        // Bottom-right corner
        p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge
        p.addLine(to: CGPoint(x: cr, y: height))
        // Bottom-left corner
        p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW,
                                                      islandH: islandH, hasNotch: state.hasNotch)
        let canvasSize = diameter / 0.6
        // Room above Tomo in its canvas: for particles, and for an arrival, which starts about 1.9 R up and stretched,
        // its head at the island's top edge in the card (the mask cuts what's above the island).
        let overhang: CGFloat = 72

        Group {
            // The halo behind Tomo in the card, in the moment's colour (TomoMomentHalo).
            if state.mode == .expanded {
                TomoMomentHalo(game: TomoGame.shared, diameter: diameter, opacity: botGlowOpacity(state.effectiveState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Extra canvas at the top (`overhang`); the position is offset up by half of it, and TomoBlob compensates
            // with cy = H/2 + particleOverhang/2 + dy*R + R*0.1. Resting, small Tomo glows amber while something counts
            // (the rule TomoRestingSide and a visit use).
            TomoCharacterView(state: state, particleOverhang: overhang, callGlow: { [state] in
                state.mode == .compact && TomoGame.shared.somethingCounts ? 1 : 0
            })
                .frame(width: canvasSize, height: canvasSize + overhang)
                .opacity(opacity)
                .position(x: cx, y: cy - overhang / 2)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
        }
        // Pokes and hover are handled by the AppKit NSEvent monitors in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat,
                 hasNotch: Bool = true) -> (CGFloat, CGFloat, CGFloat, Double) {
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
    case .hidden:
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (40, resting.botCenterY, resting.botDiameter, 1)
    case .peek: return (TomoPeekLayout.tomoCenterX, islandH / 2, TomoPeekLayout.tomoDiameter(height: islandH), 1)
    case .expanded:
        let layout = IslandConst.layout(view)
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card (VStack top=8, header=34 → content starts at y=42)
            let headerBottom: CGFloat = 42
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, layout.botDiameter, 1)
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(state: state)
                .frame(height: 34)
                .opacity(state.view == .confused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view == .confused)

            ZStack {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    // Tomo's card fills the available height; the dizzy card has a fixed 98pt content frame.
                    let isTall = v == .overview
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    IslandViewContent(view: v, state: state)
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 98)
                        .frame(minHeight: (isTall && !active) ? 0 : nil, maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

// MARK: - Island header

struct IslandHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Left: Tomo's name, age and growth (kept clear of the physical notch)
            TomoHeaderLeft()
                .padding(.leading, 18)

            Spacer()

            // Right: words learned, restart, voice
            TomoHeaderRight(state: state)
            .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
    }
}
