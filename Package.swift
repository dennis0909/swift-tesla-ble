// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-tesla-ble",
    platforms: [.iOS(.v17), .macOS(.v11)],
    products: [
        .library(name: "TeslaBLE", targets: ["TeslaBLE"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .binaryTarget(
            name: "TeslaCommand",
            path: "build/TeslaCommand.xcframework",
        ),
        .target(
            name: "TeslaBLE",
            dependencies: [
                .target(name: "TeslaCommand", condition: .when(platforms: [.iOS])),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
        ),
        .testTarget(
            name: "TeslaBLETests",
            dependencies: ["TeslaBLE"],
        ),
    ],
)
