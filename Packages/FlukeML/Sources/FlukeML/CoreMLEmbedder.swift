import CoreML
import Foundation

public actor CoreMLEmbedder: EmbeddingProviding {
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
    return try await load(compiledModelURL: url)
  }

  static func load(compiledModelURL: URL) async throws -> CoreMLEmbedder {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    do {
      let model = try await MLModel.load(contentsOf: compiledModelURL, configuration: configuration)
      try validate(model: model)
      return CoreMLEmbedder(predictor: MLModelPredictor(model: model))
    } catch let error as LocalIdentifierError {
      throw error
    } catch {
      throw LocalIdentifierError.modelLoadFailed
    }
  }

  public func embedding(frame: CameraFrame) async throws -> [Float] {
    let input: MLMultiArray
    do {
      input = try preprocessor.makeInput(frame: frame)
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
    guard prediction.name == "embedding",
      prediction.isFloat32,
      prediction.shape == [1, expectedOutputCount],
      prediction.values.count == expectedOutputCount
    else {
      throw LocalIdentifierError.invalidModelOutput
    }
    let result = prediction.values
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

struct CoreMLPrediction: Sendable {
  let name: String
  let isFloat32: Bool
  let shape: [Int]
  let values: [Float]

  init(name: String, value: MLMultiArray) {
    self.name = name
    isFloat32 = value.dataType == .float32
    shape = value.shape.map(\.intValue)
    values = (0..<value.count).map { value[$0].floatValue }
  }
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
