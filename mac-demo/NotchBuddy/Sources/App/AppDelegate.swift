import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        TomoIconRenderer.renderIfRequested()
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Tomodachi")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Tomodachi"
        button.image?.isTemplate = true
        rebuildMenu()
        // Menu text follows the interface language, and "Skip to talking" shows the target's age label.
        languageWatch = TomoLanguages.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.settingsWindow?.title = TomoLanguages.shared.learner("menu.settingsTitle")
            }
    }

    private var languageWatch: AnyCancellable?

    private func rebuildMenu() {
        let ui = TomoLanguages.shared.learner
        let menu = NSMenu()
        menu.addItem(withTitle: ui("menu.open"), action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(withTitle: ui("menu.dropIn"), action: #selector(dropInNow), keyEquivalent: "d")
        menu.addItem(withTitle: ui("menu.talk", ["age": TomoLanguages.shared.target.ageLabel(TomoGame.chatStage)]),
                     action: #selector(skipToTalking), keyEquivalent: "3")
        menu.addItem(withTitle: ui("menu.restart"), action: #selector(restartDemo), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: ui("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: ui("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.fsm.openedExternally()
        islandController?.expand(to: .overview)
    }

    @objc private func restartDemo() {
        TomoStartOver.confirm()
    }

    @objc private func skipToTalking() {
        TomoGame.shared.jumpToChat()
    }

    @objc private func dropInNow() {
        TomoGame.shared.dropIn(force: true)
    }

    private var settingsWindow: NSWindow?

    /// Settings: General (languages, visits, voice), AI provider, About.
    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if settingsWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = TomoLanguages.shared.learner("menu.settingsTitle")
            let host = NSHostingView(rootView: TomoSettingsView())
            host.sizingOptions = [.preferredContentSize]
            win.contentView = host
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow.map(placeBelowIsland)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
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
                // TOMO_OPEN_SETTINGS=1 also captures the Settings window
                if let sv = self?.settingsWindow?.contentView, self?.settingsWindow?.isVisible == true,
                   let srep = sv.bitmapImageRepForCachingDisplay(in: sv.bounds) {
                    sv.cacheDisplay(in: sv.bounds, to: srep)
                    let surl = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "settings-%03d.png", n))
                    try? srep.representation(using: .png, properties: [:])?.write(to: surl)
                }
            }
        }
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        TomoSounds.shared.listen()           // Tomo's own synthesized sound effects
        // Tomo visits on its own (see DropIn); the first visit is right at launch.
        islandController?.fsm.homeToPetitDelay = 45
        // Between visits Tomo hangs out small beside the notch (click to play anytime): never auto-hide.
        islandController?.fsm.petitToHiddenDelay = 365 * 24 * 3600
        let game = TomoGame.shared
        game.openIsland = { [weak self] in
            guard let c = self?.islandController else { return }
            c.fsm.openedExternally()
            c.expand(to: .overview)
        }
        game.closeIsland = { [weak self] in self?.islandController?.collapse() }
        game.isIslandOpen = { AppState.shared.mode == .expanded }
        game.focusInput = { [weak self] in self?.islandController?.window?.makeKey() }
        game.start()
        game.dropIn(force: true)
        startDebugSnapshots()
        if ProcessInfo.processInfo.environment["TOMO_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openSettings() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}
