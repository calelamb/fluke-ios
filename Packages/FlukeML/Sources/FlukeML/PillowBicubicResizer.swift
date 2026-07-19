import Foundation

struct RGBImage: Sendable {
  let width: Int
  let height: Int
  let bytes: [UInt8]
}

struct PillowBicubicResizer: Sendable {
  private static let precisionBits = 22
  private static let fixedScale = Double(1 << precisionBits)
  private static let roundingBias = Int64(1 << (precisionBits - 1))

  func resize(_ image: RGBImage, width: Int, height: Int) -> RGBImage {
    let horizontal = resampleHorizontally(image, width: width)
    return resampleVertically(horizontal, height: height)
  }
}

extension PillowBicubicResizer {
  fileprivate struct Coefficients {
    let start: Int
    let weights: [Int64]
  }

  fileprivate func resampleHorizontally(_ image: RGBImage, width: Int) -> RGBImage {
    guard width != image.width else { return image }
    let coefficients = makeCoefficients(inputSize: image.width, outputSize: width)
    var output = [UInt8](repeating: 0, count: width * image.height * 3)
    for y in 0..<image.height {
      for x in 0..<width {
        let values = coefficients[x]
        for channel in 0..<3 {
          var accumulator = Self.roundingBias
          for (offset, weight) in values.weights.enumerated() {
            let index = (y * image.width + values.start + offset) * 3 + channel
            accumulator += Int64(image.bytes[index]) * weight
          }
          output[(y * width + x) * 3 + channel] = clipped(accumulator >> Self.precisionBits)
        }
      }
    }
    return RGBImage(width: width, height: image.height, bytes: output)
  }

  fileprivate func resampleVertically(_ image: RGBImage, height: Int) -> RGBImage {
    guard height != image.height else { return image }
    let coefficients = makeCoefficients(inputSize: image.height, outputSize: height)
    var output = [UInt8](repeating: 0, count: image.width * height * 3)
    for y in 0..<height {
      let values = coefficients[y]
      for x in 0..<image.width {
        for channel in 0..<3 {
          var accumulator = Self.roundingBias
          for (offset, weight) in values.weights.enumerated() {
            let index = ((values.start + offset) * image.width + x) * 3 + channel
            accumulator += Int64(image.bytes[index]) * weight
          }
          output[(y * image.width + x) * 3 + channel] = clipped(
            accumulator >> Self.precisionBits)
        }
      }
    }
    return RGBImage(width: image.width, height: height, bytes: output)
  }

  fileprivate func makeCoefficients(inputSize: Int, outputSize: Int) -> [Coefficients] {
    let scale = Double(inputSize) / Double(outputSize)
    let filterScale = max(scale, 1)
    let support = 2 * filterScale
    return (0..<outputSize).map { outputIndex in
      let center = (Double(outputIndex) + 0.5) * scale
      let start = max(0, Int(center - support + 0.5))
      let end = min(inputSize, Int(center + support + 0.5))
      let rawWeights = (start..<end).map { inputIndex in
        bicubic((Double(inputIndex) - center + 0.5) / filterScale)
      }
      let sum = rawWeights.reduce(0, +)
      let fixedWeights = rawWeights.map { weight -> Int64 in
        let normalized = sum == 0 ? 0 : weight / sum
        let rounded =
          normalized < 0
          ? normalized * Self.fixedScale - 0.5
          : normalized * Self.fixedScale + 0.5
        return Int64(rounded)
      }
      return Coefficients(start: start, weights: fixedWeights)
    }
  }

  fileprivate func bicubic(_ value: Double) -> Double {
    let x = abs(value)
    if x < 1 {
      return ((1.5 * x - 2.5) * x * x) + 1
    }
    if x < 2 {
      return (((x - 5) * x + 8) * x - 4) * -0.5
    }
    return 0
  }

  fileprivate func clipped(_ value: Int64) -> UInt8 {
    UInt8(clamping: Int(value))
  }
}
