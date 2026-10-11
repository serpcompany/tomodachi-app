import AppKit
import SwiftUI
import TomoCore

// MARK: - The Tomodachi window (issue #90): Tomo, Words, Together, Settings and About, with a sidebar
//
// The same screens as the iPhone's tabs (TomoCore: TomoGrowthScreen, TomoWordsScreen, TomoTogetherScreen,
// TomoSettingsScreen, TomoAboutScreen), plus what only the Mac has: open at login (in Settings) and, after ⌥-clicking
// the menu bar icon, the AI page and the testing tools (TomoFeatures). It opens from the menus (About, Settings…,
// Tomo's words, Start Tomo over…, and the menu bar icon's Open Tomodachi…), from Tomo's age in the card header, and
// when Tomodachi is opened again from the Dock, Finder or Launchpad (AppDelegate.applicationShouldHandleReopen).
// Closing it leaves Tomo in the notch and Tomodachi in the Dock (decisions.md).
// TOMO_OPEN_WINDOW=<screen> opens it at launch, `tour` shows every screen in turn, and TOMO_SNAPSHOT_DIR captures it
// (window-<screen>-NNN.png, and window-sheet-NNN.png for the start-over question); TOMO_APPEARANCE=light|dark draws it
// in either, and TOMO_WINDOW_HEIGHT makes it taller, for a long page (docs/debug-flags.md).

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
        // TOMO_WINDOW_HEIGHT=<points>: a taller window for snapshots of a long page (a test run's window is never on
        // screen, so it may be taller than the screen).
        if let h = ProcessInfo.processInfo.environment["TOMO_WINDOW_HEIGHT"].flatMap(Double.init) {
            win.setContentSize(NSSize(width: win.frame.width, height: h))
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func make() -> NSWindow {
        let win = newWindow()
        // TOMO_APPEARANCE=light|dark: snapshots in either, whatever this Mac uses.
        if let look = ProcessInfo.processInfo.environment["TOMO_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        window = win
        startSnapshots()
        return win
    }

    /// The window with its content, not yet shown (the self-test draws one that never is).
    private static func newWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.minSize = minSize
        win.contentView = NSHostingView(rootView: TomoAppView(play: { TomoMenus.openIsland() }))
        win.isReleasedWhenClosed = false
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
        var screens: [TomoScreen] = [.tomo, .words, .together, .settings, .about]
        if TomoFeatures.shared.ai { screens += [.ai] }
        if TomoFeatures.shared.testingTools { screens += [.testing] }
        open(screens[0])
        for (i, screen) in screens.enumerated().dropFirst() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 * Double(i)) { open(screen) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 * Double(screens.count)) { open(confirmStartOver: true) }
    }

    private static func startSnapshots() {
        guard let dir = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_DIR"] else { return }
        var n = 0
        let every = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_EVERY"].flatMap(Double.init) ?? 1
        timers.append(Timer.scheduledTimer(withTimeInterval: max(every, 0.05), repeats: true) { _ in
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
        guard let view, let rep = snapshot(view) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The view as the snapshots and the self-test draw it. A selected sidebar row's highlight is a material (an
    /// NSVisualEffectView, `.selection`), which only the window server draws: drawn offscreen, as here, it comes out
    /// solid black, and a light-mode label on it vanishes (#239). So while the picture is taken, each one stands
    /// aside for the system's colour for a selection: grey in a window that isn't in front (a test run's never is),
    /// and the accent colour when it's emphasized, as in a window in front (the self-test draws both). Emphasized, the
    /// material does draw offscreen, but in one bright blue in light and dark alike, not the system's colour.
    private static func snapshot(_ view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        let standIns = selections(in: view).map(SelectionStandIn.init(for:))
        view.cacheDisplay(in: view.bounds, to: rep)
        standIns.forEach { $0.remove() }
        return rep
    }

    private static func selections(in view: NSView) -> [NSVisualEffectView] {
        let own: [NSVisualEffectView] = (view as? NSVisualEffectView).map { [$0] } ?? []
        return own.filter { $0.material == .selection && !$0.isHidden }
            + view.subviews.flatMap(selections)
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

    // MARK: The self-test (TOMO_SELFTEST): every sidebar label shows

    /// In light and dark, with each screen selected in turn, every line of every sidebar row's label stands out from
    /// its row: at least 3:1, WCAG's floor for large text (#239: the selected row's label vanished in light mode).
    /// Each is drawn twice: as the snapshots draw it, the window behind others (the grey highlight), and as a learner
    /// sees it most, the window in front (the accent-colour highlight, with the label turned light), so a label with a
    /// fixed colour that's lost on the accent fails too. The window is never shown, and the selected screen comes back.
    static func selfTest(_ check: (Bool, String) -> Void) {
        let nav = TomoScreenNav.shared, was = nav.screen
        defer { nav.screen = was }
        let win = newWindow()
        for (look, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            win.appearance = NSAppearance(named: look)
            var weakest: [Bool: (contrast: Double, row: String)] = [:], followed = true
            for (n, screen) in [TomoScreen.tomo, .words, .together, .settings, .about].enumerated() {
                nav.screen = screen
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))   // SwiftUI moves the selection
                guard let view = win.contentView else { followed = false; continue }
                view.layoutSubtreeIfNeeded()
                let rows = sidebarRows(in: view)
                followed = followed && rows.firstIndex(where: \.isSelected) == (screen == .about ? rows.count - 1 : n)
                    && rows.filter(\.isSelected).count == 1
                for inFront in [false, true] {
                    // A table emphasizes its rows when its window is in front: the highlight turns the accent colour
                    // (in snapshot, the system's) and the label in it turns light, as on screen.
                    rows.forEach { $0.isEmphasized = inFront }
                    defer { rows.forEach { $0.isEmphasized = false } }
                    guard let picture = snapshot(view).flatMap({ Picture($0, of: view) }) else {
                        followed = false; continue
                    }
                    for (i, row) in rows.enumerated() {
                        let lines = picture.lineContrasts(row, profile: i == 0, in: view)
                        for (l, contrast) in lines.enumerated()
                        where contrast < weakest[inFront]?.contrast ?? .infinity {
                            weakest[inFront] = (contrast, "row \(i + 1)" + (lines.count > 1 ? ", line \(l + 1)" : "")
                                                + (row.isSelected ? ", selected," : "") + " on \(screen.rawValue)")
                        }
                    }
                }
            }
            for (inFront, window) in [(false, "behind"), (true, "in front")] {
                let contrast = weakest[inFront]?.contrast ?? 0
                check(followed && contrast >= 3,
                      "the window's sidebar, \(name), \(window): every line of every row's label shows, selected or "
                      + "not (weakest " + String(format: "%.1f:1", contrast) + ": \(weakest[inFront]?.row ?? "no rows")"
                      + (followed ? ")" : "; the selection didn't follow the screen)"))
            }
        }
    }

    /// The sidebar's rows, top to bottom (the pages' own lists are right of it).
    private static func sidebarRows(in view: NSView) -> [NSTableRowView] {
        func all(_ v: NSView) -> [NSTableRowView] {
            let own: [NSTableRowView] = (v as? NSTableRowView).map { [$0] } ?? []
            return own + v.subviews.flatMap(all)
        }
        func frame(_ row: NSTableRowView) -> NSRect { row.convert(row.bounds, to: view) }
        let rows = all(view).filter { frame($0).height > 1 && frame($0).maxX <= TomoSidebar.width + 1 }
        return rows.sorted { view.isFlipped ? frame($0).minY < frame($1).minY : frame($0).maxY > frame($1).maxY }
    }
}

/// In a snapshot, a selection's highlight as the screen shows it: the same rounded shape, in the system's colour for
/// it, the accent colour if it's emphasized (a window in front) and grey if not (`TomoAppWindow.snapshot`). It hides
/// the material while it stands in.
private final class SelectionStandIn: NSView {
    private let material: NSVisualEffectView
    private let radius: CGFloat, emphasized: Bool

    init(for material: NSVisualEffectView) {
        self.material = material
        radius = material.layer?.cornerRadius ?? 0
        emphasized = material.isEmphasized
        super.init(frame: material.frame)
        material.superview?.addSubview(self, positioned: .above, relativeTo: material)
        material.isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        (emphasized ? NSColor.selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    func remove() {
        removeFromSuperview()
        material.isHidden = false
    }
}

// MARK: - The sidebar's layout, shared by its rows and the self-test

private enum TomoSidebar {
    static let width: CGFloat = 220
    /// A screen's row: its icon, then the gap before its label.
    static let icon: CGFloat = 22, iconGap: CGFloat = 8
    /// The top row: live Tomo, then the gap before its name.
    static let avatar: CGFloat = 40, avatarGap: CGFloat = 10
    /// The top row's label is two lines, one over the other: Tomo's name, then its age and level.
    static let profileLines = 2
}

/// A snapshot's pixels in sRGB, on the window's background, for the self-test to measure.
@MainActor
private struct Picture {
    private let bytes: [UInt8]
    private let width: Int, height: Int, scale: CGFloat

    init?(_ rep: NSBitmapImageRep, of view: NSView) {
        guard let image = rep.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        self.width = width; self.height = height; scale = CGFloat(width) / max(view.bounds.width, 1)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var background = NSColor.windowBackgroundColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.cgColor }
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let all = CGRect(x: 0, y: 0, width: width, height: height)
            ctx.setFillColor(background)
            ctx.fill(all)
            ctx.draw(image, in: all)
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    /// WCAG's relative luminance of the pixel `x` across and `y` down.
    private func luminance(_ x: Int, _ y: Int) -> Double {
        let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(bytes[i]) + 0.7152 * linear(bytes[i + 1]) + 0.0722 * linear(bytes[i + 2])
    }

    /// How far each line of the row's label stands out from the row, top to bottom: the contrast with the row's
    /// background (sampled near the row's right end, past any label) that 10 square points of the line's ink reach,
    /// so a stray pixel can't pass. The label's box is split into equal bands, one per line (the top row's name, then
    /// its age and level), so one line can't pass for another that vanished.
    func lineContrasts(_ row: NSTableRowView, profile: Bool, in view: NSView) -> [Double] {
        let frame = row.convert(row.bounds, to: view)
        let cell = (row.numberOfColumns > 0 ? row.view(atColumn: 0) as? NSView : nil) ?? row
        let cellFrame = cell.convert(cell.bounds, to: view)
        let start = cellFrame.minX + (profile ? TomoSidebar.avatar + TomoSidebar.avatarGap
                                              : TomoSidebar.icon + TomoSidebar.iconGap)
        let label = NSRect(x: start, y: cellFrame.minY + 2, width: frame.maxX - 16 - start, height: cellFrame.height - 4)
        func pixel(_ p: NSPoint) -> (Int, Int) {
            (Int(p.x * scale), Int((view.isFlipped ? p.y : view.bounds.height - p.y) * scale))
        }
        let (bx, by) = pixel(NSPoint(x: frame.maxX - 14, y: frame.midY))
        let background = luminance(bx, by)
        let (x0, ya) = pixel(NSPoint(x: label.minX, y: label.minY)), (x1, yb) = pixel(NSPoint(x: label.maxX, y: label.maxY))
        let top = min(ya, yb), lines = profile ? TomoSidebar.profileLines : 1
        let band = (max(ya, yb) - top) / lines, ink = Int(10 * scale * scale)
        return (0..<lines).map { line in
            var contrasts: [Double] = []
            for y in (top + line * band)..<(top + (line + 1) * band) {
                for x in x0..<max(x0, x1) {
                    let l = luminance(x, y)
                    contrasts.append((max(l, background) + 0.05) / (min(l, background) + 0.05))
                }
            }
            return contrasts.count > ink ? contrasts.sorted(by: >)[ink] : 1
        }
    }
}

// MARK: - The window's content: a sidebar of screens, the selected screen on the right

/// Together, for the learner's own Tomo: its progress, look and material are passed in (TomoCore's screen takes the
/// Tomo it shows).
private struct TomoTogetherPage: View {
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        TomoTogetherScreen(progress: game.progress, look: TomoLook.current, material: .own,
                           version: game.progressVersion) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

private struct TomoAppView: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var nav = TomoScreenNav.shared
    @ObservedObject var features = TomoFeatures.shared
    let play: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: TomoSidebar.width)
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
            Section { row(.words); row(.together); row(.settings) }
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
        HStack(spacing: TomoSidebar.iconGap) {
            Image(systemName: screen.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: TomoSidebar.icon, height: TomoSidebar.icon)
                .background(screen.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(lang.learner(screen.titleKey))
        }
        .padding(.vertical, 2)
        .tag(screen)
    }

    @ViewBuilder private var page: some View {
        switch nav.screen {
        case .tomo:     TomoGrowthScreen(play: play, together: { nav.screen = .together })
        case .words:    TomoWordsScreen()
        case .together: TomoTogetherPage()
        case .settings: TomoSettingsScreen(device: {
            TomoLoginItemSection()
            TomoReminderSettingsView.QuietHours(forVisits: true)   // no visits at night (#88)
            TomoScreenSection()                                    // which screen Tomo lives on (#130)
            TomoShortcutSection()                                  // a shortcut to play from any app (#130)
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
        HStack(spacing: TomoSidebar.avatarGap) {
            TomoLiveAvatar(size: TomoSidebar.avatar, material: .own)
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

/// Open at login (TomoLoginItem), off until the learner turns it on. A Debug build never opens at login (#54): no
/// switch, only why, as in its first run.
private struct TomoLoginItemSection: View {
    @ObservedObject var lang = TomoLanguages.shared
    @State private var openAtLogin = TomoLoginItem.isOn
    @State private var needsApproval = TomoLoginItem.needsApproval

    var body: some View {
        if TomoLoginItem.allowed {
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
        } else {
            Section { Text(lang.learner("login.debug")).foregroundStyle(.secondary) }
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
