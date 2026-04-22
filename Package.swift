// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "squib",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "SquibCore",
            path: "Sources/SquibCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "squib",
            dependencies: ["SquibCore"],
            path: "Sources/squib",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // squibTestRunner: standalone executable that calls Testing.__swiftPMEntryPoint()
        // directly, bypassing SPM's bundle runner which requires a formal Testing dependency
        // to activate swift-testing mode. Run with: swift run squibTestRunner
        .executableTarget(
            name: "squibTestRunner",
            dependencies: ["SquibCore"],
            path: "Sources/squibTestRunner",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ]
        )
    ]
)
