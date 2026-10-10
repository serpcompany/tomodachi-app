import AppKit
import SwiftUI
import TomoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TomoHeadless.start()   // TOMO_HEADLESS: test runs stay invisible and silent
        // Every live Tomo follows Reduce Motion (Accessibility → Display). A test run ignores this Mac's setting, so its
        // snapshots don't depend on it: TOMO_REDUCE_MOTION=1 turns it on (TomoMotion).
        TomoMotion.shared.follow(NSWorkspace.shared.notificationCenter,
                                 NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            !TomoHeadless.isOn && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        NSApp.setActivationPolicy(.accessory)
        TomoIconRenderer.renderIfRequested()   // the self-test and the renders quit here
        // A regular app with a Dock icon and a main menu (decisions.md). Info.plist starts it as an agent
        // (LSUIElement) only so a test run (TOMO_HEADLESS) never shows a Dock icon, not even for a moment.
        // Nothing here activates it: launched at login, or by Tomo's visits, it stays in the background.
        if !TomoHeadless.isOn { NSApp.setActivationPolicy(.regular) }
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = !TomoHeadless.isOn
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Tomodachi")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Tomodachi"
        button.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        TomoMenus.fill(menu)   // filled again each time it opens (TomoMenus), so it follows the interface language
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        TomoTestingTools.menuOpening()   // ⌥-click shows the testing tools
        TomoMenus.fill(menu)
    }

    // MARK: - Actions

    /// The learner opened Tomo on purpose (the menus, the window's Play with Tomo): free play, and Esc closes it.
    private func openIsland() {
        islandController?.open()
        islandController?.takeKeyboard()   // opened on purpose: Esc closes it
    }

    /// Opening Tomodachi again from Finder, Launchpad or the Dock while it runs brings up its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TomoAppWindow.open()
        return false
    }

    // MARK: - Debug snapshots (TOMO_SNAPSHOT_DIR=/path): PNG of the island panel every second

    private var snapshotTimer: Timer?

    private func startDebugSnapshots() {
        guard let dir = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_DIR"] else { return }
        var n = 0
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let view = self?.islandController?.window?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                n += 1
                let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "snap-%03d.png", n))
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                // Popovers (e.g. the Explain panel) live in their own windows
                for (i, w) in NSApp.windows.enumerated()
                where w.isVisible && String(describing: type(of: w)).contains("Popover") {
                    guard let pv = w.contentView, let prep = pv.bitmapImageRepForCachingDisplay(in: pv.bounds) else { continue }
                    pv.cacheDisplay(in: pv.bounds, to: prep)
                    let purl = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "popover%d-%03d.png", i, n))
                    try? prep.representation(using: .png, properties: [:])?.write(to: purl)
                }
            }
        }
    }

    // MARK: - Island setup

    private func setupIsland() {
        let firstRun = TomoOnboarding.checkAtLaunch()   // before anything opens the store (#88)
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        TomoSounds.shared.listen()           // Tomo's own synthesized sound effects
        // Tomo visits on its own (see DropIn); the first visit is right at launch.
        islandController?.fsm.homeToPetitDelay = 45
        // Between visits Tomo hangs out small beside the notch (click to play anytime): never auto-hide.
        islandController?.fsm.petitToHiddenDelay = 365 * 24 * 3600
        let game = TomoGame.shared
        game.openIsland = { [weak self] in self?.islandController?.open() }
        game.closeIsland = { [weak self] in self?.islandController?.collapse() }
        game.isIslandOpen = { AppState.shared.mode == .expanded }
        game.focusInput = { [weak self] in self?.islandController?.window?.makeKey() }
        game.isPointerInside = { AppState.shared.mouseInIsland }
        game.onBotState = { AppState.shared.tomoState = $0 }
        game.onHelpChange = { AppState.shared.helpPanelHeight = $0 == nil ? 0 : TomoGrid.helpHeight }
        // "Wait while you're typing": CGEventSource's idle times need no permission (checked on macOS 27 from an app
        // with neither Accessibility nor Input Monitoring: the key-press time was real, apart from the mouse's).
        game.secondsSinceInput = { typing in
            let src = CGEventSourceStateID.combinedSessionState
            if typing { return CGEventSource.secondsSinceLastEventType(src, eventType: .keyDown) }
            let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
            return types.map { CGEventSource.secondsSinceLastEventType(src, eventType: $0) }.min() ?? 0
        }
        TomoSync.shared.registerForPushes = { NSApplication.shared.registerForRemoteNotifications() }
        game.start()
        if ProcessInfo.processInfo.environment["TOMO_ONBOARDING"] == "preview" {   // the Testing menu's preview, for snapshots
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { TomoOnboardingWindow.preview() }
        } else if let firstRun {
            TomoOnboardingWindow.show(firstRun)
        } else {
            game.launchVisit()   // none in quiet hours
        }
        startDebugSnapshots()   // the Tomodachi window captures itself (TomoAppWindow)
        // TOMO_GROW=step|level|birthday: the testing menu's Grow, 3 s after launch (for snapshots).
        if let how = ProcessInfo.processInfo.environment["TOMO_GROW"].flatMap(TomoGame.TestGrowth.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { TomoGame.shared.testGrow(how) }
        }
        TomoMenus.openIsland = { [weak self] in self?.openIsland() }
        TomoMenus.takeKeyboard = { [weak self] in self?.islandController?.takeKeyboard() }
        TomoAppWindow.openIfRequested()
        TomoMenus.dumpIfRequested()
    }
}
