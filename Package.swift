// KarenOS — auteur : Martial Zinsou
//  KarenOS
//  Par Martial Zinsou

// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "KarenOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KarenOS", targets: ["KarenOS"])
    ],
    targets: [
        .executableTarget(
            name: "KarenOS",
            path: "Sources/KarenOS",
            swiftSettings: [
                .define("KARENOS_VERSION", .when(configuration: .release))
            ]
        )
    ]
)

// MARK: — Metadata pour Swift Package Index & SEO
// Description courte (affichée dans l'index) : < 180 caractères
// "Application macOS native d'IA générative 100% locale (GGUF, llama.cpp, agents, multimodal)"
// Mots-clés : local-ai, generative-ai, macos, swiftui, llama-cpp, gguf, agents, multimodal, dsi, offline-ai
// Catégories : Developer Tools, Machine Learning, macOS
// Licence : MIT
// Repository : https://github.com/martialzinsou/KarenOs
// Documentation : https://github.com/martialzinsou/KarenOs/blob/main/docs/DOCUMENTATION.md