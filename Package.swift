// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClueLiz",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClueLizCore"),
        .executableTarget(name: "ClueLiz", dependencies: ["ClueLizCore"]),
        .testTarget(name: "ClueLizCoreTests", dependencies: ["ClueLizCore"])
    ]
)
