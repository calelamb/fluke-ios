import CoreImage
import CoreML
@preconcurrency import CoreVideo
import Foundation
import ImageIO

public actor CoreMLEmbedder: @preconcurrency EmbeddingProviding {
  public static let packageSHA256 =
    "e784dac753edb2b70dd31d1a74208b736cf805c0e34b87d81a7bad11e1c13109"
  public static let artifactCompatibility = IdentifierArtifactCompatibility(
    modelID: "facebook/dinov2-small",
    modelRevision: "ed25f3a31f01632728cabb09d1542f84ab7b0056",
    modelVersion: "dinov2-small-coreml-v1",
    modelSHA256: packageSHA256,
    preprocessingVersion: "dinov2-imagenet-v1",
    indexVersion: "mobile-reference-v1"
  )

  private static let resourceName = "FlukeEmbedder"
  private static let compiledExtension = "mlmodelc"
  private static let expectedOutputCount = 384
  private static let normTolerance: Float = 0.001

  private let predictor: any CoreMLPredicting
  private let preprocessor: CoreMLImagePreprocessor

  init(
    predictor: any CoreMLPredicting,
    preprocessor: CoreMLImagePreprocessor = CoreMLImagePreprocessor()
  ) {
    self.predictor = predictor
    self.preprocessor = preprocessor
  }

  public static func load(bundle: Bundle = .main) async throws -> CoreMLEmbedder {
    guard let url = compiledModelURL(in: bundle) else {
      throw LocalIdentifierError.modelResourceMissing
    }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    do {
      let model = try await MLModel.load(contentsOf: url, configuration: configuration)
      try validate(model: model)
      return CoreMLEmbedder(predictor: MLModelPredictor(model: model))
    } catch let error as LocalIdentifierError {
      throw error
    } catch {
      throw LocalIdentifierError.modelLoadFailed
    }
  }

  public func embedding(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) async throws -> [Float] {
    let input: MLMultiArray
    do {
      input = try preprocessor.makeInput(
        pixelBuffer: pixelBuffer,
        orientation: orientation
      )
    } catch let error as LocalIdentifierError {
      throw error
    } catch {
      throw LocalIdentifierError.preprocessingFailed
    }

    let prediction: CoreMLPrediction
    do {
      prediction = try predictor.prediction(input: input)
    } catch let error as LocalIdentifierError {
      throw error
    } catch {
      throw LocalIdentifierError.predictionFailed
    }
    return try Self.validatedEmbedding(prediction)
  }
}

extension CoreMLEmbedder {
  static func compiledModelURL(in bundle: Bundle) -> URL? {
    bundle.url(forResource: resourceName, withExtension: compiledExtension)
      ?? bundle.url(
        forResource: resourceName,
        withExtension: compiledExtension,
        subdirectory: "Models"
      )
  }

  static func validate(model: MLModel) throws {
    let description = model.modelDescription
    guard Set(description.inputDescriptionsByName.keys) == ["pixels"],
      Set(description.outputDescriptionsByName.keys) == ["embedding"],
      validFeature(
        description.inputDescriptionsByName["pixels"],
        shape: [1, 3, 224, 224]
      ),
      validFeature(
        description.outputDescriptionsByName["embedding"],
        shape: [1, expectedOutputCount]
      )
    else {
      throw LocalIdentifierError.invalidModelContract
    }
  }

  static func validFeature(_ feature: MLFeatureDescription?, shape: [Int]) -> Bool {
    guard let feature,
      feature.type == .multiArray,
      let constraint = feature.multiArrayConstraint,
      constraint.dataType == .float32
    else {
      return false
    }
    return constraint.shape.map(\.intValue) == shape
  }

  static func validatedEmbedding(_ prediction: CoreMLPrediction) throws -> [Float] {
    let value = prediction.value
    guard prediction.name == "embedding",
      value.dataType == .float32,
      value.shape.map(\.intValue) == [1, expectedOutputCount],
      value.count == expectedOutputCount
    else {
      throw LocalIdentifierError.invalidModelOutput
    }
    let result = (0..<value.count).map { value[$0].floatValue }
    guard result.allSatisfy(\.isFinite) else {
      throw LocalIdentifierError.invalidEmbedding
    }
    let squaredNorm = result.reduce(Float.zero) { $0 + $1 * $1 }
    guard squaredNorm.isFinite,
      abs(sqrt(squaredNorm) - 1) <= normTolerance
    else {
      throw LocalIdentifierError.invalidEmbedding
    }
    return result
  }
}

struct CoreMLPrediction: @unchecked Sendable {
  let name: String
  let value: MLMultiArray
}

protocol CoreMLPredicting: Sendable {
  func prediction(input: MLMultiArray) throws -> CoreMLPrediction
}

// The containing CoreMLEmbedder actor is the only owner and serializes every model prediction.
private final class MLModelPredictor: CoreMLPredicting, @unchecked Sendable {
  private let model: MLModel

  init(model: MLModel) {
    self.model = model
  }

  func prediction(input: MLMultiArray) throws -> CoreMLPrediction {
    let features = try MLDictionaryFeatureProvider(dictionary: ["pixels": input])
    let output = try model.prediction(from: features)
    guard Set(output.featureNames) == ["embedding"],
      let value = output.featureValue(for: "embedding")?.multiArrayValue
    else {
      throw LocalIdentifierError.invalidModelOutput
    }
    return CoreMLPrediction(name: "embedding", value: value)
  }
}

struct CoreMLImagePreprocessor: Sendable {
  private static let resizeShortestEdge = 256
  private static let cropSize = 224
  private static let means: [Float] = [0.485, 0.456, 0.406]
  private static let standardDeviations: [Float] = [0.229, 0.224, 0.225]

  func makeInput(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) throws -> MLMultiArray {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0 else { throw LocalIdentifierError.invalidPixelBuffer }

    let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    let normalized = image.transformed(
      by: CGAffineTransform(
        translationX: -image.extent.minX,
        y: -image.extent.minY
      )
    )
    let target = targetSize(
      width: Int(normalized.extent.width), height: Int(normalized.extent.height))
    let resized = try bicubicResize(normalized, target: target)
    let crop = CGRect(
      x: (target.width - Self.cropSize) / 2,
      y: (target.height - Self.cropSize) / 2,
      width: Self.cropSize,
      height: Self.cropSize
    )
    let cropped = resized.cropped(to: crop).transformed(
      by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
    )
    let bytes = try renderedRGBBytes(cropped)
    return try normalizedTensor(bytes)
  }
}

extension CoreMLImagePreprocessor {
  fileprivate struct PixelSize {
    let width: Int
    let height: Int
  }

  fileprivate func targetSize(width: Int, height: Int) -> PixelSize {
    if width <= height {
      return PixelSize(
        width: Self.resizeShortestEdge,
        height: Self.resizeShortestEdge * height / width
      )
    }
    return PixelSize(
      width: Self.resizeShortestEdge * width / height,
      height: Self.resizeShortestEdge
    )
  }

  fileprivate func bicubicResize(_ image: CIImage, target: PixelSize) throws -> CIImage {
    guard let filter = CIFilter(name: "CIBicubicScaleTransform") else {
      throw LocalIdentifierError.preprocessingFailed
    }
    let scaleY = CGFloat(target.height) / image.extent.height
    let scaleX = CGFloat(target.width) / image.extent.width
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(scaleY, forKey: kCIInputScaleKey)
    filter.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
    filter.setValue(0, forKey: "inputB")
    filter.setValue(0.5, forKey: "inputC")
    guard let output = filter.outputImage else {
      throw LocalIdentifierError.preprocessingFailed
    }
    return output
  }

  fileprivate func renderedRGBBytes(_ image: CIImage) throws -> [UInt8] {
    let rowBytes = Self.cropSize * 4
    var bytes = [UInt8](repeating: 0, count: rowBytes * Self.cropSize)
    let context = CIContext(options: [.cacheIntermediates: false])
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw LocalIdentifierError.preprocessingFailed
    }
    context.render(
      image,
      toBitmap: &bytes,
      rowBytes: rowBytes,
      bounds: CGRect(x: 0, y: 0, width: Self.cropSize, height: Self.cropSize),
      format: .RGBA8,
      colorSpace: colorSpace
    )
    return bytes
  }

  fileprivate func normalizedTensor(_ bytes: [UInt8]) throws -> MLMultiArray {
    let tensor = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
    let planeSize = Self.cropSize * Self.cropSize
    let values = tensor.dataPointer.bindMemory(to: Float32.self, capacity: tensor.count)
    for pixelIndex in 0..<planeSize {
      let byteIndex = pixelIndex * 4
      for channel in 0..<3 {
        let rescaled = Float(bytes[byteIndex + channel]) / 255
        values[channel * planeSize + pixelIndex] =
          (rescaled - Self.means[channel]) / Self.standardDeviations[channel]
      }
    }
    return tensor
  }
}
