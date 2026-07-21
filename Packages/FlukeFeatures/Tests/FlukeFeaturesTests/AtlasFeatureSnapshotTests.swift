import AppKit
import FlukeKit
import FlukeUI
import SwiftUI
import XCTest

@testable import FlukeFeatures

@MainActor
final class AtlasFeatureSnapshotTests: XCTestCase {
  private let metadata = BrowseMetadata(
    fetchedAt: Date(timeIntervalSince1970: 1_768_435_200),
    schemaVersion: 1
  )

  func test_timelineRendersTheFeatureComposition() throws {
    try assertModeSnapshot(AtlasTimelineSnapshot(metadata: metadata), named: "timeline")
  }

  func test_rangeRendersTheFeatureComposition() throws {
    try assertModeSnapshot(AtlasRangeSnapshot(metadata: metadata), named: "range")
  }

  func test_traceRendersTheFeatureComposition() throws {
    try assertModeSnapshot(AtlasTraceSnapshot(metadata: metadata), named: "trace")
  }

  func test_predictRendersTheFeatureComposition() throws {
    try assertModeSnapshot(AtlasPredictSnapshot(metadata: metadata), named: "predict")
  }

  func test_timelineAdaptsAtAccessibilityTextSize() throws {
    let image = try render(
      AtlasTimelineSnapshot(metadata: metadata)
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 430, height: 760),
      size: CGSize(width: 430, height: 760)
    )

    try assertFeatureSnapshot(image, named: "timeline-accessibility3")
  }

  func test_snapshotBaselinesSelectThePinnedCIRunner() {
    XCTAssertEqual(
      atlasSnapshotReferenceName(
        named: "timeline",
        version: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0)
      ),
      "timeline.macos-15.png"
    )
    XCTAssertEqual(
      atlasSnapshotReferenceName(
        named: "timeline",
        version: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
      ),
      "timeline.png"
    )
  }

  private func assertModeSnapshot<Content: View>(
    _ content: Content,
    named name: String
  ) throws {
    let image = try render(
      content.frame(width: 430, height: 540),
      size: CGSize(width: 430, height: 540)
    )
    try assertFeatureSnapshot(image, named: name)
  }
}

private struct AtlasTimelineSnapshot: View {
  let metadata: BrowseMetadata

  var body: some View {
    TimelineSubView(
      repository: SnapshotHistoryRepository(
        result: .cachedOffline(
          payload: .value([snapshotHistoricalSighting]),
          metadata: metadata
        )),
      catalog: [snapshotWhale],
      initialState: .content(
        [snapshotHistoricalSighting],
        notice: .offline,
        isRefreshing: false
      ),
      loadsAutomatically: false
    )
  }
}

private struct AtlasRangeSnapshot: View {
  let metadata: BrowseMetadata

  var body: some View {
    let failure = snapshotStaleFailure
    RangeSubView(
      repository: SnapshotHistoryRepository(
        result: .stale(
          payload: .empty,
          metadata: metadata,
          failure: failure
        )),
      initialState: .empty(notice: .stale(failure), isRefreshing: false),
      loadsAutomatically: false
    )
  }
}

private struct AtlasTraceSnapshot: View {
  let metadata: BrowseMetadata

  var body: some View {
    TraceSubView(
      repository: SnapshotWhalesRepository(
        result: .cachedOffline(
          payload: .value([snapshotMovementPoint]),
          metadata: metadata
        )),
      catalog: [snapshotWhale],
      initialWhaleID: snapshotWhale.id,
      initialState: .content(
        [snapshotMovementPoint],
        notice: .offline,
        isRefreshing: false
      ),
      loadsAutomatically: false
    )
  }
}

private struct AtlasPredictSnapshot: View {
  let metadata: BrowseMetadata

  var body: some View {
    PredictSubView(
      repository: SnapshotPredictionRepository(
        result: .cachedOffline(
          payload: .empty,
          metadata: metadata
        )),
      catalog: [snapshotWhale],
      initialState: .empty(notice: .offline, isRefreshing: false),
      initialSubject: .pod(.j),
      loadsAutomatically: false
    )
  }
}

private actor SnapshotHistoryRepository: HistoricalSightingsRepositoryProtocol {
  let result: BrowseResult<[HistoricalSighting]>

  init(result: BrowseResult<[HistoricalSighting]>) {
    self.result = result
  }

  func load(from: Date, to: Date, pod: Pod?) async throws -> BrowseResult<[HistoricalSighting]> {
    result
  }
}

private actor SnapshotWhalesRepository: WhalesRepositoryProtocol {
  let result: BrowseResult<[MovementTrackPoint]>

  init(result: BrowseResult<[MovementTrackPoint]>) {
    self.result = result
  }

  func loadCatalog() async throws -> BrowseResult<[Whale]> {
    .fresh(
      value: [snapshotWhale],
      metadata: BrowseMetadata(
        fetchedAt: Date(timeIntervalSince1970: 1_768_435_200), schemaVersion: 1)
    )
  }

  func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
    .empty(metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1))
  }

  func loadTrack(
    whaleId: String,
    from: Date,
    to: Date
  ) async throws -> BrowseResult<[MovementTrackPoint]> {
    result
  }
}

private actor SnapshotPredictionRepository: PredictionRepositoryProtocol {
  let result: BrowseResult<Prediction?>

  init(result: BrowseResult<Prediction?>) {
    self.result = result
  }

  func load(
    subject: PredictionRepository.Subject,
    horizon: PredictionHorizon
  ) async throws -> BrowseResult<Prediction?> {
    result
  }
}

private let snapshotHistoricalSighting = HistoricalSighting(
  id: "snapshot-history",
  observedAt: Date(timeIntervalSince1970: 1_767_225_600),
  latitude: 48.5,
  longitude: -123.2,
  locationName: "Haro Strait",
  ecotypeGuess: .resident,
  whaleIds: ["J35"]
)

private let snapshotMovementPoint = MovementTrackPoint(
  id: "snapshot-track",
  observedAt: Date(timeIntervalSince1970: 1_767_225_600),
  latitude: 48.5,
  longitude: -123.2,
  locationName: "Haro Strait",
  behaviorNotes: nil
)

private let snapshotWhale = makeWhale(
  id: "snapshot-j35",
  catalogId: "J35",
  name: "Tahlequah",
  ecotype: .resident,
  pod: "J"
)

private let snapshotStaleFailure = BrowseFailure(
  code: "STALE",
  message: "Showing saved Atlas data.",
  retryable: true,
  requestId: nil
)

@MainActor
private func render<V: View>(_ view: V, size: CGSize) throws -> NSImage {
  FlukeUIFontRegistration.registerIfNeeded()
  let renderer = ImageRenderer(content: view)
  renderer.proposedSize = ProposedViewSize(size)
  renderer.scale = 1
  return try XCTUnwrap(renderer.nsImage, "Atlas feature view did not render")
}

private func assertFeatureSnapshot(
  _ image: NSImage,
  named name: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let referenceName = atlasSnapshotReferenceName(named: name)
  let referenceURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "__Snapshots__")
    .appending(path: "AtlasFeatureSnapshotTests")
    .appending(path: referenceName)
  try writeSnapshotArtifactIfConfigured(image, named: referenceName)
  let actual = try rgbaPixels(image)

  if ProcessInfo.processInfo.environment["FLUKE_RECORD_ATLAS_SNAPSHOTS"] == "1" {
    try FileManager.default.createDirectory(
      at: referenceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try pngData(image).write(to: referenceURL, options: .atomic)
    XCTFail(
      "Recorded Atlas feature snapshot \(name); rerun without record mode", file: file, line: line)
    return
  }

  let referenceImage = try XCTUnwrap(
    NSImage(contentsOf: referenceURL),
    "Missing Atlas feature snapshot \(referenceURL.path)",
    file: file,
    line: line
  )
  let expected = try rgbaPixels(referenceImage)
  XCTAssertEqual(actual.width, expected.width, file: file, line: line)
  XCTAssertEqual(actual.height, expected.height, file: file, line: line)
  guard actual.bytes.count == expected.bytes.count else { return }

  let differingPixels = stride(from: 0, to: actual.bytes.count, by: 4).reduce(into: 0) {
    count, index in
    let differs = (0..<4).contains { channel in
      abs(Int(actual.bytes[index + channel]) - Int(expected.bytes[index + channel])) > 8
    }
    if differs { count += 1 }
  }
  let pixelCount = actual.width * actual.height
  let precision = 1 - Double(differingPixels) / Double(pixelCount)
  XCTAssertGreaterThanOrEqual(
    precision, 0.99, "Atlas snapshot precision was \(precision)", file: file, line: line)
}

private func atlasSnapshotReferenceName(
  named name: String,
  version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
) -> String {
  let platformSuffix = version.majorVersion == 15 ? ".macos-15" : ""
  return "\(name)\(platformSuffix).png"
}

private func writeSnapshotArtifactIfConfigured(_ image: NSImage, named name: String) throws {
  guard
    let artifactPath = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"],
    !artifactPath.isEmpty
  else { return }

  let directory = URL(fileURLWithPath: artifactPath, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try pngData(image).write(
    to: directory.appending(path: "\(name).actual.png"),
    options: .atomic
  )
}

private func pngData(_ image: NSImage) throws -> Data {
  let pixels = try cgImage(image)
  let bitmap = NSBitmapImageRep(cgImage: pixels)
  return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
}

private func rgbaPixels(_ image: NSImage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
  let source = try cgImage(image)
  let width = source.width
  let height = source.height
  var bytes = [UInt8](repeating: 0, count: width * height * 4)
  let rendered = bytes.withUnsafeMutableBytes { buffer in
    guard
      let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  XCTAssertTrue(rendered, "Unable to normalize Atlas snapshot pixels")
  return (width, height, bytes)
}

private func cgImage(_ image: NSImage) throws -> CGImage {
  var rect = CGRect(origin: .zero, size: image.size)
  return try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
}
