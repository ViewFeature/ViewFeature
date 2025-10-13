// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ViewFeature",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "ViewFeature",
            targets: ["ViewFeature"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
    ],
    targets: [
        .target(
            name: "ViewFeature",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "ViewFeatureTests",
            dependencies: [
                "ViewFeature",
            ],
            path: "Tests"
        ),
    ]
)
