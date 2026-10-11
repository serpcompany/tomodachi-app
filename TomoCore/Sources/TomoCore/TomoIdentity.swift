import Foundation

// MARK: - This build's identity (#54; SERP's native-app-build-identity standard)
//
// A Debug build is its own app: the product's bundle ID plus `.debug`, named "Tomodachi Debug" to the system, set per
// configuration in both project.yml files. Release keeps the product's ID, which release-beta.sh and testflight.sh
// check. What Tomo keeps on a device is named by the bundle ID or the Info.plist, never by a literal here: the data
// folder (TomoStore), the preferences (UserDefaults.standard), the keychain service (Keychain) and the App Group
// (TomoGlance). So a Debug run, even without TOMO_DATA_DIR, never reads or writes the owner's copy.

public enum TomoIdentity {
    /// The app's name on Tomo's own screens: CFBundleName, "Tomodachi" in every build, so the screens and the store
    /// screenshots (taken from a Debug build) stay the same. The system's name for it (CFBundleDisplayName: the Home
    /// Screen, the widget gallery, window titles, About) says "Tomodachi Debug" in a Debug build.
    public static var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "" }

    /// The checks, for the app's self-test (TOMO_SELFTEST). Not `swift test`: its bundle is the test runner's.
    @MainActor public static func selfTest(_ check: (Bool, String) -> Void) {
        let id = Bundle.main.bundleIdentifier ?? ""
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        #if DEBUG
        check(id.hasSuffix(".debug") && name.hasSuffix(" Debug") && !appName.contains("Debug"),
              "a Debug build is its own app: \(id), \"\(name)\" to the system, \"\(appName)\" on Tomo's screens")
        #else
        check(!id.hasSuffix(".debug") && !name.contains("Debug"), "a Release build has the product's identity: \(id)")
        #endif
        let folder = TomoStore.defaultDirectory
        check(folder.lastPathComponent == id,
              "without TOMO_DATA_DIR, Tomo is saved in this build's own folder: \(folder.path)")
        check(Keychain.service == id, "the AI key is saved under this build's own keychain service: \(Keychain.service)")
        if let group = TomoGlance.appGroup {   // the iPhone's: the Mac has none
            check(group.hasSuffix(".debug") == id.hasSuffix(".debug"), "the widgets' App Group is this build's: \(group)")
        }
    }
}
