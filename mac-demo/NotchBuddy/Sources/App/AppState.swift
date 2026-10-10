import Foundation
import SwiftUI
import Combine
import TomoCore

/// What the island shows and where the pointer is. Tomo's own state lives in TomoGame; the island only
/// mirrors what it needs to draw (`tomoState`, set through `TomoGame.onBotState`).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview

    /// Tomo's state from the game (asking, thinking, right, wrong…).
    @Published var tomoState: BotState = .idle
    /// Overrides Tomo's state for a moment (dizzy after three pokes).
    @Published var stateOverride: BotState? = nil

    // The island's screen: its notch (or none) and width. IslandWindowController sets them at launch and
    // whenever displays change; the island resizes to match.
    @Published var notchWidth:  CGFloat = IslandConst.notchWidth
    @Published var notchHeight: CGFloat = IslandConst.notchHeight
    @Published var hasNotch = true
    var screenWidth: CGFloat = 1512

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var mouseInIsland: Bool = false   // set by IslandWindowController every frame
    /// Tomo's help panel below the card (0 = closed). The expanded island grows by this much.
    @Published var helpPanelHeight: CGFloat = 0
    /// A peek's word on its way into the card as the peek opens (TomoWordFlight); the card's own word waits for it.
    @Published var wordFlight: TomoWordFlight?
    /// How many times Tomo came out on its own (a visit, as its card or its peek): Tomo drips in from the notch for each
    /// (TomoCharacterView). A click on small Tomo isn't one: it grows into the card.
    @Published var arrivals = 0
    /// The pointer came onto the resting island (and nothing changed under it since): the island grows a little
    /// (`islandSize`'s `grown`), not under Reduce Motion. IslandWindowController keeps it, with the click area in step.
    @Published var restingHover = false
    /// The card or the peek is folding, and waits while Tomo is pulled up into the notch (about 0.45 s): for the game
    /// it's closed already (`TomoGame.isIslandOpen`).
    @Published var leaving = false

    // Sound enabled: Tomo's switch (TomoGame.soundEnabled, persisted there)
    var soundEnabled: Bool {
        get { TomoGame.shared.soundEnabled }
        set { TomoGame.shared.soundEnabled = newValue }
    }

    private init() {}

    var effectiveState: BotState {
        stateOverride ?? tomoState
    }
}
