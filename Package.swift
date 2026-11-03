// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LongShot",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LongShot", targets: ["LongShot"]),
        .library(name: "LongShotCore", targets: ["LongShotCore"])
    ],
    targets: [
        .target(
            name: "LongShotCore",
            path: "Sources/LongShotCore"
        ),
        .executableTarget(
            name: "LongShot",
            dependencies: ["LongShotCore"],
            path: "Sources/LongShot"
        ),
        .testTarget(
            name: "LongShotCoreTests",
            dependencies: ["LongShotCore"],
            path: "Tests/LongShotCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
