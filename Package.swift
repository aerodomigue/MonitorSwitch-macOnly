// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonitorSwitchUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MonitorSwitchUI",
            targets: ["MonitorSwitchUI"]
        )
    ],
    dependencies: [
        // Add any dependencies here
    ],
    targets: [
        .executableTarget(
            name: "MonitorSwitchUI",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)