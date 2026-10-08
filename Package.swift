// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Shelf", targets: ["Shelf"])
    ],
    targets: [
        .executableTarget(
            name: "Shelf",
            path: "Sources/Shelf",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ShelfTests",
            dependencies: ["Shelf"],
            path: "Tests/ShelfTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
