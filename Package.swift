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
        .package(url: "https://github.com/waydabber/AppleSiliconDDC.git", branch: "main")
    ],
    targets: [
        .target(
            name: "CDDCBridge",
            path: "Sources/CDDCBridge",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MonitorSwitchUI",
            dependencies: ["CDDCBridge", "AppleSiliconDDC"],
            path: "Sources",
            exclude: ["CDDCBridge"],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("CoreDisplay")
            ]
        )
    ]
)
