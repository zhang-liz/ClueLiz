// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Clueless",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CluelessCore"),
        .executableTarget(name: "Clueless", dependencies: ["CluelessCore"]),
        .testTarget(name: "CluelessCoreTests", dependencies: ["CluelessCore"])
    ]
)
