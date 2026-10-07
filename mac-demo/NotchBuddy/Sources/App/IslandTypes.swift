import Foundation
import TomoCore

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

/// What the open island shows: Tomo's card, or the dizzy card after three pokes.
enum IslandView: String, CaseIterable {
    case overview, confused
}

// MARK: - View dimensions

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
}

// MARK: - Constants

enum IslandConst {
    static let notchWidth: CGFloat  = IslandScreenGeometry.fallbackNotchWidth
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640
    static let roundedCorner: CGFloat = 14    // hidden/compact
    static let expandedCorner: CGFloat = 22

    static func layout(_ view: IslandView) -> ViewLayout {
        switch view {
        case .overview: ViewLayout(height: 208, botX: 66, botY: 126, botDiameter: 72)   // +12: Tomo's level bar
        case .confused: ViewLayout(height: 160, botX: 76, botY: nil, botDiameter: 66)
        }
    }
}
