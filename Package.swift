// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YamahaRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "YamahaRemote", path: "Sources")
    ]
)
