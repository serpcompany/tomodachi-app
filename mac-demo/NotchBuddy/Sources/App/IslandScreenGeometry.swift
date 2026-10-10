import Foundation

/// The island's size on its screen: the physical notch, or on a screen without one, a capsule (#130).
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    /// Without a notch, the resting island is a capsule this size, 4 pt below the top of the screen (`capsuleTop`):
    /// small Tomo on its left, the right side (あそぼ！ or when words are back, and the ring) on its right, as beside a
    /// notch, with the notch's place between them.
    static let capsule = CGSize(width: 300, height: 30)
    static let capsuleTop: CGFloat = 4

    let hasNotch: Bool
    /// The notch, or on a screen without one, the capsule's middle between its two sides, so the resting island
    /// (`islandSize`: the notch and a side on each of it) is the capsule.
    let width: CGFloat
    let height: CGFloat

    init(screenWidth: CGFloat, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            height = safeAreaTop
        } else {
            width = Self.capsule.width - IslandRestingLayout.ear * 2
            height = Self.capsule.height
        }
    }

    /// How far below the top of the screen the island's top edge is: none under a notch (it's glued to it), and
    /// `capsuleTop` for the capsule, whether it rests, peeks or is open.
    static func top(hasNotch: Bool) -> CGFloat { hasNotch ? 0 : capsuleTop }

    /// The island's corner radii, for its mode and height now. Under a notch: square on top (glued to the top of the
    /// screen), rounded below, 14 pt resting and 22 pt open or peeking. Without one, rounded all round: fully while it
    /// rests (half its height, under the pointer too), 22 pt open or peeking.
    static func corners(mode: IslandMode, height: CGFloat, hasNotch: Bool) -> (top: CGFloat, bottom: CGFloat) {
        let open = mode == .expanded || mode == .peek
        if hasNotch { return (0, open ? IslandConst.expandedCorner : IslandConst.roundedCorner) }
        let r = open ? IslandConst.expandedCorner : height / 2
        return (r, r)
    }
}

/// The resting (compact) island: the notch (or the strip on a screen without one) with an ear on each side. Small
/// Tomo sits in the left ear; the right one holds `TomoRestingSide` (あそぼ！ or when words are back, then Tomo's
/// level ring at the right edge), which never reaches under the notch.
struct IslandRestingLayout {
    static let ear: CGFloat = 80
    static let ring: CGFloat = 15
    static let ringInset: CGFloat = 11          // from the island's right edge
    static let ringGap: CGFloat = 6             // between the words and the ring
    static let notchClearance: CGFloat = 3
    /// How much the resting island grows under the pointer (#130), wider and taller, centred under the notch.
    static let hoverGrowth = CGSize(width: 8, height: 4)
    /// The widest the right side's words get; longer ones shrink to fit (あそぼ！ is about 43 pt at 11.5 pt bold).
    static var textWidth: CGFloat { ear - ringInset - ring - ringGap - notchClearance }   // 45

    let width: CGFloat
    let height: CGFloat

    var botDiameter: CGFloat { min(20, max(0, height - 6)) }
    var botCenterY: CGFloat { height / 2 }

    /// The right side's frame in the island: the words, then the ring, centred on the island's height.
    var rightSide: CGRect {
        let w = Self.textWidth + Self.ringGap + Self.ring
        return CGRect(x: width - Self.ringInset - w, y: (height - Self.ring) / 2, width: w, height: Self.ring)
    }
}
