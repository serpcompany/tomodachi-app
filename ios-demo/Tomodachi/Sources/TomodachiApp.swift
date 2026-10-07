import Combine
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomodachi on the iPhone (issue #52)
//
// A shell around TomoCore, like the Mac island: it sets TomoGame's closures and draws Tomo. On the iPhone
// the app itself is Tomo's place: opening it is free play, and Tomo never leaves while you're looking.
// The Home Screen widget reads a TomoGlance the shell writes whenever progress changes.
// The same glance drives Tomo's Lock Screen card (a Live Activity, TomoLiveVisit).

@main
struct TomodachiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shell = TomoPhoneShell.shared

    init() {
        TomoLiveVisit.shared.install()      // before anything else: a tap on the card can be why we launched
    }

    var body: some Scene {
        WindowGroup {
            TomoPhoneView(shell: shell)
                .onAppear {
                    // onChange below only reports changes: on a fresh launch the app can already be active.
                    shell.isActive = scenePhase == .active
                    shell.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            shell.isActive = phase == .active
            if phase == .active {
                TomoLiveVisit.shared.endRound()
                TomoSync.shared.fetchSoon()          // the Mac may have played since (#62)
            } else {
                shell.updateWidgets()
            }
        }
    }
}

@MainActor
final class TomoPhoneShell: ObservableObject {
    static let shared = TomoPhoneShell()

    /// What Tomo is doing (asking, thinking, right, wrong…), passed to its TomoBlobView.
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
        // On screen, or playing a round on the Lock Screen card (TomoLiveVisit).
        game.isIslandOpen = { [weak self] in self?.isActive == true || TomoLiveVisit.shared.isPlaying }
        game.isPointerInside = { [weak self] in self?.isActive == true || TomoLiveVisit.shared.isPlaying }
        game.onBotState = { [weak self] in self?.botState = $0 }
        TomoSounds.shared.listen()
        TomoSync.shared.registerForPushes = { UIApplication.shared.registerForRemoteNotifications() }
        game.start()                                // free play starts when the app becomes active
        watch = game.$progressVersion.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateWidgets() }   // after the change has landed
        }
    }

    /// Tomo right now, for the widgets and the Lock Screen card.
    func currentGlance() -> TomoGlance {
        var glance = TomoGame.shared.glance
        // Testing (TOMO_CARD_COUNTDOWN=<seconds>): nothing waiting, next words in that many seconds.
        if let secs = ProcessInfo.processInfo.environment["TOMO_CARD_COUNTDOWN"].flatMap(Double.init) {
            glance.waiting = false
            glance.status = TomoLanguages.shared.learner("glance.done")
            glance.nextDue = (lastGlance?.nextDue).map { $0 } ?? Date().addingTimeInterval(secs)
        }
        glance.updated = lastGlance?.updated ?? glance.updated
        return glance
    }

    /// Writes Tomo's glance for the widget and reloads it, when anything it shows changed.
    func updateWidgets() {
        var glance = currentGlance()
        guard glance != lastGlance else { return }
        glance.updated = Date()
        glance.save()
        lastGlance = glance
        WidgetCenter.shared.reloadTimelines(ofKind: "TomoWidget")
        TomoLiveVisit.shared.show(glance)
    }
}
