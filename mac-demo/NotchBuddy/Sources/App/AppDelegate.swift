import AppKit
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

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Tomo", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(withTitle: "Drop in now", action: #selector(dropInNow), keyEquivalent: "d")
        menu.addItem(withTitle: "Restart demo", action: #selector(restartDemo), keyEquivalent: "r")
        menu.addItem(withTitle: "Skip to 3さい (talking)", action: #selector(skipToTalking), keyEquivalent: "3")
        menu.addItem(withTitle: "AI provider…", action: #selector(openAISettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(languageMenu(title: "Learning", items: TomoLanguages.shared.targets.map {
            ($0.id, "\($0.name(TomoLanguages.shared.learner.id)) (\($0.nativeName))\($0.reviewedByNativeSpeaker ? "" : " · draft")")
        }, selected: TomoLanguages.shared.target.id, action: #selector(pickTarget(_:))))
        menu.addItem(languageMenu(title: "I speak", items: TomoLanguages.shared.learners.map { ($0.id, $0.name) },
                                  selected: TomoLanguages.shared.learner.id, action: #selector(pickLearner(_:))))
        sfxItem = menu.addItem(withTitle: "Coucou sound effects (private use only)",
                               action: #selector(toggleSfx), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.fsm.openedExternally()
        islandController?.expand(to: .overview)
    }

    @objc private func restartDemo() {
        TomoGame.shared.restart()
    }

    private var aiWindow: NSWindow?

    // MARK: - Languages (see docs/languages.md)

    private func languageMenu(title: String, items: [(id: String, title: String)], selected: String, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        for item in items {
            let mi = NSMenuItem(title: item.title, action: action, keyEquivalent: "")
            mi.representedObject = item.id
            mi.state = item.id == selected ? .on : .off
            sub.addItem(mi)
        }
        parent.submenu = sub
        return parent
    }

    private func check(_ sender: NSMenuItem) {
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    @objc private func pickTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        check(sender)
        TomoLanguages.shared.select(target: id)
        TomoGame.shared.restart()   // one Tomo per target language; progress isn't saved yet
    }

    @objc private func pickLearner(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        check(sender)
        TomoLanguages.shared.select(learner: id)
    }

    @objc private func openAISettings() {
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if aiWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "Tomo — AI provider"
            win.contentView = NSHostingView(rootView: TomoAISettingsView())
            win.isReleasedWhenClosed = false
            aiWindow = win
        }
        aiWindow.map(placeBelowIsland)
        aiWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func skipToTalking() {
        TomoGame.shared.jumpToChat()
    }

    @objc private func dropInNow() {
        TomoGame.shared.dropIn(force: true)
    }

    // Coucou's sounds are not covered by its MIT license (see LICENSE-ASSETS.md): off by default.
    private var sfxItem: NSMenuItem?

    @objc private func toggleSfx() {
        SoundEngine.shared.enabled.toggle()
        sfxItem?.state = SoundEngine.shared.enabled ? .on : .off
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Coucou"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 420, height: 320)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
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
            }
        }
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        SoundEngine.shared.enabled = false
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
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}
