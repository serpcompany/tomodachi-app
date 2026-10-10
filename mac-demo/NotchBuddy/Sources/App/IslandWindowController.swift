import AppKit
import Combine
import SwiftUI
import TomoCore

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers), and the one timer it needs (checkRules)
    let fsm = IslandStateMachine()
    private var rulesTimer: Timer?
    private var rulesTimerAt: TimeInterval?

    private var wasInIsland = false
    private var pointerMonitors: [Any] = []
    private var islandChanges: AnyCancellable?
    private var pointerClock: Timer?   // 60 Hz, only while it's needed (setPointerClock)
    private var keyMonitor: Any?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Bot-head hover (love emote)
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var love = TomoLoveCooldown()   // the love emote at most once every 6 s, like the iPhone's long press
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
        panel.canHide = false   // Tomodachi is a regular app: hiding it (⌘H, Hide Others) leaves Tomo in the notch
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

        startKeyMonitor()
        followScreens()
        wireFSM()
        followPointer()
    }

    // MARK: - Screens (the notch one if there is one; it can change while Tomo runs)

    /// Re-places the island whenever displays change: a monitor plugged in or out, the lid closed or opened,
    /// a resolution change, or waking from sleep. It was picked once at launch, and stranded after any of those.
    private func followScreens() {
        let replace: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, let screen = Self.islandScreen() else { return }
                self.place(on: screen)
                self.pollFrame()   // the island moved under a still pointer
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
        // The FSM starts its own fold when the pointer is away, so nothing here feeds it back.
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .hidden { SoundEngine.shared.play("peek") }
                self.setMode(.compact)

            case .peek:
                break   // only the app shows a peek (`peek()`, peekedExternally); the rules never move to one

            case .home:
                self.expand(to: .overview)
            }
        }
    }

    /// The clock the island's rules run on: seconds the Mac has been awake, so a fold waits through sleep like the
    /// timers it replaced.
    private static var clock: TimeInterval { CACurrentMediaTime() }

    /// Sets the one timer the island's rules need, for `next` (what each of their inputs returns). When it fires, the
    /// rules get the time, make what came due, and say when they need the clock again. Nil: no timer.
    private func checkRules(at next: TimeInterval?) {
        if next == rulesTimerAt, rulesTimer?.isValid == true { return }
        rulesTimer?.invalidate()
        rulesTimer = nil
        rulesTimerAt = next
        guard let next else { return }
        let wait = max(0, next - Self.clock)
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rulesTimerAt = nil
                self.checkRules(at: self.fsm.advance(to: Self.clock))
            }
        }
        timer.tolerance = min(0.05, wait / 10)
        RunLoop.main.add(timer, forMode: .common)
        rulesTimer = timer
    }

    // MARK: - Following the pointer: its moves, and the island's changes (no clock while the pointer is away)

    /// Runs `pollFrame` whenever the pointer moves or the island changes, instead of 60 times a second all day.
    /// Mouse events need no permission (only keys need Accessibility), sandboxed or not: checked on macOS 27 with an
    /// ad-hoc signed, sandboxed test app with neither Input Monitoring nor Accessibility, which got the pointer's
    /// moves all over the screen, the menu bar and the notch included, with no prompt.
    private func followPointer() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Moves sent to other apps: nearly all of them, since the panel is click-through outside the island.
        // Delivered on the main thread. A button let go elsewhere (the end of a click or a drag) checks again too,
        // in case some of the pointer's moves went unseen.
        let ups: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves.union(ups), handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFrame() }
        }) { pointerMonitors.append(m) }
        // Moves sent to Tomo's own windows.
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pollFrame() }
            return event
        }) { pointerMonitors.append(m) }
        // The island changing under a still pointer (opening, closing, the help panel, the dizzy card, a new notch)
        // moves its edge past the pointer with no event: check again once the change has landed.
        islandChanges = state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.pollFrame() } }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollFrame() }   // turns the clock on or off (setPointerClock)
            }
        }
        DispatchQueue.main.async { [weak self] in self?.pollFrame() }   // where the pointer is at launch
    }

    /// The 60 Hz clock, kept only while the pointer's moves may not come as events: while the pointer is in the
    /// island, where the panel takes it (its moves go to Tomo's non-activating panel, not to another app, so the global
    /// monitor can't see them), so leaving is still noticed at once; and while Tomodachi is the active app, which
    /// gets the moves itself. A headless run can't check either case, so they keep the clock they had.
    nonisolated static func needsPointerClock(inIsland: Bool, appActive: Bool) -> Bool {
        inIsland || appActive
    }

    private func setPointerClock(_ on: Bool) {
        if on, pointerClock == nil {
            let clock = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollFrame() }
            }
            RunLoop.main.add(clock, forMode: .common)
            pointerClock = clock
        } else if !on, let clock = pointerClock {
            clock.invalidate()
            pointerClock = nil
        }
    }

    /// Whether the resting island grows (`AppState.restingHover`): only resting, only for a pointer that came onto it
    /// (`IslandStateMachine.hovering`: not after a close under a still pointer), and not under Reduce Motion. A peek's
    /// hover opens it instead (the rules), so it never grows.
    nonisolated static func restingGrows(mode: IslandMode, hovering: Bool, reduceMotion: Bool) -> Bool {
        mode == .compact && hovering && !reduceMotion
    }

    /// TOMO_RESTING_HOVER=1 (snapshots): the resting island as it is under the pointer, which a headless run can't move.
    private static let forcedRestingHover = ProcessInfo.processInfo.environment["TOMO_RESTING_HOVER"] == "1"

    /// Whether the pointer at `point` (panel coordinates) is in the island: the panel takes clicks there and lets
    /// them through everywhere else. 6 pt of slack, except around the resting bar on a screen without a notch, which
    /// must not take the clicks meant for the window just below the menu bar. It's decided on each pointer move and
    /// each change to the island, never on a clock, so a fast flick onto small Tomo takes the click that follows it
    /// (TomoIslandSelfTest).
    nonisolated static func pointerInIsland(_ point: CGPoint, island: CGRect, hasNotch: Bool, open: Bool) -> Bool {
        let hoverRect = !hasNotch && !open ? island : island.insetBy(dx: -6, dy: -6)
        return hoverRect.contains(point)
    }

    /// The island's frame in the panel (AppKit coordinates, origin bottom-left): glued to the top, centred, with
    /// the help panel under an open card.
    nonisolated static func islandFrame(panel: CGSize, mode: IslandMode, view: IslandView,
                                        notch: CGSize, help: CGFloat, hasNotch: Bool = true, grown: Bool = false) -> CGRect {
        let (w, fixedH) = islandSize(mode: mode, view: view, nw: notch.width, nh: notch.height, hasNotch: hasNotch,
                                     grown: grown)
        let h = fixedH + (mode == .expanded ? help : 0)
        return CGRect(x: (panel.width - w) / 2, y: panel.height - h, width: w, height: h)
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        let inIsland = Self.pointerInIsland(local, island: panel.currentIslandFrame(nw: notchW, nh: notchH),
                                            hasNotch: hasNotch, open: state.mode == .expanded)
        setPointerClock(Self.needsPointerClock(inIsland: inIsland, appActive: NSApp.isActive))

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
        if inIsland && !wasInIsland { checkRules(at: fsm.mouseEntered(at: Self.clock)) }
        if !inIsland && wasInIsland { checkRules(at: fsm.mouseLeft(at: Self.clock)) }
        wasInIsland = inIsland
        state.mouseInIsland = inIsland

        // The resting island grows under a pointer that came onto it; the click area above grows with it.
        let grown = Self.restingGrows(mode: state.mode, hovering: Self.forcedRestingHover || (inIsland && fsm.hovering),
                                      reduceMotion: TomoMotion.shared.reduce)
        if state.restingHover != grown { state.restingHover = grown }

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
        guard love.ready(at: CACurrentMediaTime()) else { return }
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
            guard self.love.show(at: CACurrentMediaTime()) else { return }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .peek: return 2; case .expanded: return 3 }
    }

    /// Whether Tomo counts as open for the game (`TomoGame.isIslandOpen`): its card, or a peek, so a visit offered as a
    /// peek isn't ended as closed mid-visit.
    nonisolated static func countsAsOpen(_ mode: IslandMode) -> Bool { mode == .expanded || mode == .peek }

    /// The card opened, however it opened (a click, a peek pointed at, the menu, a visit): the game asks what it
    /// offered in a peek, if anything (`TomoGame.acceptOffer`).
    var onOpen: (() -> Void)?

    /// The fold waiting for Tomo to be pulled up into the notch (`AppState.leaving`), and where it's going.
    private var leaving: (fold: DispatchWorkItem, to: IslandMode)?

    /// How long the card or the peek waits to fold while Tomo is pulled up out of it (TomoBlob's pull up).
    nonisolated static let pullUpTime: TimeInterval = 0.45

    /// Whether going from `from` to `to` waits for Tomo to be pulled up first: the card or the peek folding (to rest,
    /// or hidden), not under Reduce Motion, where Tomo fades as it folds.
    nonisolated static func foldWaits(from: IslandMode, to: IslandMode, reduceMotion: Bool) -> Bool {
        countsAsOpen(from) && !countsAsOpen(to) && !reduceMotion
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        if Self.countsAsOpen(mode) { stayOpen() }   // opened again while Tomo was leaving: it comes back
        guard mode != prev else { return }
        // Folding the card or the peek: Tomo is pulled up into the notch first (TomoCharacterView), then it folds.
        if Self.foldWaits(from: prev, to: mode, reduceMotion: TomoMotion.shared.reduce) {
            if let pending = leaving { leaving = (pending.fold, mode); return }
            let fold = DispatchWorkItem { [weak self] in
                guard let self, let to = self.leaving?.to else { return }
                self.leaving = nil
                self.applyMode(to)
                self.state.leaving = false   // after the fold, so Tomo isn't brought back into the card first
            }
            leaving = (fold, mode)
            state.leaving = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pullUpTime, execute: fold)
            return
        }
        applyMode(mode)
    }

    /// A fold that was waiting for Tomo to leave won't happen: the island stays open.
    private func stayOpen() {
        guard let pending = leaving else { return }
        pending.fold.cancel()
        leaving = nil
        state.leaving = false
    }

    private func applyMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) { state.mode = mode }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close") }
        if mode == .expanded { onOpen?() }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode != .expanded { setMode(.expanded) }
    }

    func collapse() {
        // Keep the FSM in step with what is on screen (home → petit now).
        checkRules(at: fsm.collapse(at: Self.clock))
        setMode(.compact)
        giveBackKeyboard()
    }

    /// The app opened the island itself (Tomo's visit, the menu's Open): the FSM follows without a transition.
    /// `arriving`: Tomo came out on its own (a visit), so it drips in from the notch (`AppState.arrivals`).
    func open(arriving: Bool = false) {
        checkRules(at: fsm.openedExternally(at: Self.clock))
        if arriving, !Self.countsAsOpen(state.mode) { state.arrivals += 1 }
        expand(to: .overview)
    }

    /// A visit offered as a peek (`TomoGame.peekIsland`): the bar, which opens into the card when the pointer rests on
    /// it (the rules' 0.45 s, only for a pointer that comes in) or on a click. It never takes the keyboard. An open card
    /// stays open.
    func peek() {
        guard state.mode != .expanded else { return }
        checkRules(at: fsm.peekedExternally(at: Self.clock))
        if state.mode != .peek { state.arrivals += 1 }   // Tomo drips into the bar
        setMode(.peek)
        // TOMO_PEEK_OPEN=<seconds> (snapshots): that long after it shows, the peek opens as a click on it would, but
        // without taking the keyboard, so a test run can see the word slide into the card.
        if let wait = ProcessInfo.processInfo.environment["TOMO_PEEK_OPEN"].flatMap(TimeInterval.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, self.state.mode == .peek else { return }
                self.checkRules(at: self.fsm.click(at: Self.clock))
            }
        }
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
                        // FSM petit/hidden→home; onTransition calls expand(to:)
                        self.checkRules(at: self.fsm.click(at: Self.clock))
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
        let (islandW, islandH) = islandSize(mode: s.mode, view: s.view, nw: notchW, nh: notchH, hasNotch: hasNotch,
                                            grown: s.restingHover)
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
        // TOMO_NO_NOTCH (snapshots): the island a Mac without a notch gets, on any screen.
        let noNotch = ProcessInfo.processInfo.environment["TOMO_NO_NOTCH"] != nil
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: noNotch ? 0 : screen.safeAreaInsets.top,
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
        return IslandWindowController.islandFrame(panel: frame.size, mode: s.mode, view: s.view,
                                                  notch: CGSize(width: nw, height: nh), help: s.helpPanelHeight,
                                                  hasNotch: s.hasNotch, grown: s.restingHover)
    }
}

// MARK: - islandSize (takes real notch dimensions)

/// The island's size for a mode, on this notch (or none). `grown`: the resting island under the pointer
/// (`AppState.restingHover`), which the drawing and the click area both take from here, so they stay in step.
func islandSize(mode: IslandMode, view: IslandView,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight, hasNotch: Bool = true, grown: Bool = false) -> (CGFloat, CGFloat) {
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:
        let g = grown ? IslandRestingLayout.hoverGrowth : .zero
        return (nw + IslandRestingLayout.ear * 2 + g.width, nh + g.height)
    case .peek:
        let size = TomoPeekLayout(hasNotch: hasNotch, notchHeight: nh).size
        return (size.width, size.height)
    case .expanded: return (IslandConst.expandedWidth, IslandConst.layout(view).height)
    }
}
