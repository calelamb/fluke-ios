import FlukeReleaseB
import FlukeUI
import PhotosUI
import SwiftUI

public struct IdentifyView: View {
  private let online: Bool
  private let service: (any IdentifyServiceProtocol)?
  private let browseWhales: () -> Void
  private let submitSighting: () -> Void

  public init(
    online: Bool = true,
    service: any IdentifyServiceProtocol,
    browseWhales: @escaping () -> Void,
    submitSighting: @escaping () -> Void
  ) {
    self.online = online
    self.service = service
    self.browseWhales = browseWhales
    self.submitSighting = submitSighting
  }

  public init(
    browseWhales: @escaping () -> Void,
    submitSighting: @escaping () -> Void
  ) {
    online = false
    service = nil
    self.browseWhales = browseWhales
    self.submitSighting = submitSighting
  }

  public var body: some View {
    Group {
      if let service {
        IdentifyReadyView(
          online: online,
          service: service,
          browseWhales: browseWhales,
          submitSighting: submitSighting
        )
      } else {
        IdentifyTrainingView(
          browseWhales: browseWhales,
          submitSighting: submitSighting
        )
      }
    }
    .navigationTitle("Identify")
    .background(Color.fog)
  }
}

private struct IdentifyTrainingView: View {
  let browseWhales: () -> Void
  let submitSighting: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("FIELD NOTE 04")
          .font(.flukeLabel)
          .foregroundStyle(Color.tide)
        EditorialHeading(level: .hero, text: "Every fin tells a story.")
        DorsalFramingGuide()
        FlukeCard {
          VStack(alignment: .leading, spacing: 10) {
            EditorialHeading(level: .card, text: "Identification is in training")
              .accessibilityIdentifier("identify.training.title")
            Text(IdentifyViewModel.trainingMessage)
              .font(.flukeBody)
              .foregroundStyle(Color.deep)
          }
        }
        Button("Browse whales", action: browseWhales)
          .buttonStyle(FlukeButtonStyle.primary)
        Button("Submit a sighting", action: submitSighting)
          .buttonStyle(FlukeButtonStyle.secondary)
      }
      .padding(20)
    }
  }
}

private struct DorsalFramingGuide: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(Color.deep)
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.mist, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
        .padding(16)
      VStack(spacing: 12) {
        DorsalFinShape()
          .fill(Color.bone)
          .frame(width: 132, height: 132)
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
  private let submitSighting: () -> Void
  @Environment(\.scenePhase) private var scenePhase
  @State private var owner: IdentifyReadyState
  @State private var selectedPhoto: PhotosPickerItem?

  private var camera: IdentifyCameraCoordinator { owner.camera }
  private var model: IdentifyViewModel { owner.model }

  init(
    online: Bool,
    service: any IdentifyServiceProtocol,
    browseWhales: @escaping () -> Void,
    submitSighting: @escaping () -> Void
  ) {
    self.browseWhales = browseWhales
    self.submitSighting = submitSighting
    _owner = State(initialValue: IdentifyReadyState(online: online, service: service))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        EditorialHeading(level: .hero, text: "Compare a dorsal fin")
        DorsalFramingGuide()
        if let message = model.unavailableMessage {
          FlukeEmptyState(title: unavailableTitle, message: message)
        } else {
          controls
        }
        if !model.matches.isEmpty {
          IdentifyResultsView(
            matches: model.matches,
            disclaimer: model.disclaimer,
            feedbackEnabled: model.isWrongMatchFeedbackEnabled
          )
        }
        if let error = model.errorMessage {
          Text(error).font(.callout).foregroundStyle(Color.deep)
        }
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
        set: { if !$0 { Task { await camera.close() } } }
      )
    ) {
      if let session = camera.previewSession {
        ZStack(alignment: .topTrailing) {
          IdentifyCameraView(session: session)
            .ignoresSafeArea()
          Button("Close", systemImage: "xmark") {
            Task { await camera.close() }
          }
          .labelStyle(.iconOnly)
          .accessibilityLabel("Close live camera")
          .padding()
        }
        .task { await camera.run() }
      }
    }
    .onChange(of: selectedPhoto) { _, item in load(item) }
    .onChange(of: scenePhase) { _, phase in
      Task {
        if phase == .background {
          await camera.applicationDidEnterBackground()
        } else if phase == .active {
          await camera.permissionDidChange()
        }
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    ) {
      _ in
      let thermalState = ProcessInfo.processInfo.thermalState
      Task {
        await camera.thermalStateDidChange(
          isSeriousOrCritical: thermalState == .serious || thermalState == .critical)
      }
    }
    .onDisappear { Task { await camera.viewDidDisappear() } }
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
        .disabled(model.isIdentifying)
      case .unavailable(let message):
        Text(message)
          .font(.footnote)
          .foregroundStyle(Color.deep)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      PhotosPicker(selection: $selectedPhoto, matching: .images) {
        Label("Choose a photo", systemImage: "photo")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(FlukeButtonStyle.secondary)
      .disabled(model.isIdentifying)

      if model.isIdentifying {
        ProgressView("Comparing visual features")
          .tint(Color.tide)
      }
    }
  }

  private var unavailableTitle: String {
    model.availability == .needsInternet ? "Internet required" : "Identification is in training"
  }

  private func load(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          model.reportInvalidPhoto()
          return
        }
        let processed = try ImageProcessor.process(data)
        await model.identify(photo: try IdentifyPhoto(bytes: processed.bytes))
      } catch is CancellationError {
        return
      } catch {
        model.reportInvalidPhoto()
      }
    }
  }
}
