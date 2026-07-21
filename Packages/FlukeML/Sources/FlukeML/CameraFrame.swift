import CoreImage
@preconcurrency import CoreVideo
import Foundation
import ImageIO

public struct CameraFrame: Sendable {
  public let width: Int
  public let height: Int
  public let orientation: CGImagePropertyOrientation
  let rgbBytes: [UInt8]

  public init(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) throws {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0 else { throw LocalIdentifierError.invalidPixelBuffer }

    let status = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard status == kCVReturnSuccess else { throw LocalIdentifierError.invalidPixelBuffer }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    self.width = width
    self.height = height
    self.orientation = orientation
    rgbBytes = try Self.copyRGBBytes(from: pixelBuffer, width: width, height: height)
  }
}

extension CameraFrame {
  private static func copyRGBBytes(
    from pixelBuffer: CVPixelBuffer,
    width: Int,
    height: Int
  ) throws -> [UInt8] {
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    if format == kCVPixelFormatType_32BGRA {
      return try copyPackedRGBBytes(from: pixelBuffer, width: width, height: height)
    }
    return try renderRGBBytes(from: pixelBuffer, width: width, height: height)
  }

  private static func copyPackedRGBBytes(
    from pixelBuffer: CVPixelBuffer,
    width: Int,
    height: Int
  ) throws -> [UInt8] {
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    var result = [UInt8]()
    result.reserveCapacity(width * height * 3)
    for y in 0..<height {
      let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let offset = x * 4
        result.append(contentsOf: [row[offset + 2], row[offset + 1], row[offset]])
      }
    }
    return result
  }

  private static func renderRGBBytes(
    from pixelBuffer: CVPixelBuffer,
    width: Int,
    height: Int
  ) throws -> [UInt8] {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw LocalIdentifierError.preprocessingFailed
    }
    let rowBytes = width * 4
    var rgba = [UInt8](repeating: 0, count: rowBytes * height)
    CIContext(options: [.cacheIntermediates: false]).render(
      CIImage(cvPixelBuffer: pixelBuffer),
      toBitmap: &rgba,
      rowBytes: rowBytes,
      bounds: CGRect(x: 0, y: 0, width: width, height: height),
      format: .RGBA8,
      colorSpace: colorSpace
    )
    var result = [UInt8]()
    result.reserveCapacity(width * height * 3)
    for offset in stride(from: 0, to: rgba.count, by: 4) {
      result.append(contentsOf: rgba[offset..<(offset + 3)])
    }
    return result
  }
}
