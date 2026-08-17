// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SteamHub",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SteamHub",
            resources: [.process("Resources")]
        )
    ]
)
