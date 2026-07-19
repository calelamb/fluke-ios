// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlukeML",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlukeML", targets: ["FlukeML"]),
    ],
    targets: [
        .target(
            name: "FlukeML",
            path: "Sources/FlukeML",
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-DACCELERATE_NEW_LAPACK",
                    "-Xcc", "-DACCELERATE_LAPACK_ILP64",
                ]),
            ]
        ),
        .testTarget(
            name: "FlukeMLTests",
            dependencies: ["FlukeML"],
            path: "Tests/FlukeMLTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
