// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CatmullRomTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CatmullRomSmoothing",
            path: "SupaNotesSwift/Canvas",
            sources: [
                "CatmullRomSmoothing.swift",
                "StrokeRendering.swift",
            ]
        ),
        .testTarget(
            name: "CatmullRomSmoothingTests",
            dependencies: ["CatmullRomSmoothing"],
            path: "Tests",
            sources: [
                "CatmullRomSmoothingTests.swift",
            ]
        ),
    ]
)
