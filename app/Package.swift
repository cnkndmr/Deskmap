// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Deskmap",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Deskmap",
            path: "Sources/Deskmap"
        ),
        .testTarget(
            name: "DeskmapTests",
            dependencies: ["Deskmap"],
            path: "Tests/DeskmapTests"
        ),
    ]
)
