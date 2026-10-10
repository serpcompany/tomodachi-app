import AppKit

// MARK: - Do swipes over the notch reach Tomo? (#130 batch 4: a probe, not a feature)
//
// "Swipe down to open, up to tuck away" needs the island's non-activating panel to get trackpad scrolls while it isn't
// the key window and Tomodachi isn't the active app. A headless run can't tell: its panel never takes mouse events,
// nothing can swipe, and test runs never post input. So with TOMO_SCROLL_PROBE=1 this logs, to stderr, every scroll
// Tomodachi gets (a local monitor: the event reached one of its windows) and every scroll another app gets while the
// pointer is on the island (a global monitor, which needs no permission for mouse events: if a swipe on the island
// shows up here, the panel didn't get it). Each line says whether the panel was key, whether Tomodachi was active, the
// island's mode, whether the pointer was on it, and the scroll's deltas and phases (a trackpad's are precise, with
// phases; with natural scrolling the deltas are inverted). It changes nothing: every event goes on as before.

@MainActor
enum TomoScrollProbe {
    private static var monitors: [Any] = []
    private static let started = Date()

    /// Starts logging if TOMO_SCROLL_PROBE is set. `panel` is the island's.
    static func startIfRequested(panel: NSWindow?) {
        guard ProcessInfo.processInfo.environment["TOMO_SCROLL_PROBE"] != nil, monitors.isEmpty else { return }
        log("scroll-probe on: swipe with two fingers on the resting island, on a peek and on the card, "
            + "with another app in front; each scroll prints a line")
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            MainActor.assumeIsolated { log(line("tomodachi", event, panel: panel)) }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { event in
            MainActor.assumeIsolated {
                guard AppState.shared.mouseInIsland else { return }   // only the ones over the island matter
                log(line("another app", event, panel: panel))
            }
        }) { monitors.append(m) }
    }

    private static func line(_ who: String, _ e: NSEvent, panel: NSWindow?) -> String {
        let s = AppState.shared
        let to = e.window.map { $0 === panel ? "island" : String(describing: type(of: $0)) } ?? "none"
        return String(format: "scroll-probe %@ t=%.2f dy=%.2f dx=%.2f precise=%@ phase=%@ momentum=%@ inverted=%@ "
                      + "window=%@ panelKey=%@ appActive=%@ mode=%@ pointerOnIsland=%@",
                      who, Date().timeIntervalSince(started), e.scrollingDeltaY, e.scrollingDeltaX,
                      String(e.hasPreciseScrollingDeltas), phase(e.phase), phase(e.momentumPhase),
                      String(e.isDirectionInvertedFromDevice), to, String(panel?.isKeyWindow == true),
                      String(NSApp.isActive), s.mode.rawValue, String(s.mouseInIsland))
    }

    private static func phase(_ p: NSEvent.Phase) -> String {
        switch p {
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .mayBegin: "mayBegin"
        case .stationary: "stationary"
        default: "none"
        }
    }

    private static func log(_ s: String) { fputs(s + "\n", stderr) }
}
