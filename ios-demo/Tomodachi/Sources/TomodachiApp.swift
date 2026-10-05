import Combine
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomodachi on the iPhone (issue #52)
//
// A shell around TomoCore, like the Mac island: it sets TomoGame's closures and draws Tomo. On the iPhone
// the app itself is Tomo's place: opening it is free play, and Tomo never leaves while you're looking.
// The Home Screen widget reads a TomoGlance the shell writes whenever progress changes.
// Lock Screen visits (Live Activities) come next.

@main
struct TomodachiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shell = TomoPhoneShell.shared

    var body: some Scene {
        WindowGroup {
            TomoPhoneView(shell: shell)
                .onAppear { shell.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            shell.isActive = phase == .active
            if phase == .background { shell.updateWidgets() }
        }
    }
}

@MainActor
final class TomoPhoneShell: ObservableObject {
    static let shared = TomoPhoneShell()

    /// What Tomo is doing (asking, thinking, right, wrong…), passed to its TomoChickView.
    @Published private(set) var botState: BotState = .idle
    /// The app is on screen: Tomo is "open", and a visit doesn't time out (you're looking at it).
    var isActive = false
    private var started = false
    private var watch: AnyCancellable?
    private var lastGlance: TomoGlance?

    func start() {
        guard !started else { return }
        started = true
        let game = TomoGame.shared
        game.openIsland = {}                        // the app is Tomo's screen: nothing to open or close
        game.closeIsland = {}
        game.isIslandOpen = { [weak self] in self?.isActive ?? false }
        game.isPointerInside = { [weak self] in self?.isActive ?? false }
        game.onBotState = { [weak self] in self?.botState = $0 }
        TomoSounds.shared.listen()
        game.start()                                // free play starts when the app becomes active
        watch = game.$progressVersion.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateWidgets() }   // after the change has landed
        }
    }

    /// Writes Tomo's glance for the widget and reloads it, when anything it shows changed.
    func updateWidgets() {
        var glance = TomoGame.shared.glance
        glance.updated = lastGlance?.updated ?? glance.updated
        guard glance != lastGlance else { return }
        glance.updated = Date()
        glance.save()
        lastGlance = glance
        WidgetCenter.shared.reloadTimelines(ofKind: "TomoWidget")
    }
}
