import SwiftUI
import TomoCore

// MARK: - The peek: a visit offered by the notch, before its card opens (Settings: Peek first; #19, #130)
//
// The island widens into a bar (`TomoPeekLayout`): Tomo calling at the left (the island's own Tomo, BotPlacement),
// and beside it the pack's invite in amber over the visit's word and a speaker. The pointer resting on it (0.45 s,
// IslandStateMachine) or a click opens the card, and the word slides from the bar into the card's word slot
// (`TomoWordFlight`), where Tomo says it. Ignored, it tucks back in when its countdown line runs out, as a visit's
// card does. It never takes the keyboard, and it lets clicks through outside itself (IslandWindowController).

/// Where everything sits in the peek's bar, in the island's coordinates (origin top-left). Fixed slots, like the card's
/// grid (TomoGrid): the text sits below the notch, right of Tomo's column, above the countdown line, and the word is
/// one line, made smaller only to fit its row.
struct TomoPeekLayout {
    static let width: CGFloat = 520
    static let belowNotch: CGFloat = 56          // 88 pt tall under a 32 pt notch
    static let flatHeight: CGFloat = 64          // on a screen without a notch
    static let side: CGFloat = 14                // the bar's sides to Tomo's column and to the text's end
    static let tomoColumn: CGFloat = 72
    static var tomoCenterX: CGFloat { side + tomoColumn / 2 }
    static let gap: CGFloat = 8
    static let notchClearance: CGFloat = 2
    static let inviteFont: CGFloat = 11
    static let wordFont: CGFloat = 24
    static let inviteRow: CGFloat = 14
    static let rowGap: CGFloat = 1
    static let wordRow: CGFloat = 28
    static let speaker: CGFloat = TomoGrid.iconButton

    /// Tomo's size in the bar (BotPlacement's diameter): 56 under a notch, 44 in the 64 pt bar.
    static func tomoDiameter(height: CGFloat) -> CGFloat { min(56, height - 20) }

    let hasNotch: Bool
    let notchHeight: CGFloat

    var size: CGSize {
        CGSize(width: Self.width, height: hasNotch ? notchHeight + Self.belowNotch : Self.flatHeight)
    }
    /// Tomo's column, the bar's full height (left of the notch, which sits in the bar's middle).
    var tomo: CGRect { CGRect(x: Self.side, y: 0, width: Self.tomoColumn, height: size.height) }
    /// The text's room: right of Tomo, below the notch, above the countdown line.
    var text: CGRect {
        let top = hasNotch ? notchHeight + Self.notchClearance : 0
        let bottom = size.height - TomoCountdownLine.bottom - TomoCountdownLine.height - 2
        let x = tomo.maxX + Self.gap
        return CGRect(x: x, y: top, width: size.width - x - Self.side, height: bottom - top)
    }
    private var blockTop: CGFloat {
        text.minY + max(0, (text.height - Self.inviteRow - Self.rowGap - Self.wordRow) / 2)
    }
    var invite: CGRect { CGRect(x: text.minX, y: blockTop, width: text.width, height: Self.inviteRow) }
    /// The word's row: the word, then the speaker.
    var word: CGRect {
        CGRect(x: text.minX, y: invite.maxY + Self.rowGap, width: text.width, height: Self.wordRow)
    }
    /// The widest the word may be: its row, less the speaker after it.
    var wordWidth: CGFloat { word.width - Self.gap - Self.speaker }

    /// The word's font size: 24 pt, smaller only to fit its row on one line (measured the way it's drawn).
    func wordSize(_ word: String) -> CGFloat {
        let w = ceil((word as NSString).size(withAttributes: [.font: TomoWords.lineFont(Self.wordFont)]).width)
        return w <= wordWidth ? Self.wordFont : max(12, floor(Self.wordFont * wordWidth / w * 2) / 2)
    }
}

/// The peek's text for the game it's given: the pack's invite (あそぼ！) over the round the visit offers. It observes
/// only that game, so the island doesn't redraw on every change to the game.
struct TomoPeekWord: View {
    @ObservedObject var game: TomoGame
    @ObservedObject var lang = TomoLanguages.shared
    let layout: TomoPeekLayout

    var body: some View {
        TomoPeekBar(layout: layout, invite: lang.target.lines.invite ?? lang.target.lines.practice, word: game.round.say)
    }
}

/// The peek's bar beside Tomo: the invite in amber over the word, and a speaker. It takes no clicks of its own: a click
/// anywhere on the bar opens the card, where Tomo says the word.
struct TomoPeekBar: View {
    let layout: TomoPeekLayout
    let invite: String
    let word: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(invite)
                .font(.system(size: TomoPeekLayout.inviteFont, weight: .bold, design: .rounded))
                .foregroundColor(TomoCountdownLine.amber)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: layout.invite.width, height: layout.invite.height, alignment: .leading)
                .offset(x: layout.invite.minX, y: layout.invite.minY)
            HStack(spacing: TomoPeekLayout.gap) {
                Text(word)
                    .font(.system(size: layout.wordSize(word), weight: .bold, design: .rounded))
                    .lineLimit(1).fixedSize()
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: TomoPeekLayout.speaker, height: TomoPeekLayout.speaker)
                    .background(Circle().fill(Color.white.opacity(0.09)))
            }
            .foregroundColor(Color(hex: "#F5F6F8"))
            .frame(width: layout.word.width, height: layout.word.height, alignment: .leading)
            .offset(x: layout.word.minX, y: layout.word.minY)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

// MARK: - The word sliding from the peek into the card

/// A peek's word on its way into the card as the peek opens: from where the bar draws it to where the card's picture
/// round draws it (TomoView's word slot, at TomoLineView's fitted size), in panel coordinates (origin top-left). The
/// card's own word shows once it has landed (`duration`).
struct TomoWordFlight: Equatable {
    /// How long the word is in the air before the card's own word takes over: the slide has settled by then.
    static let duration: TimeInterval = 0.6
    static let response: Double = 0.45, damping: Double = 0.7

    /// How far along the slide is, `t` seconds in: a spring (about 0.5 s, overshooting by about 5% at 0.3 s), exactly 1
    /// from `duration` on, so the card's word takes over where the flying one is. Drawn every frame from the clock, like
    /// the countdown line, so it never depends on the frames SwiftUI gets to draw.
    static func progress(at t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        guard t < duration else { return 1 }
        let w = 2 * Double.pi / response, wd = w * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    let id = UUID()
    let word: String
    let from: CGPoint      // the word's leading edge and vertical centre
    let fromSize: CGFloat
    let to: CGPoint
    let toSize: CGFloat

    init?(word: String, script: String, peek: TomoPeekLayout, panelWidth: CGFloat) {
        guard !word.isEmpty else { return nil }
        self.word = word
        from = CGPoint(x: (panelWidth - peek.size.width) / 2 + peek.word.minX, y: peek.word.midY)
        fromSize = peek.wordSize(word)
        let slot = Self.cardWordSlot(panelWidth: panelWidth)
        toSize = TomoWords.fittingSize(TomoWords.tokens(word, script: script, spacesOnly: true), script: script,
                                       in: slot.size, maxSize: 30)
        to = CGPoint(x: slot.minX + TomoWords.wordPadding, y: slot.midY)
    }

    /// The picture card's word slot in the panel: the open island (centred at the top), its padding and header
    /// (IslandContentView: 8 pt and the 34 pt header above, 10 pt at the sides), the level bar and its gap, then
    /// TomoView's card: Tomo's column, the gap, and the word row at the top of the rows, which are centred in the card.
    static func cardWordSlot(panelWidth: CGFloat) -> CGRect {
        let islandX = (panelWidth - IslandConst.expandedWidth) / 2
        let cardTop = 8 + 34 + TomoGrid.levelBar + TomoGrid.levelBarGap
        let rows = TomoGrid.wordRow + TomoGrid.promptRow + TomoGrid.goalRow + TomoGrid.rowGap * 2
        return CGRect(x: islandX + 10 + TomoGrid.tomoColumn + TomoGrid.gap,
                      y: cardTop + (TomoGrid.content.height - rows) / 2,
                      width: TomoGrid.wordWidth, height: TomoGrid.wordRow)
    }
}

/// Draws a `TomoWordFlight` every frame, from when it first shows (so a slow first frame of the card doesn't eat the
/// slide): the word at its landing size, scaled down to the bar's at the start. `onLanded` comes at `duration`.
struct TomoWordFlightView: View {
    let flight: TomoWordFlight
    let onLanded: () -> Void
    @State private var start: Date?

    var body: some View {
        let width = ceil((flight.word as NSString).size(withAttributes: [.font: TomoWords.lineFont(flight.toSize)]).width)
        TimelineView(.animation) { timeline in
            let p = TomoWordFlight.progress(at: start.map { timeline.date.timeIntervalSince($0) } ?? 0)
            let x = flight.from.x + (flight.to.x - flight.from.x) * p, y = flight.from.y + (flight.to.y - flight.from.y) * p
            let scale = flight.fromSize / flight.toSize + (1 - flight.fromSize / flight.toSize) * p
            Text(flight.word)
                .font(.system(size: flight.toSize, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1).fixedSize()
                .frame(width: width, alignment: .leading)
                .scaleEffect(scale, anchor: .leading)
                .position(x: x + width / 2, y: y)
        }
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(TomoWordFlight.duration))
            onLanded()
        }
    }
}
