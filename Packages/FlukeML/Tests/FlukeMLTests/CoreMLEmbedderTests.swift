import CoreML
import CoreVideo
import ImageIO
import Testing

@testable import FlukeML

@Suite("Core ML embedder")
struct CoreMLEmbedderTests {
  @Test("rejects non-finite model output")
  func rejectsNonFiniteEmbedding() async throws {
    let output = try Self.multiArray(values: [.nan] + [Float](repeating: 0, count: 383))
    let embedder = CoreMLEmbedder(predictor: FakeCoreMLPredictor(output: output))

    await #expect(throws: LocalIdentifierError.invalidEmbedding) {
      try await embedder.embedding(pixelBuffer: Self.redPixelBuffer(), orientation: .up)
    }
  }

  @Test("rejects model output that is not L2 normalized")
  func rejectsUnnormalizedEmbedding() async throws {
    let output = try Self.multiArray(values: [Float](repeating: 0, count: 384))
    let embedder = CoreMLEmbedder(predictor: FakeCoreMLPredictor(output: output))

    await #expect(throws: LocalIdentifierError.invalidEmbedding) {
      try await embedder.embedding(pixelBuffer: Self.redPixelBuffer(), orientation: .up)
    }
  }

  @Test(
    "rejects output feature name, shape, and type drift",
    arguments: [
      OutputDrift.name,
      .shape,
      .dataType,
    ])
  func rejectsOutputContractDrift(_ drift: OutputDrift) async throws {
    let shape: [NSNumber] = drift == .shape ? [1, 383] : [1, 384]
    let dataType: MLMultiArrayDataType = drift == .dataType ? .float16 : .float32
    let output = try MLMultiArray(shape: shape, dataType: dataType)
    for index in 0..<output.count { output[index] = index == 0 ? 1 : 0 }
    let name = drift == .name ? "features" : "embedding"
    let embedder = CoreMLEmbedder(
      predictor: FakeCoreMLPredictor(outputName: name, output: output)
    )

    await #expect(throws: LocalIdentifierError.invalidModelOutput) {
      try await embedder.embedding(pixelBuffer: Self.redPixelBuffer(), orientation: .up)
    }
  }

  @Test("preprocessing produces golden RGB ImageNet tensor values")
  func goldenRGBPreprocessing() throws {
    let input = try CoreMLImagePreprocessor().makeInput(
      pixelBuffer: Self.redPixelBuffer(width: 320, height: 180),
      orientation: .up
    )
    let plane = 224 * 224

    #expect(abs(input[0].floatValue - ((1 - 0.485) / 0.229)) < 0.000_1)
    #expect(abs(input[plane].floatValue - ((0 - 0.456) / 0.224)) < 0.000_1)
    #expect(abs(input[plane * 2].floatValue - ((0 - 0.406) / 0.225)) < 0.000_1)
    #expect(input.shape == [1, 3, 224, 224])
    #expect(input.dataType == .float32)
  }

  @Test("preprocessing applies orientation before shortest-edge resize and center crop")
  func orientationBeforeCrop() throws {
    let source = try Self.horizontalBandsPixelBuffer(width: 300, height: 200)
    let input = try CoreMLImagePreprocessor().makeInput(
      pixelBuffer: source,
      orientation: .right
    )
    let plane = 224 * 224
    let topCenter = 16 * 224 + 112
    let bottomCenter = 208 * 224 + 112

    #expect(input[topCenter].floatValue > 1)
    #expect(input[topCenter + plane * 2].floatValue < 0)
    #expect(input[bottomCenter].floatValue < 0)
    #expect(input[bottomCenter + plane * 2].floatValue > 1)
  }
}

extension CoreMLEmbedderTests {
  enum OutputDrift: CaseIterable {
    case name
    case shape
    case dataType
  }

  struct FakeCoreMLPredictor: CoreMLPredicting, @unchecked Sendable {
    let outputName: String
    let output: MLMultiArray

    init(outputName: String = "embedding", output: MLMultiArray) {
      self.outputName = outputName
      self.output = output
    }

    func prediction(input _: MLMultiArray) throws -> CoreMLPrediction {
      CoreMLPrediction(name: outputName, value: output)
    }
  }

  static func multiArray(values: [Float]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .float32)
    for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
    return array
  }

  static func redPixelBuffer(width: Int = 1, height: Int = 1) throws -> CVPixelBuffer {
    try pixelBuffer(width: width, height: height) { _, _ in (255, 0, 0, 255) }
  }

  static func horizontalBandsPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    try pixelBuffer(width: width, height: height) { x, _ in
      if x < width / 3 { return (255, 0, 0, 255) }
      if x < (width * 2) / 3 { return (0, 255, 0, 255) }
      return (0, 0, 255, 255)
    }
  }

  static func pixelBuffer(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      nil,
      &buffer
    )
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
