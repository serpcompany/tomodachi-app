import AppKit
import Combine
import SwiftUI
import TomoCore

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandStateMachine()

    private var wasInIsland = false
    private var frameTimer: Timer?
    private var keyMonitor: Any?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Bot-head hover (love emote)
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var lastLoveTime: Double = 0
    private var botHoverStartPos: CGPoint = .zero

    private var pendingIslandClick = false   // any island click → expand on mouseUp

    // Notch real dimensions (set by place(on:))
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight
    private var hasNotch = true

    nonisolated static let panelSize = NSSize(width: 720, height: 560)   // room for Tomo's help panel below the card

    convenience init() {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.init(window: panel)
        self.islandPanel = panel
        if let screen = Self.islandScreen() { place(on: screen) }
        setupPanel()
    }

    private func setupPanel() {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // The hosting view sits in a plain container, so SwiftUI's sizing never resizes the panel.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        container.addSubview(hosting)
        panel.contentView = container

        startPolling()
        startKeyMonitor()
        followScreens()
        wireFSM()
    }

    // MARK: - Screens (the notch one if there is one; it can change while Tomo runs)

    /// Re-places the island whenever displays change: a monitor plugged in or out, the lid closed or opened,
    /// a resolution change, or waking from sleep. It was picked once at launch, and stranded after any of those.
    private func followScreens() {
        let replace: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, let screen = Self.islandScreen() else { return }
                self.place(on: screen)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main, using: replace)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main, using: replace)
    }

    /// Puts the island at the top centre of `screen`, sized for its notch (or for none).
    private func place(on screen: NSScreen) {
        let geometry = Self.screenGeometry(for: screen)
        notchW = geometry.width
        notchH = geometry.height
        hasNotch = geometry.hasNotch
        islandPanel.notchWidth = notchW
        islandPanel.notchHeight = notchH
        islandPanel.setFrame(Self.panelFrame(on: screen.frame), display: true)
        // AppState drives the SwiftUI island; it resizes when these change.
        if state.notchWidth != notchW { state.notchWidth = notchW }
        if state.notchHeight != notchH { state.notchHeight = notchH }
        if state.hasNotch != hasNotch { state.hasNotch = hasNotch }
        if state.screenWidth != screen.frame.width { state.screenWidth = screen.frame.width }
    }

    /// The screen Tomo lives on: the one with a notch, else the main display (the one with the menu bar).
    static func islandScreen() -> NSScreen? {
        pickScreen(NSScreen.screens.map { $0.safeAreaInsets.top > 0 }).map { NSScreen.screens[$0] }
    }

    /// Which of the screens (true = it has a notch) Tomo lives on: the first notch, else the first screen.
    nonisolated static func pickScreen(_ hasNotch: [Bool]) -> Int? {
        hasNotch.firstIndex(of: true) ?? (hasNotch.isEmpty ? nil : 0)
    }

    /// The panel's frame: glued to the top of the screen, centred.
    nonisolated static func panelFrame(on screen: NSRect) -> NSRect {
        NSRect(x: screen.midX - panelSize.width / 2, y: screen.maxY - panelSize.height,
               width: panelSize.width, height: panelSize.height)
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .hidden { SoundEngine.shared.play("peek") }
                self.setMode(.compact)
                // Start the hide timer if the mouse is not currently over the island
                if !self.wasInIsland { self.fsm.mouseLeft() }

            case .home:
                self.expand(to: .overview)
                // Start the collapse timer if the mouse is not hovering
                if !self.wasInIsland { self.fsm.mouseLeft() }
            }
        }
    }

    // MARK: - 60 Hz polling loop

    private func startPolling() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollFrame() }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        // On a screen without a notch, the resting bar must not intercept clicks
        // in the app window immediately below the menu bar.
        let hoverRect = !hasNotch && state.mode != .expanded
            ? islandRect : islandRect.insetBy(dx: -6, dy: -6)
        let inIsland = hoverRect.contains(local)

        // Toggle click-through
        if panel.ignoresMouseEvents == inIsland {
            panel.ignoresMouseEvents = !inIsland
            if inIsland, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // Mouse in the island screen's coords (Y flipped, origin top-left) for Tomo's gaze
        let sf = panel.screen?.frame ?? pf
        let newPos = CGPoint(x: mouse.x - sf.minX, y: sf.maxY - mouse.y)
        let cur = AppState.shared.mousePosition
        if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
            AppState.shared.mousePosition = newPos
        }

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland { fsm.mouseEntered() }
        if !inIsland && wasInIsland { fsm.mouseLeft() }
        wasInIsland = inIsland
        state.mouseInIsland = inIsland

        // Bot-head hover (love emote)
        let overBot = state.mode == .expanded && state.stateOverride == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: NSEvent.mouseLocation) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering {
            let m = NSEvent.mouseLocation
            let dist = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
            if dist > 40 {
                botHoverStartPos = m
                botHoverTimer?.cancel()
                scheduleLoveTimer()
            }
        }
    }

    // MARK: - Bot-head hover (love emote)

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        botHoverStartPos = mousePos
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        scheduleLoveTimer()
    }

    private func botHoverOut() {
        botHoverTimer?.cancel()
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    private func scheduleLoveTimer() {
        botHoverTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.botHovering, self.state.stateOverride == nil else { return }
            guard CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) { state.mode = mode }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close") }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode != .expanded { setMode(.expanded) }
    }

    func collapse() {
        // Keep the FSM in step with what is on screen (home → petit now).
        fsm.collapse()
        setMode(.compact)
        giveBackKeyboard()
    }

    // MARK: - Keyboard (Escape closes) and mouse

    /// The learner opened Tomo themselves (a click, the menu): the island takes the keyboard, so Esc closes it.
    /// Tomo dropping in by itself never does, or the learner's typing would land in it.
    func takeKeyboard() {
        window?.makeKey()
    }

    /// A key the island got closes it: Esc, sent to the island (not Settings), while it's open. Anything else
    /// passes on untouched.
    nonisolated static func escCloses(keyCode: UInt16, inIsland: Bool, open: Bool) -> Bool {
        keyCode == 53 && inIsland && open   // 53: Escape
    }

    /// Hands the keyboard back to the app the learner was in. The panel never activates Tomodachi, so that app
    /// is still frontmost: ordering the panel out and straight back in gives its window the keyboard again.
    private func giveBackKeyboard() {
        guard let panel = window, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func startKeyMonitor() {
        // Esc closes the island. A local monitor sees only keys sent to Tomo's own windows, so it needs no
        // permission (a global one needs Accessibility, which Tomodachi never asks for) and never takes a key
        // from the app the learner is working in (decisions.md).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, Self.escCloses(keyCode: event.keyCode, inIsland: event.window === self.window,
                                               open: self.state.mode == .expanded) else { return false }
                self.collapse()
                return true
            }
            return closed ? nil : event
        }

        // .botDizzy — posted by TomoBlob.poke() on the 3rd poke; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDizzy() }
        }

        // A click on the island: a poke when it's open (on Tomo), or open it on mouseUp.
        // Uses MainActor.assumeIsolated (synchronous) to avoid racing pollFrame().
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // A poke only lands on Tomo, and only when the island is open
                guard self.isBotHit(event.locationInWindow), self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                self.pendingIslandClick = false
                if hadPendingClick && self.state.mode != .expanded {
                    if self.fsm.state == .home {
                        // FSM already thinks it's open (e.g. the view folded it): just reopen.
                        self.expand(to: .overview)
                    } else {
                        self.fsm.click()   // FSM petit/hidden→home; onTransition calls expand(to:)
                    }
                    self.takeKeyboard()
                }
            }
            return event
        }
    }

    // MARK: - Dizzy recovery (triggered by TomoBlob.poke via .botDizzy)

    private func handleDizzy() {
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.stateOverride = nil
            if self.state.view == .confused { self.state.view = .overview }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (for pokes and hover)

    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let s = AppState.shared
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let (islandW, islandH) = islandSize(mode: s.mode, view: s.view, nw: notchW, nh: notchH)
        let islandMinX = (panelW - islandW) / 2
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                islandW: islandW, islandH: islandH, hasNotch: s.hasNotch)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
        // island top in AppKit coords = panelH (island glued to top of panel/screen)
        let botX = islandMinX + cx
        let botY = panelH - cy
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }

    // MARK: - Notch detection (static)

    static func screenGeometry(for screen: NSScreen) -> IslandScreenGeometry {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // visibleFrame includes the menu bar only while it is visible. Keep a
        // small resting bar when menus auto-hide or the app is in full screen.
        let menuBarHeight = visibleMenuBarHeight > 0
            ? visibleMenuBarHeight : NSStatusBar.system.thickness
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight
        )
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view, nw: nw, nh: nh)
        let h = fixedH + (s.mode == .expanded ? s.helpPanelHeight : 0)
        return CGRect(x: (frame.width - w) / 2, y: frame.height - h, width: w, height: h)
    }
}

// MARK: - islandSize (takes real notch dimensions)

func islandSize(mode: IslandMode, view: IslandView,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight) -> (CGFloat, CGFloat) {
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:  return (nw + 160, nh)
    case .expanded: return (IslandConst.expandedWidth, IslandConst.layout(view).height)
    }
}
