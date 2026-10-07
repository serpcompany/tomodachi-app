import AVFoundation
import Combine
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomodachi on the iPhone (issue #52)
//
// A shell around TomoCore, like the Mac island: it sets TomoGame's closures and draws Tomo. On the iPhone
// the app itself is Tomo's place: opening it is free play, and Tomo never leaves while you're looking.
// The Home Screen widget reads a TomoGlance the shell writes whenever progress changes.
// The same glance drives Tomo's Lock Screen card (a Live Activity, TomoLiveVisit), once the learner said yes to it.
// A new learner's first launch shows the first run over Tomo's screen first (TomoPhoneFirstRun). Reminders (local
// notifications) are TomoReminderCenter's, scheduled from progress.

@main
struct TomodachiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shell = TomoPhoneShell.shared

    init() {
        TomoOnboarding.checkAtLaunch()       // before anything opens the store: a new learner gets the first run (#88)
        TomoReminderCenter.shared.install()  // a tap on a reminder can be why we launched
        TomoLiveVisit.shared.install()      // before anything else: a tap on the card can be why we launched
        // Tomo's voice and peeps are a game's sounds: the Ring/Silent switch mutes them, and they play over the
        // learner's music instead of stopping it (#92).
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    var body: some Scene {
        WindowGroup {
            TomoPhoneHome(shell: shell)   // the play screen and Tomo, Words, Settings as tabs (#90)
                .onAppear {
                    // onChange below only reports changes: on a fresh launch the app can already be active.
                    shell.isActive = scenePhase == .active
                    shell.start()
                }
                .tomoFirstRun(shell)
        }
        .onChange(of: scenePhase) { _, phase in
            shell.isActive = phase == .active
            if phase == .active {
                TomoLiveVisit.shared.endRound()
                TomoSync.shared.fetchSoon()          // the Mac may have played since (#62)
            } else {
                shell.updateWidgets()
            }
            if shell.firstRun == nil { TomoReminderCenter.shared.scheduleSoon() }   // from now: the last time seen
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
    /// The first run, while it's on screen (TomoPhoneFirstRun). Tomo's game waits until it's done.
    @Published private(set) var firstRun: TomoOnboarding?
    private var started = false
    private var watch: AnyCancellable?
    private var cardWatch: AnyCancellable?
    private var hold: Timer?
    private var lastGlance: TomoGlance?

    private init() {
        guard let kind = TomoOnboarding.atLaunch else { return }
        // TOMO_ONBOARDING=<step> opens it at a step (testing), like on the Mac.
        let start = ProcessInfo.processInfo.environment["TOMO_ONBOARDING"].flatMap(TomoOnboarding.Step.init(rawValue:))
        let model = TomoOnboarding(kind: kind, shell: .phone, start: start)
        model.onFinish = { [weak self] in self?.endFirstRun() }
        firstRun = model
    }

    /// The Lock Screen card may show: the learner said yes (or had it before the first run asked), and the first run
    /// is over.
    var cardAllowed: Bool { firstRun == nil && TomoReminderCenter.shared.settings.lockScreen }

    func start() {
        guard !started else { return }
        started = true
        let game = TomoGame.shared
        game.openIsland = {}                        // the app is Tomo's screen: nothing to open or close
        game.closeIsland = {}
        // On screen (after the first run), or playing a round on the Lock Screen card (TomoLiveVisit).
        game.isIslandOpen = { [weak self] in self?.isTomoOnScreen == true || TomoLiveVisit.shared.isPlaying }
        game.isPointerInside = { [weak self] in self?.isTomoOnScreen == true || TomoLiveVisit.shared.isPlaying }
        game.onBotState = { [weak self] in self?.botState = $0 }
        TomoSounds.shared.listen()
        TomoSync.shared.registerForPushes = { UIApplication.shared.registerForRemoteNotifications() }
        game.start()                                // free play starts when the app becomes active
        watch = game.$progressVersion.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateWidgets() }   // after the change has landed
        }
        // The Lock Screen card follows its setting (the first run, Settings): it starts or ends.
        cardWatch = TomoReminderCenter.shared.$settings.map(\.lockScreen).removeDuplicates().dropFirst()
            .sink { _ in DispatchQueue.main.async { TomoLiveVisit.shared.refresh() } }
        if firstRun != nil {
            // Tomo waits while the first run is on screen: its visit clock is held, or a visit would start under it.
            hold = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                MainActor.assumeIsolated { TomoGame.shared.rescheduleVisits() }
            }
        } else {
            TomoReminderCenter.shared.start()
        }
    }

    private var isTomoOnScreen: Bool { isActive && firstRun == nil }

    /// The first run is done: its choices are saved (TomoOnboarding.finish), the saved Tomo comes back with the word
    /// just learned, Tomo asks its next word, reminders are scheduled, and the Lock Screen card starts if wanted.
    private func endFirstRun() {
        hold?.invalidate()
        hold = nil
        withAnimation(.easeInOut(duration: 0.45)) { firstRun = nil }
        TomoGame.shared.start()
        TomoReminderCenter.shared.start()
        lastGlance = nil
        updateWidgets()
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
