import SwiftUI

// MARK: - The coloured light that tells the moment (#137, effect 3)

/// What the light says right now. Tomo's card and the island wash in it, fading in as the moment starts and out as it
/// ends: green for a win, blue for practice, gold for a level-up or a birthday, and amber while Tomo waits to play.
/// Never red: a miss and no score get no light, because Tomo misses you; it never keeps score (concepts.md). The rules
/// are pure, so every shell lights the same moments; where the light shows and how it moves is the shell's (the Mac's
/// card and island: `TomoMomentLight`).
public enum TomoMoment: String, CaseIterable, Sendable {
    /// An answer that counted (the Win badge).
    case win
    /// Right, but nothing counted (the Practice badge): a smaller win, never progress.
    case practice
    /// A level-up or a birthday (TomoPhase.leveledUp, .grew).
    case grown
    /// Something counts and Tomo wants to play: the amber of small Tomo's call glow and the countdown line.
    case waiting

    /// Its colour, as hex. Every one is a gentle colour, never a red (checked: `selfTest`).
    public var hex: String {
        switch self {
        case .win: "#34D399"        // the Win badge's green
        case .practice: "#5B9BFF"   // a clear blue, apart from the Win's green
        case .grown: "#FFC447"      // gold
        case .waiting: "#F2B04A"    // TomoBlob.Palette.amber
        }
    }

    public var color: Color { Color(hex: hex) }

    /// How brightly it washes, 0…1: practice is a smaller win, and waiting, which can last, stays soft.
    public var strength: Double {
        switch self {
        case .win, .grown: 1
        case .practice: 0.72
        case .waiting: 0.7
        }
    }

    /// A moment that just happened ripples out from Tomo as it starts; waiting only glows.
    public var ripples: Bool { self != .waiting }

    /// The open card's light, for where its round is. A counted right answer is a win, an uncounted one practice, a
    /// level-up or a birthday gold. Asking, Tomo thinking, a miss, no score and resting have none. In a typed
    /// conversation (`chat`) the result stays up while Tomo asks again, so its outcome decides.
    public static func card(phase: TomoPhase, outcome: TomoOutcome?, chat: Bool = false) -> TomoMoment? {
        switch phase {
        case .leveledUp, .grew: return .grown
        case .thinking, .resting, .wrong: return nil
        case .right: return outcome == .win(counted: false) ? .practice : .win
        case .asking:
            guard chat, case .win(let counted) = outcome else { return nil }
            return counted ? .win : .practice
        }
    }

    /// The light while Tomo is small beside the notch or peeking from it: amber while something counts (the rule
    /// あそぼ！ and a visit use), else none. The mood ladder's tints (pouty pink, lonely cool blue; #130) join here as
    /// cases when it lands, decided from Tomo's mood before the amber.
    public static func resting(somethingCounts: Bool) -> TomoMoment? {
        somethingCounts ? .waiting : nil
    }

    /// Whether a colour reads as red: a hue within 20° of pure red, strongly saturated (the Miss badge's #F4505E is
    /// one). A soft pink stays allowed.
    public static func isRed(hex: String) -> Bool {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b)
        guard hi > 0, hi - lo > 0, hi == r else { return false }
        let hue = (60 * (g - b) / (hi - lo) + 360).truncatingRemainder(dividingBy: 360)
        return (hue < 20 || hue > 340) && (hi - lo) / hi > 0.5
    }

    /// The light's rules, checked by TOMO_SELFTEST (run by the Mac's TomoIslandSelfTest).
    public static func selfTest(_ check: (Bool, String) -> Void) {
        check(card(phase: .right, outcome: .win(counted: true)) == .win
              && card(phase: .right, outcome: .win(counted: false)) == .practice,
              "the card's light: a counted answer is a win (green), an uncounted one practice (blue)")
        check(card(phase: .leveledUp, outcome: .win(counted: true)) == .grown && card(phase: .grew, outcome: nil) == .grown,
              "a level-up and a birthday light gold")
        check([TomoPhase.asking, .thinking, .resting, .wrong("x")].allSatisfy { card(phase: $0, outcome: .loss) == nil }
              && card(phase: .asking, outcome: nil) == nil && card(phase: .asking, outcome: .win(counted: true)) == nil,
              "asking, thinking, a miss and resting have no light; a picture round's next question drops its win's")
        check(card(phase: .asking, outcome: .win(counted: true), chat: true) == .win
              && card(phase: .asking, outcome: .win(counted: false), chat: true) == .practice
              && card(phase: .asking, outcome: .loss, chat: true) == nil
              && card(phase: .asking, outcome: .neutral("help"), chat: true) == nil,
              "talking: a win or practice lights while Tomo asks again; a miss and no score don't")
        check(resting(somethingCounts: true) == .waiting && resting(somethingCounts: false) == nil,
              "small Tomo and the peek light amber while something counts, and nothing when nothing does")
        check(allCases.allSatisfy { !isRed(hex: $0.hex) } && isRed(hex: "#F4505E") && !isRed(hex: "#FF8FB8"),
              "never red: no moment's colour is a red (the Miss badge's would be; the mood ladder's pink isn't)")
        check(practice.strength < win.strength && allCases.allSatisfy { (0...1).contains($0.strength) }
              && allCases.filter(\.ripples) == [.win, .practice, .grown],
              "practice washes softer than a win, and only what just happened ripples out from Tomo")
    }
}
