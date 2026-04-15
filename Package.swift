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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [

        // MARK: - CGGML — shared ggml runtime (llama.cpp 0.9.11)
        // Both CWhisper and CLlama depend on this. Avoids duplicate symbol errors
        // from linking two ggml copies into the same binary.
        .target(
            name: "CGGML",
            path: "CGGML",
            exclude: [
                // Metal shader source — compiled at runtime via MTLDevice
                "ggml-metal/ggml-metal.metal",
                // CMake files
                "ggml-metal/CMakeLists.txt",
                "ggml-cpu/CMakeLists.txt",
                // Non-arm64 arch files
                "ggml-cpu/arch/x86",
                "ggml-cpu/arch/loongarch",
                "ggml-cpu/arch/powerpc",
                "ggml-cpu/arch/riscv",
                "ggml-cpu/arch/s390",
                "ggml-cpu/arch/wasm",
                // SpaceMIT RISC-V kernel (uses RISC-V asm)
                "ggml-cpu/spacemit",
                // KleidiAI ARM micro-kernels (requires external Arm SDK headers)
                "ggml-cpu/kleidiai",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_METAL"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_ACCELERATE"),
                .define("NDEBUG"),
                .define("GGML_VERSION", to: "\"0.9.11\""),
                .define("GGML_COMMIT", to: "\"unknown\""),
                .unsafeFlags(["-fno-objc-arc"]),
                .unsafeFlags(["-USWIFT_PACKAGE"]),
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("ggml-cpu"),
                .headerSearchPath("ggml-metal"),
            ],
            cxxSettings: [
                .define("GGML_USE_METAL"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_ACCELERATE"),
                .define("NDEBUG"),
                .define("GGML_VERSION", to: "\"0.9.11\""),
                .define("GGML_COMMIT", to: "\"unknown\""),
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("ggml-cpu"),
                .headerSearchPath("ggml-metal"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
            ]
        ),

        // MARK: - CWhisper — whisper.cpp ASR (whisper-specific files only; ggml via CGGML)
        .target(
            name: "CWhisper",
            dependencies: ["CGGML"],
            path: "CWhisper",
            publicHeadersPath: "include",
            cSettings: [
                .define("NDEBUG"),
                .define("WHISPER_VERSION", to: "\"1.8.4\""),
                .headerSearchPath("."),
                .headerSearchPath("include"),
            ],
            cxxSettings: [
                .define("NDEBUG"),
                .define("WHISPER_VERSION", to: "\"1.8.4\""),
                .headerSearchPath("."),
                .headerSearchPath("include"),
            ]
        ),

        // MARK: - CLlama — llama.cpp LLM inference (llama-specific files only; ggml via CGGML)
        .target(
            name: "CLlama",
            dependencies: ["CGGML"],
            path: "CLlama",
            publicHeadersPath: "include",
            cSettings: [
                .define("NDEBUG"),
                .define("LLAMA_VERSION", to: "\"0.0.0\""),
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("models"),
            ],
            cxxSettings: [
                .define("NDEBUG"),
                .define("LLAMA_VERSION", to: "\"0.0.0\""),
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("models"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("Foundation"),
            ]
        ),

        // MARK: - WhisKeyCore — all business logic
        .target(
            name: "WhisKeyCore",
            dependencies: [
                "CWhisper",
                "CLlama",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/WhisKeyCore",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),

        // MARK: - WhisKeyUI — SwiftUI views
        .target(
            name: "WhisKeyUI",
            dependencies: ["WhisKeyCore"],
            path: "Sources/WhisKeyUI",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),

        // MARK: - WhisKeyApp — menu bar executable
        .executableTarget(
            name: "WhisKeyApp",
            dependencies: ["WhisKeyCore", "WhisKeyUI"],
            path: "Sources/WhisKeyApp",
            exclude: ["Info.plist"]
        ),

        // MARK: - Tests
        .testTarget(
            name: "WhisKeyCoreTests",
            dependencies: ["WhisKeyCore"],
            path: "Tests/WhisKeyCoreTests",
            // Testing.framework lives under the Developer frameworks directory.
            // Xcode runners expose it automatically; CLT requires an explicit search path.
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("Testing"),
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ], .when(platforms: [.macOS])),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx17
)
