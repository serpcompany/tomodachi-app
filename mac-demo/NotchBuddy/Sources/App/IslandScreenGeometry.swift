import Foundation

/// Resting island dimensions, using a physical notch only when the screen has one.
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat) {
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
            width = Self.noNotchWidth
            height = min(Self.noNotchHeight, menuBarHeight)
        }
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
