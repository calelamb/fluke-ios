import CoreML
import Foundation
import ImageIO

struct CoreMLImagePreprocessor: Sendable {
  private static let resizeShortestEdge = 256
  private static let cropSize = 224
  private static let means: [Float] = [0.485, 0.456, 0.406]
  private static let standardDeviations: [Float] = [0.229, 0.224, 0.225]

  func makeInput(frame: CameraFrame) throws -> MLMultiArray {
    guard frame.rgbBytes.count == frame.width * frame.height * 3 else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    let oriented = orient(
      RGBImage(width: frame.width, height: frame.height, bytes: frame.rgbBytes),
      orientation: frame.orientation
    )
    let target = targetSize(width: oriented.width, height: oriented.height)
    let resized = PillowBicubicResizer().resize(
      oriented, width: target.width, height: target.height)
    let cropped = centerCrop(resized)
    return try normalizedTensor(cropped.bytes)
  }
}

extension CoreMLImagePreprocessor {
  struct PixelSize {
    let width: Int
    let height: Int
  }

  func targetSize(width: Int, height: Int) -> PixelSize {
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

  func orient(_ image: RGBImage, orientation: CGImagePropertyOrientation) -> RGBImage {
    let swapsDimensions = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
    let outputWidth = swapsDimensions ? image.height : image.width
    let outputHeight = swapsDimensions ? image.width : image.height
    var output = [UInt8](repeating: 0, count: image.bytes.count)
    for y in 0..<outputHeight {
      for x in 0..<outputWidth {
        let source = sourceCoordinate(
          x: x, y: y, width: image.width, height: image.height, orientation: orientation)
        let sourceIndex = (source.y * image.width + source.x) * 3
        let outputIndex = (y * outputWidth + x) * 3
        output[outputIndex..<(outputIndex + 3)] = image.bytes[sourceIndex..<(sourceIndex + 3)]
      }
    }
    return RGBImage(width: outputWidth, height: outputHeight, bytes: output)
  }

  func sourceCoordinate(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
  ) -> (x: Int, y: Int) {
    switch orientation {
    case .up: (x, y)
    case .upMirrored: (width - 1 - x, y)
    case .down: (width - 1 - x, height - 1 - y)
    case .downMirrored: (x, height - 1 - y)
    case .leftMirrored: (y, x)
    case .right: (y, height - 1 - x)
    case .rightMirrored: (width - 1 - y, height - 1 - x)
    case .left: (width - 1 - y, x)
    @unknown default: (x, y)
    }
  }

  func centerCrop(_ image: RGBImage) -> RGBImage {
    let left = (image.width - Self.cropSize) / 2
    let top = (image.height - Self.cropSize) / 2
    var output = [UInt8]()
    output.reserveCapacity(Self.cropSize * Self.cropSize * 3)
    for y in 0..<Self.cropSize {
      let start = ((top + y) * image.width + left) * 3
      output.append(contentsOf: image.bytes[start..<(start + Self.cropSize * 3)])
    }
    return RGBImage(width: Self.cropSize, height: Self.cropSize, bytes: output)
  }

  func normalizedTensor(_ bytes: [UInt8]) throws -> MLMultiArray {
    let tensor = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
    let planeSize = Self.cropSize * Self.cropSize
    let values = tensor.dataPointer.bindMemory(to: Float32.self, capacity: tensor.count)
    for pixelIndex in 0..<planeSize {
      for channel in 0..<3 {
        let rescaled = Float(bytes[pixelIndex * 3 + channel]) / 255
        values[channel * planeSize + pixelIndex] =
          (rescaled - Self.means[channel]) / Self.standardDeviations[channel]
      }
    }
    return tensor
  }
}
