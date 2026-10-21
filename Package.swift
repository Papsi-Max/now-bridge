// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NowBridge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NowBridge", path: "Sources/NowBridge"),
        .testTarget(name: "NowBridgeTests", dependencies: ["NowBridge"], path: "Tests/NowBridgeTests"),
    ]
)
