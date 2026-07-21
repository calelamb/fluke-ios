import CoreGraphics
import Foundation
import FlukeReleaseB
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Image processing")
struct ImageProcessorTests {
  @Test("Image processor rejects unsupported and decompression-bomb inputs")
  func rejectsUnsafeInput() throws {
    #expect(throws: ImageProcessingError.unsupportedFormat) {
      try ImageProcessor.process(Data("not an image".utf8))
    }
    let oversized = try makeJPEG(width: 10_000, height: 10_000)
    #expect(throws: ImageProcessingError.decompressionLimit) {
      try ImageProcessor.process(oversized)
    }
  }

  @Test("Image processor applies orientation, bounds the longest edge, emits JPEG, and strips metadata")
  func normalizesImage() throws {
    let input = try makeJPEG(width: 3_000, height: 1_500, orientation: 6)
    let output = try ImageProcessor.process(input)
    let source = CGImageSourceCreateWithData(output.bytes as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]

    #expect(CGImageSourceGetType(source) == UTType.jpeg.identifier as CFString)
    #expect(max(properties[kCGImagePropertyPixelWidth] as! Int, properties[kCGImagePropertyPixelHeight] as! Int) <= 2_048)
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
    #expect(properties[kCGImagePropertyOrientation] == nil || properties[kCGImagePropertyOrientation] as? Int == 1)
    #expect(output.bytes.count <= 10 * 1_024 * 1_024)
  }
}

private func makeJPEG(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
  let bytes = [UInt8](repeating: 100, count: width * height * 4)
  let provider = CGDataProvider(data: Data(bytes) as CFData)!
  let image = CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
  )!
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
  var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
  if let orientation { properties[kCGImagePropertyOrientation] = orientation }
  CGImageDestinationAddImage(destination, image, properties as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.encodingFailed }
  return data as Data
}
