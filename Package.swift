// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisKey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisKey", targets: ["WhisKeyApp"]),
        .library(name: "WhisKeyCore", targets: ["WhisKeyCore"]),
        .library(name: "WhisKeyBridge", targets: ["WhisKeyBridge"]),
    ],
    targets: [
        // MARK: - App entry point (menu bar app)
        .executableTarget(
            name: "WhisKeyApp",
            dependencies: ["WhisKeyCore", "WhisKeyUI"],
            path: "Sources/WhisKeyApp"
        ),

        // MARK: - Core pipeline (ASR, LLM, injection, audio, storage)
        .target(
            name: "WhisKeyCore",
            dependencies: ["WhisKeyBridge"],
            path: "Sources/WhisKeyCore"
        ),

        // MARK: - SwiftUI views and components
        .target(
            name: "WhisKeyUI",
            dependencies: ["WhisKeyCore"],
            path: "Sources/WhisKeyUI"
        ),

        // MARK: - C++ bridge layer (whisper.cpp, llama.cpp)
        // TODO: add whisper.cpp and llama.cpp as local/vendored C targets
        .target(
            name: "WhisKeyBridge",
            path: "Sources/WhisKeyBridge",
            publicHeadersPath: "include"
        ),

        // MARK: - Tests
        .testTarget(
            name: "WhisKeyCoreTests",
            dependencies: ["WhisKeyCore"],
            path: "Tests/WhisKeyCoreTests"
        ),
    ]
)
