// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mygration",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MygrationCore", targets: ["MygrationCore"]),
        .executable(name: "mygration", targets: ["mygration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "MygrationCore", path: "Sources/MygrationCore"),
        .executableTarget(
            name: "mygration",
            dependencies: [
                "MygrationCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/mygration"),
        .testTarget(
            name: "MygrationCoreTests",
            dependencies: ["MygrationCore"],
            path: "Tests/MygrationCoreTests"),
    ]
)
