import ServiceManagement

/// Opening Tomodachi at login (Settings → General; first-run onboarding can offer it too, #88). Tomo can only
/// drop in while the app is open, so without it Tomo stops visiting after a restart. Off until the learner turns
/// it on: the Mac App Store doesn't allow starting at login without consent. macOS lists it under
/// System Settings → General → Login Items, where the learner can also turn it off.
@MainActor
enum TomoLoginItem {
    /// Tomodachi opens at login.
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// It's switched on, but the learner has to allow it in System Settings → Login Items first.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Turns it on or off and returns whether it's on afterwards (macOS can say no, or ask for approval).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
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
}
