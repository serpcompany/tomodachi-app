// swift-tools-version: 6.0
// TomoCore: everything about Tomo that isn't tied to one device. The Mac app (mac-demo/) and the
// iPhone app (issue #52) are shells around it (docs/architecture.md).
import PackageDescription

let package = Package(
    name: "TomoCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TomoCore", targets: ["TomoCore"]),
    ],
    targets: [
        .target(
            name: "TomoCore",
            resources: [.copy("Resources/languages")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
