// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceScribe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceScribe",
            dependencies: ["WhisperKit", "HotKey"],
            path: "Sources/VoiceScribe"
        ),
    ]
)
