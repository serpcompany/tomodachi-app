import AppKit
import ObjectiveC

/// TOMO_HEADLESS=1: a test run that never shows on the owner's screen. Every window the app orders in (the
/// island, Settings, popovers, alerts) stays fully transparent and click-through, no window takes the keyboard
/// (the owner's typing would land in it), the app never activates,
/// the menu bar icon is hidden, and Tomo is silent (`TomoGame.soundEnabled` starts off without being saved).
/// Snapshots (TOMO_SNAPSHOT_DIR) still work: they draw the views, not the screen. Test-only: it swaps a few
/// NSWindow and NSApplication methods, and does nothing unless the variable is set.
enum TomoHeadless {
    static let isOn = ProcessInfo.processInfo.environment["TOMO_HEADLESS"] != nil

    /// Call first thing at launch, before any window exists.
    static func start() {
        guard isOn else { return }
        swap(NSWindow.self, "orderWindow:relativeTo:", #selector(NSWindow.tomoHeadlessOrder(_:relativeTo:)))
        swap(NSWindow.self, "orderFrontRegardless", #selector(NSWindow.tomoHeadlessOrderFrontRegardless))
        swap(NSWindow.self, "setAlphaValue:", #selector(NSWindow.tomoHeadlessSetAlpha(_:)))
        swap(NSWindow.self, "setIgnoresMouseEvents:", #selector(NSWindow.tomoHeadlessSetIgnoresMouse(_:)))
        swap(NSWindow.self, "makeKeyWindow", #selector(NSWindow.tomoHeadlessMakeKey))
        swap(NSWindow.self, "makeKeyAndOrderFront:", #selector(NSWindow.tomoHeadlessMakeKeyAndOrderFront(_:)))
        swap(NSApplication.self, "activate", #selector(NSApplication.tomoHeadlessActivateNow))
        swap(NSApplication.self, "activateIgnoringOtherApps:", #selector(NSApplication.tomoHeadlessActivate(ignoring:)))
    }

    private static func swap(_ cls: AnyClass, _ original: String, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(cls, NSSelectorFromString(original)),
              let b = class_getInstanceMethod(cls, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

// After the swap, calling the tomoHeadless… method runs the original.
extension NSWindow {
    @objc fileprivate func tomoHeadlessOrder(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        alphaValue = 0
        ignoresMouseEvents = true
        tomoHeadlessOrder(place, relativeTo: other)
    }

    @objc fileprivate func tomoHeadlessOrderFrontRegardless() {
        alphaValue = 0
        ignoresMouseEvents = true
        tomoHeadlessOrderFrontRegardless()
    }

    @objc fileprivate func tomoHeadlessSetAlpha(_ value: CGFloat) { tomoHeadlessSetAlpha(0) }
    @objc fileprivate func tomoHeadlessSetIgnoresMouse(_ value: Bool) { tomoHeadlessSetIgnoresMouse(true) }
    @objc fileprivate func tomoHeadlessMakeKey() {}
    @objc fileprivate func tomoHeadlessMakeKeyAndOrderFront(_ sender: Any?) { orderFront(sender) }
}

extension NSApplication {
    @objc fileprivate func tomoHeadlessActivateNow() {}
    @objc fileprivate func tomoHeadlessActivate(ignoring: Bool) {}
}
