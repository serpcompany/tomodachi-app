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

    /// The checks, for the app's self-test (TOMO_SELFTEST): the Mac's, and the iPhone's, which a UI journey runs
    /// (`testThisBuildIsItsOwnApp`). Not `swift test`: its bundle is the test runner's.
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
        #if os(iOS)
        widgets(check, id: id, name: name)
        #endif
    }

    /// The iPhone's App Group is the app's own (`group.` and its bundle ID), and its widgets, inside the app, are this
    /// build's too: their ID is the app's plus `.widgets`, under the same name and App Group. If the two groups drifted
    /// apart, the widgets would go blank. (The entitlements name the group from the same build setting, TOMO_APP_GROUP.)
    @MainActor private static func widgets(_ check: (Bool, String) -> Void, id: String, name: String) {
        let group = TomoGlance.appGroup ?? ""
        check(group == "group." + id, "the iPhone's App Group is this build's own: \(group)")
        let plugins = Bundle.main.builtInPlugInsURL
            .flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        let widget = plugins.compactMap(Bundle.init(url:)).first {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String
                == "com.apple.widgetkit-extension"
        }
        let widgetID = widget?.bundleIdentifier ?? ""
        let widgetGroup = widget?.object(forInfoDictionaryKey: "TomoAppGroup") as? String
        let widgetName = widget?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        check(widgetID == id + ".widgets" && widgetGroup == group && widgetName == name,
              "the widgets are this build's: \(widgetID), \"\(widgetName ?? "")\", sharing \(widgetGroup ?? "no App Group")")
    }
}
