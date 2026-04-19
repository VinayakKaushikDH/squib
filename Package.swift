// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "squib",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "squib",
            path: "Sources/squib",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
