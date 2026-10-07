import AppKit
import Combine
import SwiftUI
import TomoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TomoHeadless.start()   // TOMO_HEADLESS: test runs stay invisible and silent
        NSApp.setActivationPolicy(.accessory)
        TomoIconRenderer.renderIfRequested()
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
        fillMenu(menu)
        // The menu is filled again each time it opens, so its text follows the interface language.
        languageWatch = TomoLanguages.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsWindow?.title = TomoLanguages.shared.learner("menu.settingsTitle")
            }
    }

    private var languageWatch: AnyCancellable?

    func menuNeedsUpdate(_ menu: NSMenu) {
        TomoTestingTools.shared.menuOpening()   // ⌥-click shows the testing tools
        fillMenu(menu)
    }

    private func fillMenu(_ menu: NSMenu) {
        let ui = TomoLanguages.shared.learner
        menu.removeAllItems()
        menu.addItem(withTitle: ui("menu.open"), action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(withTitle: ui("menu.dropIn"), action: #selector(dropInNow), keyEquivalent: "d")
        menu.addItem(withTitle: ui("menu.words"), action: #selector(openWords), keyEquivalent: "w")
        menu.addItem(withTitle: ui("menu.restart"), action: #selector(restartDemo), keyEquivalent: "r")
        if TomoTestingTools.shared.shown {
            menu.addItem(.separator())
            menu.addItem(withTitle: ui("menu.talk", ["age": TomoLanguages.shared.target.ageLabel(TomoGame.chatStage)]),
                         action: #selector(skipToTalking), keyEquivalent: "3")
            menu.addItem(withTitle: ui("menu.growStep"), action: #selector(growStep), keyEquivalent: "g")
            menu.addItem(withTitle: ui("menu.growLevel"), action: #selector(growLevel), keyEquivalent: "l")
            menu.addItem(withTitle: ui("menu.growBirthday"), action: #selector(growBirthday), keyEquivalent: "b")
            if TomoGame.shared.isScratch {
                menu.addItem(withTitle: ui("settings.backToTomo"), action: #selector(backToMyTomo), keyEquivalent: "")
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: ui("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: ui("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.fsm.openedExternally()
        islandController?.expand(to: .overview)
        islandController?.takeKeyboard()   // opened on purpose: Esc closes it
    }

    @objc private func openWords() {
        TomoSettingsNav.open(.words)
    }

    @objc private func restartDemo() {
        TomoStartOver.confirm()
    }

    @objc private func skipToTalking() {
        TomoGame.shared.jumpToChat()
    }

    // Testing: grow without waiting, on a copy in memory (TomoGame.testGrow); the card opens to show it.
    @objc private func growStep() { openIsland(); TomoGame.shared.testGrow(.step) }
    @objc private func growLevel() { openIsland(); TomoGame.shared.testGrow(.level) }
    @objc private func growBirthday() { openIsland(); TomoGame.shared.testGrow(.birthday) }
    @objc private func backToMyTomo() { TomoGame.shared.reload() }

    @objc private func dropInNow() {
        TomoGame.shared.dropIn(force: true)
        islandController?.takeKeyboard()
    }

    private var settingsWindow: NSWindow?

    /// Settings, laid out like System Settings: a sidebar of pages (TomoSettingsView). TomoSettingsNav picks the page.
    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if settingsWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
            win.title = TomoLanguages.shared.learner("menu.settingsTitle")
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.minSize = NSSize(width: 720, height: 500)
            win.contentView = NSHostingView(rootView: TomoSettingsView())
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow.map(placeBelowIsland)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the island's screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = islandController?.window?.screen ?? IslandWindowController.islandScreen() ?? win.screen
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
        let firstRun = TomoOnboarding.checkAtLaunch()   // before anything opens the store (#88)
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
        if let firstRun { TomoOnboardingWindow.show(firstRun) } else { game.dropIn(force: true) }
        startDebugSnapshots()
        // TOMO_GROW=step|level|birthday: the testing menu's Grow, 3 s after launch (for snapshots).
        if let how = ProcessInfo.processInfo.environment["TOMO_GROW"].flatMap(TomoGame.TestGrowth.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { TomoGame.shared.testGrow(how) }
        }
        if ProcessInfo.processInfo.environment["TOMO_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openSettings() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}
