// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlukeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlukeKit", targets: ["FlukeKit"]),
        .library(name: "FlukeReleaseB", targets: ["FlukeReleaseB"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FlukeKit",
            path: "Sources/FlukeKit"
        ),
        .target(
            name: "FlukeReleaseB",
            dependencies: ["FlukeKit"],
            path: "Sources/FlukeReleaseB"
        ),
        .testTarget(
            name: "FlukeKitTests",
            dependencies: ["FlukeKit", "FlukeReleaseB"],
            path: "Tests/FlukeKitTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
