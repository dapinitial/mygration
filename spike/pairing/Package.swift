// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pair",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "pair", path: "Sources/pair")
    ]
)
