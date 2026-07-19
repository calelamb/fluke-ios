// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "FlukeML",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "FlukeML", targets: ["FlukeML"])
  ],
  targets: [
    .target(
      name: "FlukeML",
      path: "Sources/FlukeML",
      swiftSettings: [
        .unsafeFlags([
          "-Xcc", "-DACCELERATE_NEW_LAPACK",
          "-Xcc", "-DACCELERATE_LAPACK_ILP64",
        ])
      ]
    ),
    .testTarget(
      name: "FlukeMLTests",
      dependencies: ["FlukeML"],
      path: "Tests/FlukeMLTests",
      exclude: ["FixtureGeneration"],
      resources: [
        .process("Fixtures/producer-metadata.json"),
        .copy("Fixtures/python-catalog"),
        .process("Fixtures/python-catalog-provenance.json"),
        .process("Fixtures/preprocessing-source.png"),
        .process("Fixtures/preprocessing-golden.f32"),
        .process("Fixtures/embedding-golden.f32"),
        .process("Fixtures/preprocessing-provenance.json"),
      ]
    ),
  ]
)
