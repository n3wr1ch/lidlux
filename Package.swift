// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoBright",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AutoBright", path: "Sources/AutoBright")
    ]
)
