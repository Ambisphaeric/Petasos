// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Petasos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Petasos", targets: ["PetasosApp"]),
        .library(name: "PetasosCore", targets: ["PetasosCore"]),
        .library(name: "PetasosHermes", targets: ["PetasosHermes"]),
        .library(name: "PetasosSpeech", targets: ["PetasosSpeech"]),
        .library(name: "PetasosSpeechHTTP", targets: ["PetasosSpeechHTTP"]),
        .library(name: "PetasosSpeechMLX", targets: ["PetasosSpeechMLX"]),
        .library(name: "PetasosAccessibility", targets: ["PetasosAccessibility"]),
        .library(name: "PetasosUI", targets: ["PetasosUI"]),
    ],
    dependencies: [
        // Native MLX speech: Parakeet STT (110m) + Kokoro TTS (82M), both via mlx-community HF repos.
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "PetasosApp",
            dependencies: [
                "PetasosCore",
                "PetasosHermes",
                "PetasosSpeech",
                "PetasosSpeechHTTP",
                "PetasosSpeechMLX",
                "PetasosAccessibility",
                "PetasosUI",
            ],
            path: "Sources/PetasosApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the binary's __TEXT,__info_plist section so that
                // macOS reads CFBundleIdentifier, LSUIElement, and NSMicrophoneUsageDescription
                // even when the binary is launched directly via `swift run` (i.e. not yet
                // wrapped as a proper .app bundle).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PetasosApp/Info.plist",
                ]),
            ]
        ),
        .target(
            name: "PetasosCore",
            path: "Sources/PetasosCore"
        ),
        .target(
            name: "PetasosHermes",
            dependencies: ["PetasosCore"],
            path: "Sources/PetasosHermes"
        ),
        .target(
            name: "PetasosSpeech",
            dependencies: ["PetasosCore"],
            path: "Sources/PetasosSpeech"
        ),
        .target(
            name: "PetasosSpeechHTTP",
            dependencies: ["PetasosCore", "PetasosSpeech"],
            path: "Sources/PetasosSpeechHTTP"
        ),
        .target(
            name: "PetasosSpeechMLX",
            dependencies: [
                "PetasosCore",
                "PetasosSpeech",
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
            ],
            path: "Sources/PetasosSpeechMLX"
        ),
        .target(
            name: "PetasosAccessibility",
            dependencies: ["PetasosCore"],
            path: "Sources/PetasosAccessibility"
        ),
        .target(
            name: "PetasosUI",
            dependencies: [
                "PetasosCore",
                "PetasosHermes",
                "PetasosSpeech",
                "PetasosSpeechHTTP",
                "PetasosSpeechMLX",
                "PetasosAccessibility",
            ],
            path: "Sources/PetasosUI"
        ),
        .testTarget(
            name: "PetasosCoreTests",
            dependencies: ["PetasosCore"],
            path: "Tests/PetasosCoreTests"
        ),
        .testTarget(
            name: "PetasosHermesTests",
            dependencies: ["PetasosHermes"],
            path: "Tests/PetasosHermesTests"
        ),
        .testTarget(
            name: "PetasosSpeechTests",
            dependencies: ["PetasosSpeech"],
            path: "Tests/PetasosSpeechTests"
        ),
        .testTarget(
            name: "PetasosSpeechMLXTests",
            dependencies: ["PetasosSpeechMLX"],
            path: "Tests/PetasosSpeechMLXTests"
        ),
    ]
)
