// swift-tools-version: 6.2
// 6.2 is the floor for SwiftSetting.defaultIsolation; 6.0 rejects the manifest.
import PackageDescription

let package = Package(
    name: "WhisperRocketRemote",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.10.0")
    ],
    targets: [
        .target(name: "WRCore"),
        .target(name: "WRNetwork"),
        .executableTarget(
            name: "WhisperRocketRemote",
            dependencies: [
                "WRCore",
                "WRNetwork",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "WRCoreTests", dependencies: ["WRCore"]),
        .testTarget(name: "WRNetworkTests", dependencies: ["WRNetwork"]),
    ]
)
