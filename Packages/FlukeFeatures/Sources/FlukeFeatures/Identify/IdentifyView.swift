import FlukeUI
import SwiftUI

public struct IdentifyView: View {
  private let capability: IdentifyCapability
  private let browseWhales: () -> Void
  private let openWhale: (String) -> Void
  private let submitSighting: () -> Void

  public init(
    capability: IdentifyCapability,
    browseWhales: @escaping () -> Void,
    openWhale: @escaping (String) -> Void,
    submitSighting: @escaping () -> Void
  ) {
    self.capability = capability
    self.browseWhales = browseWhales
    self.openWhale = openWhale
    self.submitSighting = submitSighting
  }

  public var body: some View {
    IdentifyReadyView(
      capability: capability,
      browseWhales: browseWhales,
      openWhale: openWhale,
      submitSighting: submitSighting
    )
    .navigationTitle("Identify")
    .background(Color.fog)
  }
}

private struct DorsalFramingGuide: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.deep)
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.mist, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
        .padding(16)
      VStack(spacing: 12) {
        DorsalFinShape().fill(Color.bone).frame(width: 132, height: 132)
        Text("Frame the full left or right side of the dorsal fin")
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color.bone)
          .multilineTextAlignment(.center)
      }
      .padding(28)
    }
    .frame(minHeight: 250)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Dorsal fin framing guide. Frame the full left or right side of the dorsal fin.")
  }
}

private struct IdentifyReadyView: View {
  private let browseWhales: () -> Void
  private let openWhale: (String) -> Void
  private let submitSighting: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @State private var owner: IdentifyReadyState

  private var camera: IdentifyCameraCoordinator { owner.camera }
  private var model: IdentifyViewModel { owner.model }

  init(
    capability: IdentifyCapability,
    browseWhales: @escaping () -> Void,
    openWhale: @escaping (String) -> Void,
    submitSighting: @escaping () -> Void
  ) {
    self.browseWhales = browseWhales
    self.openWhale = openWhale
    self.submitSighting = submitSighting
    _owner = State(initialValue: IdentifyReadyState(capability: capability))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        EditorialHeading(level: .hero, text: "Compare a dorsal fin")
        DorsalFramingGuide()
        if let message = model.unavailableMessage {
          FlukeEmptyState(title: "On-device identification unavailable", message: message)
        } else {
          controls
        }
        IdentifyResultContent(
          result: model.result,
          presentation: model.presentation,
          disclaimer: model.disclaimer,
          openWhale: openWhale
        )
        Button("Browse whales", action: browseWhales)
          .buttonStyle(FlukeButtonStyle.secondary)
        Button("Submit a sighting", action: submitSighting)
          .buttonStyle(FlukeButtonStyle.secondary)
      }
      .padding(20)
    }
    .sheet(
      isPresented: Binding(
        get: { camera.isPresented },
        set: { if !$0 { stopCamera(.explicitClose) } }
      )
    ) {
      if let session = camera.previewSession {
        ZStack(alignment: .topTrailing) {
          IdentifyCameraView(session: session).ignoresSafeArea()
          Button("Close", systemImage: "xmark") { stopCamera(.explicitClose) }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Close live camera")
            .padding()
        }
        .task { await camera.run() }
      }
    }
    .onChange(of: camera.isPresented) { _, presented in
      if !presented { model.cameraDidStop() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        model.cameraDidStop()
        Task { await camera.applicationDidEnterBackground() }
      } else if phase == .active {
        Task { await camera.permissionDidChange() }
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    ) { _ in
      let thermalState = ProcessInfo.processInfo.thermalState
      if thermalState == .serious || thermalState == .critical { model.cameraDidStop() }
      Task {
        await camera.thermalStateDidChange(
          isSeriousOrCritical: thermalState == .serious || thermalState == .critical)
      }
    }
    .onDisappear {
      model.cameraDidStop()
      Task { await camera.viewDidDisappear() }
    }
  }

  private var controls: some View {
    VStack(spacing: 12) {
      switch model.cameraState {
      case .available:
        Button {
          Task { await model.openCamera() }
        } label: {
          Label("Open live camera", systemImage: "camera.viewfinder")
        }
        .buttonStyle(FlukeButtonStyle.primary)
      case .unavailable(let message):
        Text(message).font(.footnote).foregroundStyle(Color.deep)
      }
      if model.isIdentifying {
        ProgressView("Comparing visual features on this device").tint(Color.tide)
      }
    }
  }

  private func stopCamera(_ reason: IdentifyCameraStopReason) {
    model.cameraDidStop()
    Task {
      switch reason {
      case .explicitClose: await camera.close()
      default: break
      }
    }
  }
}

struct IdentifyResultContent: View {
  let result: IdentifyResult?
  let presentation: IdentifyPresentation
  let disclaimer: String
  let openWhale: (String) -> Void

  @ViewBuilder
  var body: some View {
    if let result {
      IdentifyResultsView(result: result, disclaimer: disclaimer, openWhale: openWhale)
    }
    switch presentation {
    case .unknown:
      FlukeEmptyState(
        title: "No reliable match",
        message:
          "No catalog whale was a reliable visual match. Try another angle or submit the sighting."
      )
    case .poorQuality:
      FlukeEmptyState(
        title: "Frame quality too low",
        message: "Keep the dorsal fin centered, steady, and well lit, then try again."
      )
    case .unavailable:
      FlukeEmptyState(
        title: "Identification unavailable",
        message: "The verified on-device identifier stopped safely. Close the camera and try again."
      )
    default:
      EmptyView()
    }
  }
}
