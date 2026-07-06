// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GrowattMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GrowattMenuBar", targets: ["GrowattMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "GrowattMenuBar",
            path: "Sources/GrowattMenuBar"
        )
    ]
)
