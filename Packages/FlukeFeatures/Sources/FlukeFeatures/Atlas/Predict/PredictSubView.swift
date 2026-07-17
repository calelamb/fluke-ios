import FlukeKit
import FlukeUI
import SwiftUI

public struct PredictSubView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: PredictViewModel
  private let catalog: [Whale]

  public init(repository: any PredictionRepositoryProtocol, catalog: [Whale] = []) {
    _viewModel = State(initialValue: PredictViewModel(repository: repository))
    self.catalog = catalog
  }

  public var body: some View {
    ZStack(alignment: .top) {
      BasemapView()
      if let prediction = viewModel.prediction {
        ConfidenceCone(cells: PredictPresentation.clampedCells(prediction.cells), color: .ember)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      VStack(spacing: 8) {
        stateMessage
        Spacer()
        AtlasControlShelf {
          subjectPicker
          horizonPicker
          predictionLegend
          if let prediction = viewModel.prediction {
            confidenceBlock(prediction)
          }
        }
        .padding(.bottom, 12)
      }
    }
    .task {
      if viewModel.subject == nil { viewModel.subject = .pod(.j) }
      await viewModel.loadIfNeeded()
    }
  }

  private var subjectPicker: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Menu {
          subjectButtons
        } label: {
          Label(subjectName, systemImage: "water.waves")
            .frame(minHeight: 44)
        }
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) { subjectButtons }
        }
      }
    }
    .accessibilityLabel("Prediction subject")
  }

  @ViewBuilder
  private var subjectButtons: some View {
    ForEach(Pod.allCases, id: \.self) { pod in
      subjectButton(label: pod.displayName, subject: .pod(pod))
    }
    ForEach(catalog) { whale in
      subjectButton(label: whale.catalogId, subject: .whale(id: whale.id))
    }
  }

  private func subjectButton(label: String, subject: PredictViewModel.Subject) -> some View {
    let selected = viewModel.subject == subject
    return Button(label) {
      viewModel.subject = subject
      Task { await viewModel.loadIfNeeded() }
    }
    .font(.flukeLabel)
    .foregroundStyle(selected ? Color.bone : Color.abyss)
    .padding(.horizontal, 12)
    .frame(minWidth: 44, minHeight: 44)
    .background(selected ? Color.abyss : Color.bone, in: Capsule())
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var horizonPicker: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) { horizonButtons }
      } else {
        HStack(spacing: 8) { horizonButtons }
      }
    }
    .accessibilityLabel("Prediction horizon")
  }

  private var horizonButtons: some View {
    ForEach(PredictionHorizon.allCases, id: \.self) { horizon in
      let selected = viewModel.horizon == horizon
      Button(horizon.displayName) {
        viewModel.horizon = horizon
        Task { await viewModel.loadIfNeeded() }
      }
      .font(.flukeLabel)
      .foregroundStyle(selected ? Color.bone : Color.abyss)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(selected ? Color.tide : Color.bone, in: Capsule())
      .buttonStyle(.plain)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  @ViewBuilder
  private var stateMessage: some View {
    if let notice = viewModel.state.notice {
      switch notice {
      case .offline: BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
      case .stale(let failure):
        BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
      }
    } else if let failure = viewModel.state.failure {
      BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.retry() } }
    } else if viewModel.state.isLoading {
      ProgressView("Loading prediction").padding(12).background(Color.bone, in: Capsule())
    } else if viewModel.isEmpty {
      Text("Not enough data to show a prediction for this subject and horizon.")
        .font(.flukeBody)
        .padding(12)
        .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private func confidenceBlock(_ prediction: Prediction) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(PredictPresentation.summary(prediction, subjectName: subjectName))
        .font(.flukeBody)
        .foregroundStyle(Color.abyss)
      Text(
        "Confidence: \(confidenceLabel(viewModel.normalizedConfidence)) · historical model: \(prediction.modelVersion)"
      )
      .font(.flukeLabel)
      .foregroundStyle(Color.deep)
    }
    .padding(14)
    .background(Color.bone.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("atlas.predict.summary")
  }

  private func confidenceLabel(_ value: Double) -> String {
    if value >= 0.7 { return "high" }
    if value >= 0.4 { return "medium" }
    return "low"
  }

  @ViewBuilder
  private var predictionLegend: some View {
    if case .pod(let pod) = viewModel.subject {
      AtlasPodLegend(counts: [pod: viewModel.prediction?.cells.count ?? 0])
    }
  }

  private var subjectName: String {
    switch viewModel.subject {
    case .pod(let pod): pod.displayName
    case .whale(let id): catalog.first(where: { $0.id == id })?.catalogId ?? "selected whale"
    case nil: "selected subject"
    }
  }
}
