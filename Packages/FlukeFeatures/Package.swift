// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlukeFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlukeFeatures", targets: ["FlukeFeatures"]),
    ],
    dependencies: [
        .package(path: "../FlukeKit"),
        .package(path: "../FlukeUI"),
    ],
    targets: [
        .target(
            name: "FlukeFeatures",
            dependencies: [
                .product(name: "FlukeKit", package: "FlukeKit"),
                .product(name: "FlukeReleaseB", package: "FlukeKit"),
                "FlukeUI",
            ],
            path: "Sources/FlukeFeatures",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FlukeFeaturesTests",
            dependencies: ["FlukeFeatures"],
            path: "Tests/FlukeFeaturesTests"
        ),
    ]
)
