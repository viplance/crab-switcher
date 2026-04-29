// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CrabSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CrabSwitcher", targets: ["CrabSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "CrabSwitcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
