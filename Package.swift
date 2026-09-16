// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "tapswitch",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "tapswitch", targets: ["TapSwitchApp"])
    ],
    targets: [
        // Pure: the touch vocabulary and the tap state machine. Imports Foundation only.
        .target(name: "Gesture"),
        // The only module that touches the private framework. Produces Gesture's frames.
        .target(name: "Multitouch", dependencies: ["Gesture"]),
        .target(name: "InputSources"),
        .target(name: "Preferences"),
        .executableTarget(
            name: "TapSwitchApp",
            dependencies: ["Gesture", "Multitouch", "InputSources", "Preferences"]),
        .testTarget(name: "GestureTests", dependencies: ["Gesture"]),
        .testTarget(name: "InputSourcesTests", dependencies: ["InputSources"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"])
    ]
)
