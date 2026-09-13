// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceRouter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SpaceRouter",
            path: "Sources/SpaceRouter"
        ),
        .testTarget(
            name: "SpaceRouterTests",
            dependencies: ["SpaceRouter"],
            path: "Tests/SpaceRouterTests"
        ),
    ]
)
