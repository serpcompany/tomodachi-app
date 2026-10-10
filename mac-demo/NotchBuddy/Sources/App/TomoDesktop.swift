import AppKit
import SwiftUI
import TomoCore

// MARK: - Tomo on the desktop (#130 batch 4: a prototype, behind TOMO_DESKTOP=1)
//
// Drag small Tomo out of the notch and let go: it stays on the desktop and keeps you company, its eyes on the pointer.
// With no pointer near it for about 8 s it dozes, and wakes when the pointer comes back. Let go on the notch, or when a
// visit is due (or the island opens any other way), and it flies back to its place beside the notch along an arc
// (0.95 s); under Reduce Motion it fades out there and back in beside the notch. Dragged again, it moves; clicked, it's
// poked. Everything is in AppKit's global coordinates (origin at the main screen's bottom left), so the drag, where it
// lands, the hit test against Tomo's real outline and its gaze work across screens. It's off for learners (no Setting)
// and never opens in a headless run. The rules are pure (`TomoDesktopRules`, `TomoDozeClock`, `TomoReturnArc`) and
// checked by TomoIslandSelfTest; TOMO_RENDER_DESKTOP draws the drag, the doze and the flight home offline.

enum TomoDesktopRules {
    /// How far the pointer moves after pressing on small Tomo before it's a drag, not a click (pt).
    static let dragStart: CGFloat = 6
    /// Tomo's size on the desktop (the peek's), and its canvas's room above it for particles.
    static let diameter: CGFloat = 56
    static let overhang: CGFloat = 40
    /// Let go this close to the island and Tomo goes home instead of landing.
    static let homeMargin: CGFloat = 24
    /// It lands at least this far inside the screen's usable area (below the menu bar, above the Dock).
    static let edgeMargin: CGFloat = 8
    /// The pointer within this distance keeps Tomo company; farther for `dozeAfter`, it dozes.
    static let nearRadius: CGFloat = 180
    static let dozeAfter: TimeInterval = 8

    static func dragStarts(from press: CGPoint, to now: CGPoint) -> Bool {
        hypot(now.x - press.x, now.y - press.y) > dragStart
    }

    /// Let go on (or right by) the island: back home.
    static func goesHome(drop: CGPoint, island: CGRect) -> Bool {
        island.insetBy(dx: -homeMargin, dy: -homeMargin).contains(drop)
    }

    /// Where Tomo's centre lands for a drop: on the screen the drop is on (else the nearest), fully inside its usable
    /// area. `screens` are the screens' visible frames. Nil without a screen.
    static func landing(drop: CGPoint, screens: [CGRect], radius: CGFloat) -> CGPoint? {
        guard let screen = screens.first(where: { $0.contains(drop) })
                ?? screens.min(by: { distance(drop, $0) < distance(drop, $1) }) else { return nil }
        let room = screen.insetBy(dx: radius + edgeMargin, dy: radius + edgeMargin)
        guard room.width > 0, room.height > 0 else { return CGPoint(x: screen.midX, y: screen.midY) }
        return CGPoint(x: min(max(drop.x, room.minX), room.maxX), y: min(max(drop.y, room.minY), room.maxY))
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// The canvas Tomo is drawn in at `diameter` (as BotPlacement sizes it), and Tomo's centre in it (top-left
    /// origin), where TomoBlob.draw puts it.
    static func canvas(diameter: CGFloat) -> CGSize {
        let side = diameter / 0.6
        return CGSize(width: side, height: side + overhang)
    }

    static func tomoCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 + overhang / 2 + size.width * 0.27 * 0.1)
    }

    /// Whether a point in Tomo's canvas (top-left origin) is on Tomo: its body's real outline for its age's form, placed
    /// and sized as TomoBlob draws it (resting, without its breath and moves), with a point of slack.
    static func hits(_ p: CGPoint, canvas size: CGSize, form: TomoForm) -> Bool {
        let R = size.width * 0.27, g = form.scale, ground = form.bottom * R
        let c = tomoCenter(in: size)
        let q = CGPoint(x: (p.x - c.x) / g, y: (p.y - (c.y + ground)) / g + ground)
        return form.path(R: R * 1.04).contains(q)
    }

    /// Tomo's gaze toward the pointer, −1…1 (positive y: above), both in global coordinates, so it follows the pointer
    /// onto another screen.
    static func gaze(pointer: CGPoint, tomo: CGPoint) -> CGPoint {
        CGPoint(x: tanh((pointer.x - tomo.x) / 260), y: tanh((pointer.y - tomo.y) / 200))
    }

    /// Opening the island (a visit, a click, the menu, the shortcut) while Tomo is out: it flies home first.
    static func fliesHomeFirst(opening mode: IslandMode, out: Bool) -> Bool {
        out && IslandWindowController.countsAsOpen(mode)
    }
}

/// When Tomo dozes: once the pointer has stayed farther than `nearRadius` for `dozeAfter` seconds. The pointer coming
/// near wakes it at once.
struct TomoDozeClock {
    private(set) var quietSince: TimeInterval?

    /// Whether Tomo dozes now, given whether the pointer is near.
    mutating func dozes(pointerNear: Bool, now: TimeInterval) -> Bool {
        if pointerNear { quietSince = now; return false }
        let since = quietSince ?? now
        quietSince = since
        return now - since >= TomoDesktopRules.dozeAfter
    }
}

/// Tomo flying home from the desktop: an arc from where it is to its place beside the notch (global coordinates),
/// shrinking to its resting size. It leaps up first and glides in to the notch (a quadratic curve whose bend is up
/// and toward the notch, so it never leaves the screen above), eased in and out, stretching as it goes. Under Reduce
/// Motion: no arc, a fade out where it was and in at home.
struct TomoReturnArc {
    static let duration: TimeInterval = 0.95
    static let fadeHalf: TimeInterval = 0.15

    struct Pose: Equatable {
        var center: CGPoint
        var diameter: CGFloat
        var opacity: Double = 1
        var sx: CGFloat = 1
        var sy: CGFloat = 1
    }

    let from: CGPoint
    let to: CGPoint
    var fromDiameter = TomoDesktopRules.diameter
    var toDiameter: CGFloat = 20
    var reduceMotion = false

    var duration: TimeInterval { reduceMotion ? Self.fadeHalf * 2 : Self.duration }

    /// The curve's bend: most of the way up, a fifth of the way across.
    var control: CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * 0.2, y: from.y + (to.y - from.y) * 0.95)
    }

    func point(_ u: Double) -> CGPoint {
        let u = CGFloat(u), a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, d = u * u, c = control
        return CGPoint(x: a * from.x + b * c.x + d * to.x, y: a * from.y + b * c.y + d * to.y)
    }

    func pose(at t: TimeInterval) -> Pose {
        if t >= duration { return Pose(center: to, diameter: toDiameter) }
        if reduceMotion {
            let first = t < Self.fadeHalf
            return Pose(center: first ? from : to, diameter: first ? fromDiameter : toDiameter,
                        opacity: first ? 1 - t / Self.fadeHalf : (t - Self.fadeHalf) / Self.fadeHalf)
        }
        let x = max(0, t / duration)
        let u = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        let s = CGFloat(sin(Double.pi * x)) * 0.18
        return Pose(center: point(u), diameter: fromDiameter + (toDiameter - fromDiameter) * CGFloat(u),
                    sx: 1 - s * 0.55, sy: 1 + s)
    }
}

// MARK: - The desktop Tomo (live; never in a headless run)

@MainActor
final class TomoDesktop: ObservableObject {
    /// TOMO_DESKTOP=1, and not a headless run (it puts a window on the screen).
    static let enabled = ProcessInfo.processInfo.environment["TOMO_DESKTOP"] == "1" && !TomoHeadless.isOn
    static let shared = TomoDesktop()
    /// Tomo is out on the desktop (false without the flag, without making the desktop Tomo).
    static var out: Bool { enabled && shared.isOut }

    /// Tomo is out of the island: on the desktop, being dragged, or flying home.
    @Published private(set) var isOut = false
    /// How it's drawn now: its size, opacity and squash (a flight changes them).
    @Published private(set) var pose = TomoReturnArc.Pose(center: .zero, diameter: TomoDesktopRules.diameter)
    let blob = TomoBlob(material: .own, motion: .shared)

    /// The island's side: where small Tomo rests and the island's frame (global), and what to do as Tomo leaves it and
    /// comes back (hide and show small Tomo). Set by IslandWindowController.
    var restingSpot: () -> CGPoint = { .zero }
    var islandFrame: () -> CGRect = { .zero }
    var onLeave: () -> Void = {}
    var onHome: () -> Void = {}

    private var panel: NSPanel?
    private var doze = TomoDozeClock()
    private var dozing = false
    private var dozeTimer: Timer?
    private var flight: (arc: TomoReturnArc, start: Date, then: (() -> Void)?)?
    private var flightTimer: Timer?
    private var dragging = false

    private init() {}

    private var canvas: CGSize { TomoDesktopRules.canvas(diameter: TomoDesktopRules.diameter) }

    // MARK: Out of the island

    /// The pointer pulled small Tomo out of the island: it shows on the desktop under the pointer and follows it.
    func beginDrag(at p: CGPoint) {
        guard Self.enabled, flight == nil else { return }
        dragging = true
        if !isOut {
            isOut = true
            onLeave()
            blob.setState(.idle, force: true)
            blob.setGrowth(TomoGame.shared.growthStep)
            blob.dozeAfter = .infinity   // it dozes by its own rule here (TomoDozeClock)
            blob.emote(.surprised)
        }
        place(p)
        startDozeClock()
    }

    func drag(to p: CGPoint) {
        guard dragging else { return }
        place(p)
    }

    /// Let go: on the notch it goes home, anywhere else it lands on that screen.
    func drop(at p: CGPoint) {
        guard dragging else { return }
        dragging = false
        if TomoDesktopRules.goesHome(drop: p, island: islandFrame()) { flyHome(then: nil); return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        place(TomoDesktopRules.landing(drop: p, screens: screens, radius: TomoDesktopRules.diameter / 2) ?? p)
        blob.nudge()
        doze = TomoDozeClock()
    }

    /// Back to its place beside the notch (`then`: what the island does once it's there, such as open for a visit).
    func flyHome(then: (() -> Void)?) {
        guard isOut else { then?(); return }
        if let f = flight { flight = (f.arc, f.start, chain(f.then, then)); return }
        dragging = false
        let arc = TomoReturnArc(from: pose.center, to: restingSpot(), reduceMotion: TomoMotion.shared.reduce)
        flight = (arc, Date(), then)
        if dozing { dozing = false; blob.setState(.idle) }
        flightTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { TomoDesktop.shared.fly() } }
        RunLoop.main.add(timer, forMode: .common)
        flightTimer = timer
        fly()
    }

    private func chain(_ a: (() -> Void)?, _ b: (() -> Void)?) -> (() -> Void)? {
        guard a != nil || b != nil else { return nil }
        return { a?(); b?() }
    }

    private func fly() {
        guard let f = flight else { return }
        let t = Date().timeIntervalSince(f.start)
        let p = f.arc.pose(at: t)
        show(p)
        guard t >= f.arc.duration else { return }
        flightTimer?.invalidate()
        flightTimer = nil
        flight = nil
        dozeTimer?.invalidate()
        dozeTimer = nil
        panel?.orderOut(nil)
        isOut = false
        onHome()
        f.then?()
    }

    // MARK: The pointer

    /// The pointer moved (IslandWindowController's monitors, global coordinates): the panel takes clicks only on
    /// Tomo's outline, so the desktop under it keeps the rest.
    func pointerMoved(_ p: CGPoint) {
        guard isOut, let panel, flight == nil else { return }
        let local = CGPoint(x: p.x - panel.frame.minX, y: panel.frame.maxY - p.y)
        let form = TomoLook.current.form(blob.age)
        let on = dragging || TomoDesktopRules.hits(local, canvas: canvas, form: form)
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
    }

    /// Clicked without dragging: a poke.
    func poked() { blob.poke() }

    private func startDozeClock() {
        guard dozeTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { TomoDesktop.shared.checkDoze() } }
        RunLoop.main.add(timer, forMode: .common)
        dozeTimer = timer
    }

    private func checkDoze() {
        guard isOut, flight == nil, !dragging else { return }
        let p = NSEvent.mouseLocation
        let near = hypot(p.x - pose.center.x, p.y - pose.center.y) < TomoDesktopRules.nearRadius
        let now = doze.dozes(pointerNear: near, now: Date().timeIntervalSinceReferenceDate)
        guard now != dozing else { return }
        dozing = now
        blob.setState(now ? .sleeping : .idle)
        if !now { blob.emote(.happy) }
    }

    // MARK: The window

    private func place(_ p: CGPoint) {
        show(TomoReturnArc.Pose(center: p, diameter: TomoDesktopRules.diameter))
    }

    /// Puts the window so Tomo's centre is at `p.center` (global), and draws it as `p` says.
    private func show(_ p: TomoReturnArc.Pose) {
        pose = p
        let panel = self.panel ?? makePanel()
        let c = TomoDesktopRules.tomoCenter(in: canvas)
        panel.setFrameOrigin(CGPoint(x: p.center.x - c.x, y: p.center.y - (canvas.height - c.y)))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: canvas),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.canHide = false
        let host = TomoDesktopHost(frame: NSRect(origin: .zero, size: canvas))
        let view = NSHostingView(rootView: TomoDesktopView(desktop: self))
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    // MARK: Test flag

    /// TOMO_DESKTOP_AT=<x,y> (fractions of the island screen's usable area, from its bottom left): Tomo starts out on
    /// the desktop there, as if dragged there, so the doze and the flight home can be tried without a drag.
    func placeIfRequested(on screen: NSScreen?, tries: Int = 60) {
        guard Self.enabled, let raw = ProcessInfo.processInfo.environment["TOMO_DESKTOP_AT"], let screen else { return }
        let f = raw.split(separator: ",").compactMap { Double($0) }
        guard f.count == 2 else { return }
        // Only from the resting island: the launch visit's card goes first.
        if IslandWindowController.countsAsOpen(AppState.shared.mode) || AppState.shared.leaving {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.placeIfRequested(on: screen, tries: tries - 1)
                }
            }
            return
        }
        let v = screen.visibleFrame
        let p = CGPoint(x: v.minX + v.width * f[0], y: v.minY + v.height * f[1])
        beginDrag(at: p)
        drop(at: p)
    }
}

/// The desktop window's view: Tomo, drawn live from its blob at the size and squash the flight says, its gaze on the
/// pointer (global coordinates).
private struct TomoDesktopView: View {
    @ObservedObject var desktop: TomoDesktop

    var body: some View {
        let full = TomoDesktopRules.canvas(diameter: TomoDesktopRules.diameter)
        let pose = desktop.pose
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let blob = desktop.blob
                blob.frameDate = timeline.date
                let g = TomoDesktopRules.gaze(pointer: NSEvent.mouseLocation, tomo: pose.center)
                blob.lookX = g.x
                blob.lookY = g.y
                blob.particleOverhang = TomoDesktopRules.overhang
                blob.step()
                // Smaller while it flies home: drawn in a smaller canvas whose Tomo sits where the full one's does.
                let size = TomoDesktopRules.canvas(diameter: pose.diameter)
                let c = TomoDesktopRules.tomoCenter(in: full), cs = TomoDesktopRules.tomoCenter(in: size)
                var ctx = context
                ctx.opacity = pose.opacity
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: pose.sx, y: pose.sy)
                ctx.translateBy(x: -cs.x, y: -cs.y)
                blob.draw(ctx, size: size)
            }
        }
        .frame(width: full.width, height: full.height)
        .tomoReactions(desktop.blob)
    }
}

/// Takes the desktop window's clicks and drags itself (the hosting view inside only draws): a drag moves Tomo, a click
/// pokes it.
private final class TomoDesktopHost: NSView {
    private var press: CGPoint?
    private var moved = false

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        press = NSEvent.mouseLocation
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press else { return }
        let p = NSEvent.mouseLocation
        MainActor.assumeIsolated {
            if !moved, TomoDesktopRules.dragStarts(from: press, to: p) {
                moved = true
                TomoDesktop.shared.beginDrag(at: p)
            }
            if moved { TomoDesktop.shared.drag(to: p) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil }
        let p = NSEvent.mouseLocation
        MainActor.assumeIsolated {
            if moved { TomoDesktop.shared.drop(at: p) } else { TomoDesktop.shared.poked() }
        }
    }
}

// MARK: - Offline frames (TOMO_RENDER_DESKTOP=<dir>)

extension TomoDesktop {
    /// Renders, offline (headless runs never open the desktop window), a 16 s scene on a screen 1512 × 982 drawn at
    /// half size: small Tomo pulled out of the notch and dropped on the desktop, keeping the pointer company, dozing once
    /// the pointer has been away 8 s, waking as it comes back, then flying home along the arc when a visit is due; and,
    /// in `reduce-motion/`, the flight home under Reduce Motion. 20 frames a second, each with the rules' own numbers.
    static func renderScene(to out: URL, look: TomoLook) {
        render(to: out, look: look, reduceMotion: false)
        render(to: out.appendingPathComponent("reduce-motion"), look: look, reduceMotion: true)
        renderHitTest(to: out.appendingPathComponent("hit-test.png"))
    }

    /// The hit test against what's drawn: Tomo at several seeds and ages, drawn as the desktop window draws it, with the
    /// points the hit test takes in green over it (and those it takes off the body in red). Prints how often the hit
    /// test and the drawn pixels agree.
    private static func renderHitTest(to url: URL) {
        let size = TomoDesktopRules.canvas(diameter: TomoDesktopRules.diameter), scale: CGFloat = 3
        var tiles: [(TomoLook, Int)] = []
        for seed in ["desk-1", "desk-2", "desk-3", "desk-4"] { for age in [0, 2, 5] { tiles.append((TomoLook(seed: seed), age)) } }
        var agree = 0, total = 0
        var images: [CGImage] = []
        for (look, age) in tiles {
            let blob = TomoBlob(look: look, material: .forRenders)
            blob.clock = { 0 }
            blob.particleOverhang = TomoDesktopRules.overhang
            blob.setGrowth(CGFloat(age))
            blob.step()
            let renderer = ImageRenderer(content: Canvas { ctx, _ in blob.draw(ctx, size: size) }
                .frame(width: size.width, height: size.height))
            renderer.scale = scale
            guard let cg = renderer.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { continue }
            let form = look.form(blob.age)
            var dots: [(CGPoint, Bool, Bool)] = []
            for y in stride(from: 1.0, to: Double(size.height), by: 2) {
                for x in stride(from: 1.0, to: Double(size.width), by: 2) {
                    let p = CGPoint(x: x, y: y)
                    let px = Int(x * scale), py = Int(y * scale)
                    let alpha = bytes[py * cg.bytesPerRow + px * (cg.bitsPerPixel / 8) + 3]
                    let drawn = alpha > 128, hit = TomoDesktopRules.hits(p, canvas: size, form: form)
                    total += 1
                    if drawn == hit { agree += 1 }
                    if hit { dots.append((p, hit, drawn)) }
                }
            }
            let overlay = ImageRenderer(content: Canvas { ctx, _ in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
                blob.draw(ctx, size: size)
                for (p, _, drawn) in dots {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 0.5, y: p.y - 0.5, width: 1, height: 1)),
                             with: .color(drawn ? .green.opacity(0.7) : .red))
                }
            }.frame(width: size.width, height: size.height))
            overlay.scale = scale
            if let img = overlay.cgImage { images.append(img) }
        }
        print(String(format: "desktop hit test: %.1f%% of %d points agree with the drawn pixels", Double(agree) / Double(max(total, 1)) * 100, total))
        // One sheet: three ages per row, one row per seed.
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w * 3, height: h * 4, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for (i, img) in images.enumerated() {
            ctx.draw(img, in: CGRect(x: (i % 3) * w, y: (3 - i / 3) * h, width: w, height: h))
        }
        if let sheet = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func render(to out: URL, look: TomoLook, reduceMotion: Bool) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982), menuBar: CGFloat = 32
        let usable = CGRect(x: 0, y: 70, width: 1512, height: 982 - menuBar - 70)   // below the menu bar, above a Dock
        let island = CGRect(x: (1512 - 345) / 2, y: 982 - 32, width: 345, height: 32)
        let home = CGPoint(x: island.minX + 40, y: 982 - 16)                  // small Tomo's place (botPosition)
        let drop = CGPoint(x: 1512 * 0.66, y: 982 * 0.42)
        let landed = TomoDesktopRules.landing(drop: drop, screens: [usable], radius: TomoDesktopRules.diameter / 2) ?? drop
        // The pointer's path: to small Tomo, dragging it out, staying near, going away, coming back.
        let window = CGRect(x: 120, y: 300, width: 520, height: 380)
        func pointer(_ t: Double) -> CGPoint {
            func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
                let u = CGFloat(min(max(u, 0), 1)), e = u * u * (3 - 2 * u)
                return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
            }
            let start = CGPoint(x: 900, y: 600), away = CGPoint(x: window.midX, y: window.midY)
            let near = CGPoint(x: landed.x - 90, y: landed.y + 40)
            switch t {
            case ..<1: return lerp(start, home, t)
            case ..<2.6: return lerp(home, drop, (t - 1.2) / 1.2)
            case ..<4: return lerp(drop, near, (t - 2.6) / 0.8)
            case ..<4.8: return lerp(near, away, (t - 4) / 0.8)
            case ..<13.2: return away
            case ..<14: return lerp(away, near, (t - 13.2) / 0.8)
            default: return near
            }
        }
        var t = 0.0
        let blob = TomoBlob(look: look, material: .forRenders)
        blob.clock = { t }
        blob.reduceMotion = reduceMotion
        blob.particleOverhang = TomoDesktopRules.overhang
        blob.dozeAfter = .infinity
        var doze = TomoDozeClock(), dozing = false, pulled = false
        let flyAt = 14.6
        var arc: TomoReturnArc?
        let fps = 20.0, total = reduceMotion ? 3.0 : 16.0, from = reduceMotion ? 13.6 : 0
        var trail: [CGPoint] = []
        for i in 0..<Int(fps * total) {
            t = from + Double(i) / fps
            let ptr = pointer(t)
            var pose = TomoReturnArc.Pose(center: home, diameter: 20)
            if t >= 1.2 && t < flyAt {
                if !pulled { pulled = true; blob.emote(.surprised) }
                let center = t < 2.6 ? ptr : landed
                pose = TomoReturnArc.Pose(center: center, diameter: TomoDesktopRules.diameter)
                let near = hypot(ptr.x - center.x, ptr.y - center.y) < TomoDesktopRules.nearRadius
                let dozes = t >= 2.6 && doze.dozes(pointerNear: near, now: t)
                if dozes != dozing { dozing = dozes; blob.setState(dozes ? .sleeping : .idle); if !dozes { blob.emote(.happy) } }
            } else if t >= flyAt {
                if arc == nil {
                    arc = TomoReturnArc(from: landed, to: home, reduceMotion: reduceMotion)
                    if dozing { dozing = false; blob.setState(.idle) }
                    trail = stride(from: 0.0, through: 1.0, by: 0.05).map { arc!.point($0) }
                }
                pose = arc!.pose(at: t - flyAt)
            }
            let g = TomoDesktopRules.gaze(pointer: ptr, tomo: pose.center)
            blob.lookX = g.x
            blob.lookY = g.y
            blob.step()
            let caption = t < 1.2 ? "resting" : t < 2.6 ? "dragged out" : t < flyAt ? (dozing ? "dozing" : "company")
                : t < flyAt + TomoReturnArc.duration ? "flying home" : "home"
            let frame = Canvas { ctx, size in
                let k = size.width / screen.width
                func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k, y: (screen.height - p.y) * k) }
                func box(_ r: CGRect) -> CGRect {
                    CGRect(x: r.minX * k, y: (screen.height - r.maxY) * k, width: r.width * k, height: r.height * k)
                }
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.2, green: 0.27, blue: 0.4), Color(red: 0.36, green: 0.3, blue: 0.42)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.fill(Path(roundedRect: box(window), cornerRadius: 10 * k), with: .color(Color(white: 0.93)))
                ctx.fill(Path(box(CGRect(x: 0, y: 982 - menuBar, width: 1512, height: menuBar))),
                         with: .color(Color(white: 0.15, opacity: 0.85)))
                ctx.fill(Path(roundedRect: box(island), cornerRadius: 12 * k), with: .color(.black))
                // The near radius, faint, while Tomo is out; the arc's path while it flies.
                if pulled && t < flyAt {
                    let r = TomoDesktopRules.nearRadius * k, c = flip(pose.center)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                if t >= flyAt, !reduceMotion, trail.count > 1 {
                    var path = Path()
                    path.addLines(trail.map(flip))
                    ctx.stroke(path, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                // Tomo, drawn as the desktop window draws it, at the scene's scale.
                let csize = TomoDesktopRules.canvas(diameter: pose.diameter)
                let tc = TomoDesktopRules.tomoCenter(in: csize), at = flip(pose.center)
                var c = ctx
                c.opacity = pose.opacity
                c.translateBy(x: at.x, y: at.y)
                c.scaleBy(x: k * pose.sx, y: k * pose.sy)
                c.translateBy(x: -tc.x, y: -tc.y)
                blob.draw(c, size: csize)
                // The pointer.
                let pp = flip(ptr)
                var arrow = Path()
                arrow.move(to: pp)
                arrow.addLine(to: CGPoint(x: pp.x, y: pp.y + 14))
                arrow.addLine(to: CGPoint(x: pp.x + 4, y: pp.y + 10))
                arrow.addLine(to: CGPoint(x: pp.x + 9, y: pp.y + 11))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(.white))
                ctx.stroke(arrow, with: .color(.black), lineWidth: 1)
                ctx.draw(Text(verbatim: String(format: "%.2f s  %@", t, caption)).font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white), at: CGPoint(x: 8, y: size.height - 10), anchor: .leading)
            }
                .frame(width: 756, height: 491)
            let renderer = ImageRenderer(content: frame)
            renderer.scale = 1
            if let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent(String(format: "frame-%04d.png", i)))
            }
        }
    }
}
