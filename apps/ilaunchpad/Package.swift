// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iLaunchPad",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "iLaunchPad", targets: ["iLaunchPad"])
    ],
    targets: [
        .executableTarget(
            name: "iLaunchPad",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(name: "iLaunchPadTests", dependencies: ["iLaunchPad"])
    ]
)
