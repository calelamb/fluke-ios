import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageProcessingError: Error, Equatable, Sendable {
  case unsupportedFormat
  case decompressionLimit
  case encodingFailed
  case outputTooLarge
}

public enum ImageProcessor {
  public static let maximumDimension = 2_048
  public static let maximumDecodedPixels = 40_000_000
  public static let maximumOutputBytes = 10 * 1_024 * 1_024

  public static func process(_ input: Data) throws -> ProcessedPhoto {
    guard let source = CGImageSourceCreateWithData(input as CFData, nil),
      let type = CGImageSourceGetType(source),
      type == UTType.jpeg.identifier as CFString || type == UTType.heic.identifier as CFString,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw ImageProcessingError.unsupportedFormat }
    let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, pixelCount <= maximumDecodedPixels else {
      throw ImageProcessingError.decompressionLimit
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw ImageProcessingError.unsupportedFormat
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      output, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw ImageProcessingError.encodingFailed }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.encodingFailed }
    let bytes = output as Data
    guard bytes.count <= maximumOutputBytes else { throw ImageProcessingError.outputTooLarge }
    return ProcessedPhoto(bytes: bytes, fileName: "\(UUID().uuidString).jpg")
  }
}
