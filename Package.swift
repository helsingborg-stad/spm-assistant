// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Assistant",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(
            name: "Assistant",
            targets: ["Assistant"]),
    ],
    dependencies: [
        .package(name: "TTS", url: "https://github.com/helsingborg-stad/spm-tts.git", from: "0.2.0"),
        .package(name: "STT", url: "https://github.com/helsingborg-stad/spm-stt.git", from: "0.2.1"),
        .package(name: "TextTranslator", url: "https://github.com/helsingborg-stad/spm-text-translator", from: "0.2.0"),
        .package(name: "Dragoman", url: "https://github.com/helsingborg-stad/spm-dragoman.git", from: "0.1.4")
    ],
    targets: [
        .target(
            name: "Assistant",
            dependencies: [
                "TTS",
                "STT",
                "TextTranslator",
                "Dragoman"
            ]
        ),
        .testTarget(
            name: "AssistantTests",
            dependencies: ["Assistant"]),
    ]
)
