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

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    var hasNotch = true

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var mouseInIsland: Bool = false   // set by IslandWindowController every frame
    /// Tomo's help panel below the card (0 = closed). The expanded island grows by this much.
    @Published var helpPanelHeight: CGFloat = 0

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
