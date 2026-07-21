// The iOS overlay does not annotate AVCaptureSession as Sendable. All capture mutation stays on
// this file's session actor; MainActor UI receives only the stable preview reference.
@preconcurrency import AVFoundation
import FlukeML
import Foundation
import ImageIO

enum IdentifyVideoOutputConfiguration {
  static let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
  static let discardsLateFrames = true

  #if os(iOS)
    static func apply(to output: AVCaptureVideoDataOutput) {
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
      ]
      output.alwaysDiscardsLateVideoFrames = discardsLateFrames
    }
  #endif
}

#if os(iOS)
  struct AVFoundationCameraInputFactory: Sendable {
    private let makeInput: @Sendable () throws -> AVCaptureInput

    init(_ makeInput: @escaping @Sendable () throws -> AVCaptureInput) {
      self.makeInput = makeInput
    }

    init(
      discover:
        @escaping @Sendable (
          AVCaptureDevice.DeviceType, AVMediaType, AVCaptureDevice.Position
        ) -> AVCaptureDevice?,
      makeInput: @escaping @Sendable (AVCaptureDevice) throws -> AVCaptureInput
    ) {
      self.makeInput = {
        guard
          let device = discover(
            .builtInWideAngleCamera,
            .video,
            .back
          )
        else {
          throw IdentifyCameraSessionError.cameraUnavailable
        }
        do {
          return try makeInput(device)
        } catch {
          throw IdentifyCameraSessionError.inputUnavailable
        }
      }
    }

    func makeBackWideVideoInput() throws -> AVCaptureInput {
      try makeInput()
    }

    static let live = AVFoundationCameraInputFactory(
      discover: { deviceType, mediaType, position in
        AVCaptureDevice.default(deviceType, for: mediaType, position: position)
      },
      makeInput: { try AVCaptureDeviceInput(device: $0) }
    )
  }
#endif

struct AVFoundationCameraAuthorization: IdentifyCameraAuthorizationProviding {
  func status() async -> IdentifyCameraPermission {
    #if os(iOS)
      guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
      return switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .notDetermined: .notDetermined
      case .authorized: .authorized
      case .denied: .denied
      case .restricted: .restricted
      @unknown default: .unavailable
      }
    #else
      return .unavailable
    #endif
  }

  func requestAccess() async -> Bool {
    #if os(iOS)
      await AVCaptureDevice.requestAccess(for: .video)
    #else
      return false
    #endif
  }
}

private enum IdentifyCameraSessionError: Error {
  case cameraUnavailable
  case inputUnavailable
  case configurationRejected
}

#if os(iOS)
  actor AVFoundationIdentifyCameraSession: IdentifyCameraSessionProviding {
    nonisolated let frames: AsyncStream<CameraFrame>
    nonisolated let events: AsyncStream<IdentifyCameraSessionEvent>
    nonisolated let previewSession: AVCaptureSession?

    private let captureSession: AVCaptureSession
    private let inputFactory: AVFoundationCameraInputFactory
    private let outputFactory: @Sendable () -> AVCaptureVideoDataOutput
    private let notificationCenter: NotificationCenter
    private let frameContinuation: AsyncStream<CameraFrame>.Continuation
    private let eventContinuation: AsyncStream<IdentifyCameraSessionEvent>.Continuation
    private let frameDelegate: IdentifyVideoFrameDelegate
    private var configured = false
    private var observerTokens: [NSObjectProtocol] = []

    init(
      captureSession: AVCaptureSession = AVCaptureSession(),
      inputFactory: AVFoundationCameraInputFactory = .live,
      outputFactory: @escaping @Sendable () -> AVCaptureVideoDataOutput = {
        AVCaptureVideoDataOutput()
      },
      notificationCenter: NotificationCenter = .default,
      frameConverter: @escaping (CVPixelBuffer) throws -> CameraFrame = {
        try CameraFrame(pixelBuffer: $0, orientation: .up)
      }
    ) {
      let frameChannel = CameraFrameChannel.make()
      let eventChannel = AsyncStream<IdentifyCameraSessionEvent>.makeStream()
      frames = frameChannel.frames
      events = eventChannel.stream
      previewSession = captureSession
      self.captureSession = captureSession
      self.inputFactory = inputFactory
      self.outputFactory = outputFactory
      self.notificationCenter = notificationCenter
      frameContinuation = frameChannel.continuation
      eventContinuation = eventChannel.continuation
      frameDelegate = IdentifyVideoFrameDelegate(
        processor: IdentifyVideoFrameProcessor(
          frameContinuation: frameChannel.continuation,
          eventContinuation: eventChannel.continuation,
          convert: frameConverter
        )
      )
    }

    deinit {
      frameContinuation.finish()
      eventContinuation.finish()
    }

    func start() throws {
      if !configured { try configure() }
      guard !captureSession.isRunning else { return }
      installObservers()
      captureSession.startRunning()
    }

    func stop() {
      if captureSession.isRunning { captureSession.stopRunning() }
      observerTokens.forEach(notificationCenter.removeObserver)
      observerTokens = []
      guard configured else { return }
      captureSession.beginConfiguration()
      captureSession.inputs.forEach(captureSession.removeInput)
      captureSession.outputs.forEach(captureSession.removeOutput)
      captureSession.commitConfiguration()
      configured = false
    }

    private func installObservers() {
      guard observerTokens.isEmpty else { return }
      observerTokens = [
        notificationCenter.addObserver(
          forName: .AVCaptureSessionWasInterrupted,
          object: captureSession,
          queue: nil
        ) { [eventContinuation] _ in eventContinuation.yield(.interrupted) },
        notificationCenter.addObserver(
          forName: .AVCaptureSessionRuntimeError,
          object: captureSession,
          queue: nil
        ) { [eventContinuation] _ in eventContinuation.yield(.failed) },
      ]
    }

    private func configure() throws {
      let input = try inputFactory.makeBackWideVideoInput()
      let output = outputFactory()
      IdentifyVideoOutputConfiguration.apply(to: output)
      output.setSampleBufferDelegate(frameDelegate, queue: frameDelegate.queue)

      captureSession.beginConfiguration()
      defer { captureSession.commitConfiguration() }
      captureSession.sessionPreset = .vga640x480
      guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
        throw IdentifyCameraSessionError.configurationRejected
      }
      captureSession.addInput(input)
      captureSession.addOutput(output)
      if let connection = output.connection(with: .video),
        connection.isVideoRotationAngleSupported(90)
      {
        connection.videoRotationAngle = 90
      }
      configured = true
    }
  }

  private final class IdentifyVideoFrameDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate
  {
    let queue = DispatchQueue(label: "app.fluke.identify.camera.frames")
    private let processor: IdentifyVideoFrameProcessor

    init(processor: IdentifyVideoFrameProcessor) {
      self.processor = processor
    }

    func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      processor.process(sampleBuffer: sampleBuffer)
    }
  }

  final class IdentifyVideoFrameProcessor {
    private let frameContinuation: AsyncStream<CameraFrame>.Continuation
    private let eventContinuation: AsyncStream<IdentifyCameraSessionEvent>.Continuation
    private let convert: (CVPixelBuffer) throws -> CameraFrame
    private var samplingGate = FrameSamplingGate()

    init(
      frameContinuation: AsyncStream<CameraFrame>.Continuation,
      eventContinuation: AsyncStream<IdentifyCameraSessionEvent>.Continuation,
      convert: @escaping (CVPixelBuffer) throws -> CameraFrame = {
        try CameraFrame(pixelBuffer: $0, orientation: .up)
      }
    ) {
      self.frameContinuation = frameContinuation
      self.eventContinuation = eventContinuation
      self.convert = convert
    }

    func process(sampleBuffer: CMSampleBuffer) {
      let timestamp = Self.nanoseconds(for: sampleBuffer)
      // This is the intentional <=2 fps sampling drop, before retaining frame storage.
      guard samplingGate.shouldAccept(timestampNanoseconds: timestamp) else { return }
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
        CVPixelBufferGetPlaneCount(pixelBuffer) == 2
      else {
        eventContinuation.yield(.failed)
        return
      }
      do {
        let frame = try convert(pixelBuffer)
        frameContinuation.yield(frame)
      } catch {
        eventContinuation.yield(.failed)
      }
    }

    private static func nanoseconds(for sampleBuffer: CMSampleBuffer) -> UInt64 {
      let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
      guard seconds.isFinite, seconds >= 0 else { return DispatchTime.now().uptimeNanoseconds }
      return UInt64(seconds * 1_000_000_000)
    }
  }
#else
  actor AVFoundationIdentifyCameraSession: IdentifyCameraSessionProviding {
    nonisolated let frames: AsyncStream<CameraFrame>
    nonisolated let events: AsyncStream<IdentifyCameraSessionEvent>
    nonisolated let previewSession: AVCaptureSession? = nil

    init() {
      frames = CameraFrameChannel.make().frames
      events = AsyncStream<IdentifyCameraSessionEvent> { $0.finish() }
    }

    func start() throws {
      throw IdentifyCameraSessionError.cameraUnavailable
    }

    func stop() {}
  }
#endif
