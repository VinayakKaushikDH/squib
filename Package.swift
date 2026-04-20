// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "squib",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SquibCore",
            path: "Sources/SquibCore"
        ),
        .executableTarget(
            name: "squib",
            dependencies: ["SquibCore"],
            path: "Sources/squib",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "squibTests",
            dependencies: ["SquibCore"],
            path: "Tests/squibTests"
        )
    ]
)
