// swift-tools-version:5.9
// Anti-slop: a small macOS selected-text copy editor.
//
// AntiSlopCore is Foundation-only so request composition, validation, provider
// adapters, session state and replacement checks build and test on Linux as
// well as macOS. AntiSlopMac holds the AppKit/Accessibility layer and compiles
// only on macOS; its sources are wrapped in `#if os(macOS)`.
import PackageDescription

let package = Package(
    name: "AntiSlop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AntiSlop", targets: ["AntiSlop"]),
        .executable(name: "antislop-eval", targets: ["antislop-eval"]),
        .executable(name: "antislop-axprobe", targets: ["antislop-axprobe"]),
        .library(name: "AntiSlopCore", targets: ["AntiSlopCore"]),
    ],
    targets: [
        .target(name: "AntiSlopCore"),
        .target(name: "AntiSlopMac", dependencies: ["AntiSlopCore"]),
        .executableTarget(name: "AntiSlop", dependencies: ["AntiSlopMac", "AntiSlopCore"]),
        .executableTarget(name: "antislop-eval", dependencies: ["AntiSlopCore"]),
        .executableTarget(name: "antislop-axprobe", dependencies: ["AntiSlopMac", "AntiSlopCore"]),
        .testTarget(name: "AntiSlopCoreTests", dependencies: ["AntiSlopCore"]),
    ]
)
