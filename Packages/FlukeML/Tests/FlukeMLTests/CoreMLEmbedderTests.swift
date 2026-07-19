import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import Testing

@testable import FlukeML

@Suite("Core ML embedder")
struct CoreMLEmbedderTests {
  @Test("owned frame remains stable after its source buffer is reused")
  func frameSnapshotsPixelBuffer() throws {
    let source = try Self.redPixelBuffer(width: 3, height: 2)
    let frame = try CameraFrame(pixelBuffer: source, orientation: .up)
    try Self.overwrite(source, rgba: (0, 0, 255, 255))

    #expect(
      frame.rgbBytes == Array(repeating: [UInt8](arrayLiteral: 255, 0, 0), count: 6).flatMap(\.self)
    )
    #expect(frame.width == 3)
    #expect(frame.height == 2)
  }

  @Test("owned frame accepts camera-compatible non-packed buffers")
  func frameCopiesSupportedFormats() throws {
    let monochrome = try Self.monochromePixelBuffer(value: 127)
    let monochromeFrame = try CameraFrame(pixelBuffer: monochrome, orientation: .up)
    #expect(monochromeFrame.rgbBytes.count == 3)
    #expect(monochromeFrame.rgbBytes.allSatisfy { abs(Int($0) - 127) <= 1 })
  }

  @Test("Pillow fixture matches every normalized tensor value")
  func exactPillowPreprocessingParity() throws {
    let source = try Self.fixturePixelBuffer(named: "preprocessing-source", extension: "png")
    let frame = try CameraFrame(pixelBuffer: source, orientation: .right)
    let actual = try CoreMLImagePreprocessor().makeInput(frame: frame)
    let expected = try Self.fixtureFloats(named: "preprocessing-golden")

    #expect(actual.shape == [1, 3, 224, 224])
    #expect(actual.dataType == .float32)
    #expect(expected.count == actual.count)
    let maximumError =
      expected.indices.map {
        abs(actual[$0].floatValue - expected[$0])
      }.max() ?? .infinity
    #expect(maximumError < 0.000_001)
  }

  @Test("golden fixture pins generator, model, Pillow, and artifact digests")
  func preprocessingFixtureProvenance() throws {
    let provenanceURL = try #require(
      Bundle.module.url(forResource: "preprocessing-provenance", withExtension: "json"))
    let payload = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: provenanceURL)) as? [String: Any])
    let artifacts = try #require(payload["artifacts"] as? [String: String])
    #expect(payload["producerCommit"] as? String == "7aa6474ca51c4c7e91cd4552093e7cc3424924b2")
    #expect(payload["modelPackageSHA256"] as? String == CoreMLEmbedder.packageSHA256)
    #expect(payload["pillowVersion"] as? String == "12.3.0")

    let generator = Self.repositoryRoot.appendingPathComponent(
      "Packages/FlukeML/Tests/FlukeMLTests/FixtureGeneration/generate_preprocessing_golden.py")
    let generatorData = try Data(contentsOf: generator)
    #expect(payload["generatorSHA256"] as? String == FixtureCatalog.sha256(generatorData))
    for (name, expectedDigest) in artifacts {
      let fixture = try #require(
        Bundle.module.url(
          forResource: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent,
          withExtension: URL(fileURLWithPath: name).pathExtension))
      let fixtureData = try Data(contentsOf: fixture)
      #expect(FixtureCatalog.sha256(fixtureData) == expectedDigest)
    }
  }

  @Test("preprocessor covers every EXIF orientation and both aspect-ratio branches")
  func orientationMappingsAndTargetSizes() {
    let preprocessor = CoreMLImagePreprocessor()
    let expected: [(CGImagePropertyOrientation, Int, Int)] = [
      (.up, 0, 0), (.upMirrored, 3, 0), (.down, 3, 2), (.downMirrored, 0, 2),
      (.leftMirrored, 0, 0), (.right, 0, 2), (.rightMirrored, 3, 2), (.left, 3, 0),
    ]
    for (orientation, expectedX, expectedY) in expected {
      let coordinate = preprocessor.sourceCoordinate(
        x: 0, y: 0, width: 4, height: 3, orientation: orientation)
      #expect(coordinate.x == expectedX)
      #expect(coordinate.y == expectedY)
    }

    let portrait = preprocessor.targetSize(width: 3, height: 5)
    let landscape = preprocessor.targetSize(width: 5, height: 3)
    #expect((portrait.width, portrait.height) == (256, 426))
    #expect((landscape.width, landscape.height) == (426, 256))
  }

  @Test("real packaged model loads, predicts, and matches the golden embedding")
  func actualPackagedModelParity() async throws {
    let sourceModel = Self.repositoryRoot
      .appendingPathComponent("App/Fluke/Models/FlukeEmbedder.mlpackage")
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    let modelCopy = temporaryDirectory.appendingPathComponent("FlukeEmbedder.mlpackage")
    try FileManager.default.copyItem(at: sourceModel, to: modelCopy)
    let compiledModel = try await MLModel.compileModel(at: modelCopy)
    let embedder = try await CoreMLEmbedder.load(compiledModelURL: compiledModel)
    let source = try Self.fixturePixelBuffer(named: "preprocessing-source", extension: "png")
    let frame = try CameraFrame(pixelBuffer: source, orientation: .right)

    let actual = try await embedder.embedding(frame: frame)
    let expected = try Self.fixtureFloats(named: "embedding-golden")
    #expect(actual.count == 384)
    #expect(Self.cosine(actual, expected) >= 0.999)
  }

  @Test("rejects non-finite and unnormalized model output")
  func rejectsInvalidEmbeddings() async throws {
    let frame = try CameraFrame(pixelBuffer: Self.redPixelBuffer(), orientation: .up)
    for values in [
      [.nan] + [Float](repeating: 0, count: 383),
      [Float](repeating: 0, count: 384),
    ] {
      let output = try Self.multiArray(values: values)
      let embedder = CoreMLEmbedder(predictor: FakeCoreMLPredictor(output: output))
      await #expect(throws: LocalIdentifierError.invalidEmbedding) {
        try await embedder.embedding(frame: frame)
      }
    }
  }

  @Test(
    "rejects output feature name, shape, and type drift",
    arguments: OutputDrift.allCases
  )
  func rejectsOutputContractDrift(_ drift: OutputDrift) async throws {
    let shape: [NSNumber] = drift == .shape ? [1, 383] : [1, 384]
    let dataType: MLMultiArrayDataType = drift == .dataType ? .float16 : .float32
    let output = try MLMultiArray(shape: shape, dataType: dataType)
    for index in 0..<output.count { output[index] = index == 0 ? 1 : 0 }
    let name = drift == .name ? "features" : "embedding"
    let embedder = CoreMLEmbedder(
      predictor: FakeCoreMLPredictor(outputName: name, output: output)
    )
    let frame = try CameraFrame(pixelBuffer: Self.redPixelBuffer(), orientation: .up)

    await #expect(throws: LocalIdentifierError.invalidModelOutput) {
      try await embedder.embedding(frame: frame)
    }
  }

  @Test("maps prediction failures to a stable user-facing error")
  func mapsPredictionFailure() async throws {
    let embedder = CoreMLEmbedder(predictor: FakeCoreMLPredictor(error: TestError.failed))
    let frame = try CameraFrame(pixelBuffer: Self.redPixelBuffer(), orientation: .up)

    await #expect(throws: LocalIdentifierError.predictionFailed) {
      try await embedder.embedding(frame: frame)
    }
  }

  @Test("missing compiled model fails closed")
  func missingModelResource() async {
    await #expect(throws: LocalIdentifierError.modelResourceMissing) {
      try await CoreMLEmbedder.load(bundle: Bundle.module)
    }
  }

  @Test("local identifier checks the production catalog before loading a model")
  func missingCatalogFailsBeforeModelLoad() async throws {
    let bundle = try Self.emptyBundle()
    defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }

    await #expect(throws: IdentifierArtifactError.self) {
      try await LocalIdentifier.load(bundle: bundle)
    }
  }

  @Test("local identifier errors expose bounded user-facing descriptions")
  func localErrorDescriptions() {
    let errors: [LocalIdentifierError] = [
      .modelResourceMissing, .modelLoadFailed, .invalidModelContract, .invalidModelOutput,
      .invalidEmbedding, .invalidPixelBuffer, .preprocessingFailed, .predictionFailed,
    ]
    #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
  }
}

extension CoreMLEmbedderTests {
  enum OutputDrift: CaseIterable {
    case name
    case shape
    case dataType
  }

  enum TestError: Error { case failed }

  struct FakeCoreMLPredictor: CoreMLPredicting, @unchecked Sendable {
    let outputName: String
    let output: MLMultiArray?
    let error: (any Error)?

    init(outputName: String = "embedding", output: MLMultiArray) {
      self.outputName = outputName
      self.output = output
      error = nil
    }

    init(error: any Error) {
      outputName = "embedding"
      output = nil
      self.error = error
    }

    func prediction(input _: MLMultiArray) throws -> CoreMLPrediction {
      if let error { throw error }
      return CoreMLPrediction(name: outputName, value: try #require(output))
    }
  }

  static var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static func fixtureFloats(named name: String) throws -> [Float] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "f32"))
    let data = try Data(contentsOf: url)
    #expect(data.count.isMultiple(of: MemoryLayout<UInt32>.size))
    return stride(from: 0, to: data.count, by: 4).map { offset in
      let bits = data.withUnsafeBytes { raw in
        UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
      }
      return Float(bitPattern: bits)
    }
  }

  static func fixturePixelBuffer(named name: String, extension fileExtension: String) throws
    -> CVPixelBuffer
  {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: fileExtension))
    let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    let buffer = try pixelBuffer(width: image.width, height: image.height) { _, _ in (0, 0, 0, 0) }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(buffer))
    let context = try #require(
      CGContext(
        data: base,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
          | CGImageAlphaInfo.premultipliedFirst.rawValue
      ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
  }

  static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
    let products = zip(lhs, rhs).map(*)
    let lhsNorm = sqrt(lhs.map { $0 * $0 }.reduce(0, +))
    let rhsNorm = sqrt(rhs.map { $0 * $0 }.reduce(0, +))
    return products.reduce(0, +) / (lhsNorm * rhsNorm)
  }

  static func multiArray(values: [Float]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .float32)
    for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
    return array
  }

  static func redPixelBuffer(width: Int = 1, height: Int = 1) throws -> CVPixelBuffer {
    try pixelBuffer(width: width, height: height) { _, _ in (255, 0, 0, 255) }
  }

  static func monochromePixelBuffer(value: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, 1, 1, kCVPixelFormatType_OneComponent8, nil, &buffer
      ) == kCVReturnSuccess, let buffer
    else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(buffer))
      .assumingMemoryBound(to: UInt8.self)
    base[0] = value
    return buffer
  }

  static func emptyBundle() throws -> Bundle {
    let bundleURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
    let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": "app.fluke.tests.empty",
      "CFBundlePackageType": "BNDL",
      "CFBundleVersion": "1",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return try #require(Bundle(url: bundleURL))
  }

  static func overwrite(
    _ buffer: CVPixelBuffer,
    rgba: (UInt8, UInt8, UInt8, UInt8)
  ) throws {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(buffer))
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<CVPixelBufferGetHeight(buffer) {
      let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<CVPixelBufferGetWidth(buffer) {
        row[x * 4] = rgba.2
        row[x * 4 + 1] = rgba.1
        row[x * 4 + 2] = rgba.0
        row[x * 4 + 3] = rgba.3
      }
    }
  }

  static func pixelBuffer(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
      let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let value = pixel(x, y)
        row[x * 4] = value.2
        row[x * 4 + 1] = value.1
        row[x * 4 + 2] = value.0
        row[x * 4 + 3] = value.3
      }
    }
    return buffer
  }
}
