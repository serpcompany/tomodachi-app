import AppKit
import SwiftUI
import TomoCore

// MARK: - The first run on the Mac (issue #88): TomoOnboardingView in a window of its own
//
// AppDelegate shows it at launch instead of the first visit when TomoOnboarding.checkAtLaunch() says so. The
// window sits in the middle of the notch's screen, and Tomo's visit clock is held back while it's open, so Tomo
// doesn't pop out of the notch mid-flow. Closing the window counts as done. When it's done, the saved Tomo
// reloads (with the word it just learned) and pops out of the notch: its first real visit.
// TOMO_SNAPSHOT_DIR also captures this window (onboarding-NNN.png), like the island (docs/verification.md).

@MainActor
enum TomoOnboardingWindow {
    private static var window: NSWindow?
    private static var model: TomoOnboarding?
    private static var timers: [Timer] = []
    private static let closer = Closer()
    static let size = NSSize(width: 460, height: 690)

    static func show(_ kind: TomoOnboarding.Kind) {
        let start = ProcessInfo.processInfo.environment["TOMO_ONBOARDING"].flatMap(TomoOnboarding.Step.init(rawValue:))
        let model = TomoOnboarding(kind: kind, start: start)
        model.onFinish = { close() }
        self.model = model

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1)
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.delegate = closer
        win.contentView = NSHostingView(rootView: TomoOnboardingView(model: model, gaze: { gaze(in: win) }))
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            win.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        } else {
            win.center()
        }
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Tomo stays tucked in by the notch until the first run is done.
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { TomoGame.shared.rescheduleVisits() }
        })
        startSnapshots()
    }

    /// Done (or closed): the window goes, and Tomo pops out of the notch for its first visit.
    private static func close() {
        timers.forEach { $0.invalidate() }
        timers = []
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil
        TomoGame.shared.reload()
    }

    /// Where the pointer is relative to Tomo (the top of the window), −1…1, positive y = above.
    private static func gaze(in win: NSWindow) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let tomo = CGPoint(x: win.frame.midX, y: win.frame.maxY - 170)
        return CGPoint(x: tanh((mouse.x - tomo.x) / 260), y: tanh((mouse.y - tomo.y) / 200))
    }

    /// The window's close button counts as done.
    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated { TomoOnboardingWindow.model?.finish() }
        }
    }

    private static func startSnapshots() {
        guard let dir = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_DIR"] else { return }
        var n = 0
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                n += 1
                let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "onboarding-%03d.png", n))
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        })
    }
}
