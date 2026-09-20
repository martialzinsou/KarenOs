//  KarenOS
//  Par Martial Zinsou

// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "KarenOS",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "KarenOS",
            path: "Sources/KarenOS"
        )
    ]
)