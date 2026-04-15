// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AgentKit", targets: ["AgentKit"])
    ],
    targets: [
        .target(name: "AgentKit"),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit"])
    ]
)
