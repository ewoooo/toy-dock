// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ToyDock",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ToyDock", targets: ["ToyDock"])
    ],
    targets: [
        .executableTarget(
            name: "ToyDock",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
