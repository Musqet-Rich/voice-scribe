// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceScribe",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Parakeet ASR, VAD and speaker diarisation on the Neural Engine.
        // TTS and NeMo text normalisation traits are dropped to keep the build lean.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.4", traits: ["Diarizer"]),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "HotKey",
            ],
            path: "Sources/VoiceScribe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
