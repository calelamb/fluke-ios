#if os(iOS)
  import AVFoundation
  import CoreVideo
  import Foundation
  import ImageIO
  import Testing

  @testable import FlukeFeatures
  @testable import FlukeML

  @Suite("iOS identification camera adapter")
  struct IdentifyAVFoundationAdapterTests {
    @Test("input discovery requests the back wide-angle video camera")
    func backWideCameraSelection() {
      let factory = AVFoundationCameraInputFactory(
        discover: { deviceType, mediaType, position in
          #expect(deviceType == .builtInWideAngleCamera)
          #expect(mediaType == .video)
          #expect(position == .back)
          return nil
        },
        makeInput: { _ in
          Issue.record("Input creation must not run without a discovered device")
          throw AdapterTestError.unexpectedInput
        }
      )

      #expect(throws: (any Error).self) {
        try factory.makeBackWideVideoInput()
      }
    }

    @Test("output factory requests 420f and discards late frames")
    func outputPolicy() {
      let output = AVCaptureVideoDataOutput()

      IdentifyVideoOutputConfiguration.apply(to: output)

      #expect(output.alwaysDiscardsLateVideoFrames)
      let format = output.videoSettings[kCVPixelBufferPixelFormatTypeKey as String] as? UInt32
      #expect(format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    }

    @Test("injected session configures, previews, observes, starts, and releases without hardware")
    func sessionLifecycle() async throws {
      let captureSession = FakeCaptureSession()
      let notificationCenter = NotificationCenter()
      let session = AVFoundationIdentifyCameraSession(
        captureSession: captureSession,
        inputFactory: AVFoundationCameraInputFactory {
          try Self.fakeInput()
        },
        outputFactory: { AVCaptureVideoDataOutput() },
        notificationCenter: notificationCenter
      )

      try await session.start()
      let event = Task { await session.events.first { _ in true } }
      notificationCenter.post(name: .AVCaptureSessionWasInterrupted, object: captureSession)

      #expect(await event.value == .interrupted)
      #expect(session.previewSession === captureSession)
      #expect(captureSession.startCount == 1)
      #expect(captureSession.addedInputs.count == 1)
      #expect(captureSession.addedOutputs.count == 1)

      await session.stop()
      await session.stop()

      #expect(captureSession.stopCount == 1)
      #expect(captureSession.removedInputCount == 1)
      #expect(captureSession.removedOutputCount == 1)
    }

    @Test("frame processing owns YUV bytes before yielding and reports conversion errors")
    func ownedFrameAndErrorPath() async throws {
      let sample = try Self.sampleBuffer()
      let frameChannel = AsyncStream<CameraFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
      let eventChannel = AsyncStream<IdentifyCameraSessionEvent>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
      let processor = IdentifyVideoFrameProcessor(
        frameContinuation: frameChannel.continuation,
        eventContinuation: eventChannel.continuation
      )

      processor.process(sampleBuffer: sample)
      let frame = try #require(await frameChannel.stream.first { _ in true })
      let ownedBytes = frame.rgbBytes
      try Self.overwritePixelBuffer(in: sample)

      #expect(frame.rgbBytes == ownedBytes)
      #expect(frame.width == 2)
      #expect(frame.height == 2)

      let failingProcessor = IdentifyVideoFrameProcessor(
        frameContinuation: frameChannel.continuation,
        eventContinuation: eventChannel.continuation,
        convert: { _ in throw AdapterTestError.conversion }
      )
      failingProcessor.process(sampleBuffer: try Self.sampleBuffer(timestamp: 1))

      #expect(await eventChannel.stream.first { _ in true } == .failed)
    }
  }

  extension IdentifyAVFoundationAdapterTests {
    static func fakeInput() throws -> AVCaptureInput {
      let specifications = [
        [
          kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
            "mdta/app.fluke.test",
          kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
            "com.apple.metadata.datatype.UTF-8",
        ]
      ]
      var description: CMMetadataFormatDescription?
      guard
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
          allocator: kCFAllocatorDefault,
          metadataType: kCMMetadataFormatType_Boxed,
          metadataSpecifications: specifications as CFArray,
          formatDescriptionOut: &description
        ) == noErr,
        let description
      else {
        throw AdapterTestError.formatDescription
      }
      return AVCaptureMetadataInput(
        formatDescription: description,
        clock: CMClockGetHostTimeClock()
      )
    }

    static func sampleBuffer(timestamp: CMTimeValue = 0) throws -> CMSampleBuffer {
      var pixelBuffer: CVPixelBuffer?
      let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary]
      guard
        CVPixelBufferCreate(
          kCFAllocatorDefault,
          2,
          2,
          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
          attributes as CFDictionary,
          &pixelBuffer
        ) == kCVReturnSuccess,
        let pixelBuffer
      else {
        throw AdapterTestError.pixelBuffer
      }
      try fill(pixelBuffer: pixelBuffer, value: 128)
      var description: CMVideoFormatDescription?
      guard
        CMVideoFormatDescriptionCreateForImageBuffer(
          allocator: kCFAllocatorDefault,
          imageBuffer: pixelBuffer,
          formatDescriptionOut: &description
        ) == noErr,
        let description
      else {
        throw AdapterTestError.formatDescription
      }
      var timing = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: CMTime(value: timestamp, timescale: 1),
        decodeTimeStamp: .invalid
      )
      var sampleBuffer: CMSampleBuffer?
      guard
        CMSampleBufferCreateReadyWithImageBuffer(
          allocator: kCFAllocatorDefault,
          imageBuffer: pixelBuffer,
          formatDescription: description,
          sampleTiming: &timing,
          sampleBufferOut: &sampleBuffer
        ) == noErr,
        let sampleBuffer
      else {
        throw AdapterTestError.sampleBuffer
      }
      return sampleBuffer
    }

    static func overwritePixelBuffer(in sampleBuffer: CMSampleBuffer) throws {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        throw AdapterTestError.pixelBuffer
      }
      try fill(pixelBuffer: pixelBuffer, value: 32)
    }

    static func fill(pixelBuffer: CVPixelBuffer, value: UInt8) throws {
      guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
        throw AdapterTestError.pixelBuffer
      }
      defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
      for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
        guard let address = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
          throw AdapterTestError.pixelBuffer
        }
        let byteCount =
          CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
          * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        memset(address, Int32(value), byteCount)
      }
    }
  }

  private enum AdapterTestError: Error {
    case conversion
    case formatDescription
    case pixelBuffer
    case sampleBuffer
    case unexpectedInput
  }

  private final class FakeCaptureSession: AVCaptureSession {
    private var runningState = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var addedInputs: [AVCaptureInput] = []
    private(set) var addedOutputs: [AVCaptureOutput] = []
    private(set) var removedInputCount = 0
    private(set) var removedOutputCount = 0

    override var isRunning: Bool { runningState }
    override var inputs: [AVCaptureInput] { addedInputs }
    override var outputs: [AVCaptureOutput] { addedOutputs }
    override func beginConfiguration() {}
    override func commitConfiguration() {}
    override func canAddInput(_ input: AVCaptureInput) -> Bool { true }
    override func canAddOutput(_ output: AVCaptureOutput) -> Bool { true }
    override func addInput(_ input: AVCaptureInput) { addedInputs.append(input) }
    override func addOutput(_ output: AVCaptureOutput) { addedOutputs.append(output) }
    override func removeInput(_ input: AVCaptureInput) {
      removedInputCount += 1
      addedInputs.removeAll { $0 === input }
    }
    override func removeOutput(_ output: AVCaptureOutput) {
      removedOutputCount += 1
      addedOutputs.removeAll { $0 === output }
    }
    override func startRunning() {
      startCount += 1
      runningState = true
    }
    override func stopRunning() {
      stopCount += 1
      runningState = false
    }
  }
#endif
