// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InstagramMac",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "InstagramMac",
            path: "Sources"
        )
    ]
)
