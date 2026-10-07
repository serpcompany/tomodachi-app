import AppKit
import SwiftUI
import TomoCore

// MARK: - The Tomodachi window (issue #90): Tomo, Words, Settings and About, with a sidebar
//
// The same screens as the iPhone's tabs (TomoCore: TomoGrowthScreen, TomoWordsScreen, TomoSettingsScreen,
// TomoAboutScreen), plus what only the Mac has: open at login (in Settings) and, after ⌥-clicking the menu bar icon,
// the AI page and the testing tools (TomoFeatures). It opens from the menus (About, Settings…, Tomo's words, Start
// Tomo over…, and the menu bar icon's Open Tomodachi…), from Tomo's age in the card header, and when Tomodachi is
// opened again from the Dock, Finder or Launchpad (AppDelegate.applicationShouldHandleReopen). Closing it leaves
// Tomo in the notch and Tomodachi in the Dock (decisions.md).
// TOMO_OPEN_WINDOW=<screen> opens it at launch, `tour` shows every screen in turn, and TOMO_SNAPSHOT_DIR captures it
// (window-<screen>-NNN.png, and window-sheet-NNN.png for the start-over question) (docs/verification.md).

@MainActor
enum TomoAppWindow {
    private static var window: NSWindow?
    private static var timers: [Timer] = []
    static let size = NSSize(width: 860, height: 620)
    static let minSize = NSSize(width: 720, height: 500)

    /// Opens the window (or brings it to the front), at `screen` if given; `confirmStartOver` asks to start Tomo over.
    static func open(_ screen: TomoScreen? = nil, confirmStartOver: Bool = false) {
        let nav = TomoScreenNav.shared
        if let screen { nav.screen = screen }
        if confirmStartOver { nav.screen = .settings; nav.confirmingStartOver = true }
        // The island floats above every window; fold it away so it can't cover the window.
        if AppState.shared.mode == .expanded { TomoGame.shared.closeIsland?() }
        let win = window ?? make()
        if !win.isVisible { place(win) }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func make() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.minSize = minSize
        win.contentView = NSHostingView(rootView: TomoAppView(play: { TomoMenus.openIsland() }))
        win.isReleasedWhenClosed = false
        window = win
        startSnapshots()
        return win
    }

    /// Centres the window and keeps its title bar clear of the island panel (320 pt tall at the top of the island's
    /// screen), shrinking it to fit if needed.
    private static func place(_ win: NSWindow) {
        guard let screen = IslandWindowController.islandScreen() ?? win.screen ?? NSScreen.main else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: Test runs: open at launch, the tour, snapshots

    /// TOMO_OPEN_WINDOW (or the older TOMO_OPEN_SETTINGS): open the window a second after launch.
    static func openIfRequested() {
        guard let asked = TomoScreenNav.requested else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if asked == "tour" { tour() } else { open(nil, confirmStartOver: asked == "startOver") }
        }
    }

    /// Every screen in turn, three seconds each, then the start-over question.
    private static func tour() {
        var screens: [TomoScreen] = [.tomo, .words, .settings, .about]
        if TomoFeatures.shared.testingTools { screens += [.ai, .testing] }
        open(screens[0])
        for (i, screen) in screens.enumerated().dropFirst() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 * Double(i)) { open(screen) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 * Double(screens.count)) { open(confirmStartOver: true) }
    }

    private static func startSnapshots() {
        guard let dir = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_DIR"] else { return }
        var n = 0
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let win = window, win.isVisible else { return }
                n += 1
                let name = TomoScreenNav.shared.screen.rawValue
                capture(win.contentView, to: URL(fileURLWithPath: dir).appendingPathComponent(
                    String(format: "window-%@-%03d.png", name, n)))
                if let sheet = win.attachedSheet {   // the start-over question (an alert draws its text in layers)
                    captureLayers(sheet.contentView?.superview ?? sheet.contentView, to: URL(fileURLWithPath: dir)
                        .appendingPathComponent(String(format: "window-sheet-%03d.png", n)))
                }
            }
        })
    }

    private static func capture(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func captureLayers(_ view: NSView?, to url: URL) {
        guard let view, let layer = view.layer else { return }
        let scale = view.window?.backingScaleFactor ?? 2, size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        // Its material doesn't render offscreen: put it on the window's background so its light text shows.
        var background = NSColor.windowBackgroundColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.cgColor }
        ctx.cgContext.setFillColor(background)
        ctx.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        ctx.cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: ctx.cgContext)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - The window's content: a sidebar of screens, the selected screen on the right

private struct TomoAppView: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var nav = TomoScreenNav.shared
    @ObservedObject var features = TomoFeatures.shared
    let play: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(SidebarMaterial())
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(lang.learner(nav.screen.titleKey))
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 4)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: TomoAppWindow.minSize.width, minHeight: TomoAppWindow.minSize.height)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebar: some View {
        List(selection: Binding<TomoScreen?>(get: { nav.screen }, set: { if let s = $0 { nav.screen = s } })) {
            Section { TomoProfileRow().tag(TomoScreen.tomo) }
            Section { row(.words); row(.settings) }
            Section {
                if features.ai { row(.ai) }                 // hidden for now: Japanese only, offline (TomoFeatures)
                if features.testingTools { row(.testing) }  // ⌥-click the menu bar icon (TomoTestingTools)
                row(.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 34)                   // clear of the window's close / minimize / zoom buttons
    }

    private func row(_ screen: TomoScreen) -> some View {
        HStack(spacing: 8) {
            Image(systemName: screen.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(screen.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(lang.learner(screen.titleKey))
        }
        .padding(.vertical, 2)
        .tag(screen)
    }

    @ViewBuilder private var page: some View {
        switch nav.screen {
        case .tomo:     TomoGrowthScreen(play: play)
        case .words:    TomoWordsScreen()
        case .settings: TomoSettingsScreen(device: {
            TomoLoginItemSection()
            TomoReminderSettingsView.QuietHours(forVisits: true)   // no visits at night (#88)
        }, more: { EmptyView() })
        case .about:    TomoAboutScreen()
        case .ai:       TomoAISettingsView()
        case .testing:  TomoTestingSettings()
        }
    }
}

/// The sidebar's top row, like the account row in System Settings: live Tomo, its age and level.
private struct TomoProfileRow: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 10) {
            TomoLiveAvatar(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(lang.learner("screen.tomo")).font(.system(size: 14, weight: .semibold))
                Text("\(game.age) · \(lang.learner("level", ["n": "\(game.level)"]))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The translucent sidebar background of System Settings.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Settings: what only the Mac has

/// Open at login (TomoLoginItem), off until the learner turns it on.
private struct TomoLoginItemSection: View {
    @ObservedObject var lang = TomoLanguages.shared
    @State private var openAtLogin = TomoLoginItem.isOn
    @State private var needsApproval = TomoLoginItem.needsApproval

    var body: some View {
        Section {
            Toggle(lang.learner("settings.openAtLogin"), isOn: Binding(
                get: { openAtLogin },
                set: { openAtLogin = TomoLoginItem.set($0); needsApproval = TomoLoginItem.needsApproval }))
            if needsApproval {
                HStack {
                    Text(lang.learner("settings.openAtLoginApprove")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.learner("settings.openLoginItems")) { TomoLoginItem.openSystemSettings() }
                }
            }
        } footer: {
            Text(lang.learner("settings.openAtLoginNote")).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {   // the learner may have changed it in System Settings → Login Items
            openAtLogin = TomoLoginItem.isOn
            needsApproval = TomoLoginItem.needsApproval
        }
    }
}

// MARK: - Testing (after ⌥-clicking the menu bar icon): on a copy of Tomo in memory

private struct TomoTestingSettings: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        Form {
            Section {
                Picker(lang.learner("settings.tryAge"), selection: Binding(
                    get: { game.stage },
                    set: { game.jump(toAge: $0) })) {
                    ForEach([1, 2, 3, 5, 7, 10, 12], id: \.self) { Text(lang.target.ageLabel($0)).tag($0) }
                }
                if game.isScratch {
                    Button(lang.learner("settings.backToTomo")) { game.reload() }
                }
            }
            Section {
                Button(lang.learner("settings.skipAhead")) { game.skipAhead(days: 1) }
                if TomoClock.offset > 0 {
                    Text(lang.learner("settings.clockAhead", ["n": String(format: "%.1f", TomoClock.offset / 86400)]))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } footer: {
                Text(lang.learner("settings.testingNote")).font(.caption).foregroundStyle(.secondary)
            }
            .id(game.progressVersion)
        }
        .formStyle(.grouped)
    }
}
