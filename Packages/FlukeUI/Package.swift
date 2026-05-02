// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlukeUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlukeUI", targets: ["FlukeUI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        ),
    ],
    targets: [
        .target(
            name: "FlukeUI",
            path: "Sources/FlukeUI",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FlukeUITests",
            dependencies: [
                "FlukeUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/FlukeUITests"
        ),
    ]
)
