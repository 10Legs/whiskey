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
        .library(name: "CWhisper", targets: ["CWhisper"]),
        .library(name: "CLlama",   targets: ["CLlama"]),
    ],
    dependencies: [
        // GRDB.swift source is vendored in Vendor/GRDB/ and built against the
        // system SQLite bundled with macOS. No external dependencies required.
    ],
    targets: [

        // MARK: - CSQLite — system SQLite bundled with macOS
        // Wraps /usr/lib/libsqlite3.dylib as the `CSQLite` module that
        // GRDB's Export.swift imports under the SWIFT_PACKAGE branch.
        .systemLibrary(
            name: "CSQLite",
            path: "CSQLiteLib"
        ),

        // MARK: - GRDB — GRDB 6.29.3 vendored, plain SQLite (system)
        // Source extracted from https://github.com/groue/GRDB.swift tag v6.29.3.
        // SWIFT_PACKAGE → satisfies GRDB's own package-build guard.
        // SQLITE_ENABLE_FTS5 → enable full-text search.
        .target(
            name: "GRDB",
            dependencies: ["CSQLite"],
            path: "Vendor/GRDB",
            exclude: [
                "Documentation.docc",
                "PrivacyInfo.xcprivacy",
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
                .define("SQLITE_ENABLE_FTS5"),
            ]
        ),

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
                "GRDB",
            ],
            path: "Sources/WhisKeyCore",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"]),
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
            exclude: ["Info.plist"],
            resources: [
                // Precompiled ggml Metal library. SPM copies executable-target resources
                // directly to the binary's directory (Build/Products/Debug/), which is
                // where ggml_metal_library_init looks when GGML_METAL_PATH_RESOURCES
                // is set to that path by llama_bridge.cpp's set_metal_path_from_bundle().
                .copy("default.metallib"),
                // Asset catalog containing menu bar icon variants (MenuBarIdle, MenuBarRecording).
                // .process() triggers actool so SPM emits a .car into Bundle.module.
                .process("Assets.xcassets"),
            ]
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
