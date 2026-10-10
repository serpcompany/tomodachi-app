import SwiftUI

// MARK: - The experience bar, on every screen (TomoProgress.levelProgress)
//
// Two parts: the track, which the level's best words fill stage by stage, and the goal, the last tenth
// (TomoProgress.goalShare), set apart, which fills only when the level is done. So the bar never looks full before
// the level is done, even when the track is. A word that slipped keeps its part of the track (the bar never moves
// back), drawn pale until it's answered right again (`standing`). The shells pick the colors and the height.

public struct TomoGrowthBar: View {
    public var progress: Double          // TomoGame.levelProgress
    public var standing: Double          // TomoGame.levelStanding (≤ progress)
    public var dimmed: Bool              // practice: nothing done now moves it
    public var colors: [Color]           // the fill, left to right across the whole bar
    public var empty: Color
    public var outline: Color            // around the goal until it fills
    public var gap: CGFloat

    public init(progress: Double, standing: Double, dimmed: Bool = false, colors: [Color],
                empty: Color = Color.white.opacity(0.1), outline: Color = Color.white.opacity(0.22), gap: CGFloat = 3) {
        self.progress = progress; self.standing = standing; self.dimmed = dimmed
        self.colors = colors; self.empty = empty; self.outline = outline; self.gap = gap
    }

    /// The track's width in a bar `width` wide: all of it but the goal and the gap before it.
    public static func trackWidth(_ width: CGFloat, gap: CGFloat = 3) -> CGFloat {
        max(0, width * (1 - TomoProgress.goalShare) - gap / 2)
    }

    /// Where the fill ends in a bar `width` wide at `progress`: along the track, and the whole bar once the level is done
    /// (the goal filled). A shell that sends something into the bar aims here.
    public static func filledWidth(_ width: CGFloat, progress: Double, gap: CGFloat = 3) -> CGFloat {
        progress >= 1 ? width : trackWidth(width, gap: gap) * min(max(progress, 0) / (1 - TomoProgress.goalShare), 1)
    }

    public var body: some View {
        GeometryReader { g in
            let w = g.size.width, mark = 1 - TomoProgress.goalShare
            let track = Self.trackWidth(w, gap: gap), goal = max(0, w - track - gap)
            let done = progress >= 1
            let reached = track * min(max(progress, 0) / mark, 1)
            let now = track * min(max(min(standing, progress), 0) / mark, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(empty).frame(width: track)
                Capsule().fill(empty)
                    .overlay(Capsule().strokeBorder(done ? .clear : outline, lineWidth: 1))
                    .frame(width: goal).offset(x: track + gap)
                // One gradient across the whole bar, showing through what's filled.
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: w)
                    .mask(alignment: .leading) {
                        ZStack(alignment: .leading) {
                            Capsule().frame(width: reached).opacity(0.35)     // earned; a slipped word comes back here
                            Capsule().frame(width: now)
                            Capsule().frame(width: goal).offset(x: track + gap).opacity(done ? 1 : 0)
                        }
                    }
                    .shadow(color: (colors.last ?? .green).opacity(done ? 0.8 : 0), radius: 4)
                    .opacity(dimmed ? 0.3 : 1)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: standing)
        .animation(.easeInOut(duration: 0.4), value: dimmed)
    }
}
