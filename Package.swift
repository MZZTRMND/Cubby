// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cubby",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Cubby", targets: ["Cubby"])
    ],
    targets: [
        .executableTarget(
            name: "Cubby",
            path: "Sources/Cubby",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CubbyTests",
            dependencies: ["Cubby"],
            path: "Tests/CubbyTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
