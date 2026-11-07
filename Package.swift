// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MusicCastRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MusicCastRemote", path: "Sources")
    ]
)
