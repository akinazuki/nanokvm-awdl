// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "awdlkvm",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "awdlkvm",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
        )
    ]
)
