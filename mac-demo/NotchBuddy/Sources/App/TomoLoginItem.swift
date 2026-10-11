import Foundation
import ServiceManagement
import TomoCore

/// Opening Tomodachi at login (Settings → General; first-run onboarding can offer it too, #88). Tomo can only
/// drop in while the app is open, so without it Tomo stops visiting after a restart. Off until the learner turns
/// it on: the Mac App Store doesn't allow starting at login without consent. macOS lists it under
/// System Settings → General → Login Items, where the learner can also turn it off.
@MainActor
enum TomoLoginItem {
    /// This build may open at login: a Release build only. A Debug build is its own app beside the owner's (#54), and
    /// SERP's build identity standard keeps it out of Login Items, so a copy run from Xcode never starts next to the
    /// owner's Tomo. Checked here, the one place that calls the API, so no caller gets past it (TOMO_SELFTEST checks it).
    static let allowed: Bool = {
        #if DEBUG
        return false
        #else
        return !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug")
        #endif
    }()

    /// Tomodachi opens at login.
    static var isOn: Bool { allowed && SMAppService.mainApp.status == .enabled }

    /// It's switched on, but the learner has to allow it in System Settings → Login Items first.
    static var needsApproval: Bool { allowed && SMAppService.mainApp.status == .requiresApproval }

    /// Turns it on or off and returns whether it's on afterwards (macOS can say no, or ask for approval). A build that
    /// isn't `allowed` never calls the API: it stays off.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard allowed else { return false }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Already in that state, or not allowed: `status` says which.
        }
        return isOn
    }

    /// System Settings → General → Login Items, to approve it.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The rule, for TOMO_SELFTEST: a Debug build never opens at login, and its first run has no switch. It only reads:
    /// a broken guard can't make it register the build on the Mac that runs it.
    static func selfTest(_ check: (Bool, String) -> Void) {
        let firstRun = TomoOnboarding(kind: .welcomeBack, shell: .mac, loginItem: TomoOnboardingWindow.loginItem)
        #if DEBUG
        check(!allowed && !isOn && !needsApproval && !firstRun.offersLogin && !firstRun.openAtLogin,
              "a Debug build never opens at login: no switch in its first run or Settings, and it never calls the API")
        #else
        check(allowed && firstRun.offersLogin && firstRun.openAtLogin,
              "a Release build may open at login: the first run offers the switch, on")
        #endif
    }
}
