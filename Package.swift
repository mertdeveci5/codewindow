// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodeWindow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodeWindow", targets: ["CodeWindowApp"]),
        .executable(name: "codewindow-report", targets: ["CodeWindowReporter"]),
        .executable(name: "codewindow-install", targets: ["CodeWindowInstaller"]),
        .executable(name: "CodeWindowTests", targets: ["CodeWindowTests"]),
    ],
    targets: [
        .target(name: "CodeWindowCore"),
        .executableTarget(
            name: "CodeWindowReporter",
            dependencies: ["CodeWindowCore"]
        ),
        .executableTarget(
            name: "CodeWindowInstaller",
            dependencies: ["CodeWindowCore"]
        ),
        .executableTarget(
            name: "CodeWindowApp",
            dependencies: ["CodeWindowCore"]
        ),
        .executableTarget(
            name: "CodeWindowTests",
            dependencies: ["CodeWindowCore"],
            path: "Sources/CodeWindowCoreTests"
        ),
    ]
)
