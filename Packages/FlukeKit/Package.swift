// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlukeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlukeKit", targets: ["FlukeKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FlukeKit",
            path: "Sources/FlukeKit"
        ),
        .testTarget(
            name: "FlukeKitTests",
            dependencies: ["FlukeKit"],
            path: "Tests/FlukeKitTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
