// swift-tools-version: 6.0
import PackageDescription

// G13 Manager — userspace driver + management app for the Logitech G13 on macOS.
//
// Build environment note: this machine has Command Line Tools only (no full Xcode),
// so the canonical build path is `swift build` + hand-assembled .app bundle
// (see scripts/make_app.sh). We use the Swift 5 language mode to keep the heavy
// IOKit / CoreGraphics C-interop and the cross-thread HID callback ergonomic.
let package = Package(
    name: "G13Manager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "G13Core", targets: ["G13Core"]),
        .executable(name: "g13probe", targets: ["g13probe"]),
        .executable(name: "G13Manager", targets: ["G13Manager"]),
    ],
    targets: [
        .target(
            name: "G13Core"
        ),
        .executableTarget(
            name: "g13probe",
            dependencies: ["G13Core"]
        ),
        .executableTarget(
            name: "G13Manager",
            dependencies: ["G13Core"]
        ),
        // Plain-executable test runner. `swift test` needs the xctest harness /
        // bundled Testing module, neither of which ships with Command Line Tools,
        // so logic tests run as `swift run g13selftest` instead.
        .executableTarget(
            name: "g13selftest",
            dependencies: ["G13Core"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
