// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidLux",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LidLux", path: "Sources/LidLux"),
        .testTarget(name: "LidLuxTests", dependencies: ["LidLux"])
    ]
)
