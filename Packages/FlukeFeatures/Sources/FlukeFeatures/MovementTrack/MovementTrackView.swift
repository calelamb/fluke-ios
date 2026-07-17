import FlukeKit
import FlukeUI
import SwiftUI

public struct MovementTrackView: View {
  public static let minimumControlSize: CGFloat = 44

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dismiss) private var dismiss
  @State private var model: MovementTrackViewModel
  private let submitSighting: () -> Void

  public init(
    repository: any WhalesRepositoryProtocol,
    whale: Whale,
    onSubmitSighting: @escaping () -> Void = {}
  ) {
    _model = State(initialValue: MovementTrackViewModel(repository: repository, whale: whale))
    submitSighting = onSubmitSighting
  }

  public var body: some View {
    NavigationStack {
      ZStack {
        Color.fog.ignoresSafeArea()
        content
      }
      .navigationTitle("Movement")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
            .frame(minWidth: Self.minimumControlSize, minHeight: Self.minimumControlSize)
        }
      }
    }
    .task { await model.load() }
    .task(id: model.isPlaying) {
      while model.isPlaying, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        model.advancePlayback(by: 0.1)
      }
    }
    .onAppear { model.setReduceMotion(reduceMotion) }
    .onChange(of: reduceMotion) { _, enabled in model.setReduceMotion(enabled) }
  }

  @ViewBuilder
  private var content: some View {
    switch model.presentation {
    case .loading:
      ProgressView("Loading movement track")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      ContentUnavailableView(
        "No movement sightings",
        systemImage: "water.waves",
        description: Text("No public movement points were returned for this whale.")
      )
    case .failed(let failure):
      ContentUnavailableView {
        Label("Movement unavailable", systemImage: "water.waves")
      } description: {
        Text(failure.message)
      } actions: {
        if failure.retryable {
          Button("Retry") { Task { await model.retry() } }
        }
      }
    case .sparse:
      sparseState
    case .ready:
      movementContent
    }
  }

  private var sparseState: some View {
    ContentUnavailableView {
      Label("A pattern needs more sightings", systemImage: "point.3.connected.trianglepath.dotted")
    } description: {
      Text(model.sparseMessage)
    } actions: {
      Button("Submit a sighting") {
        dismiss()
        submitSighting()
      }
      .frame(minHeight: Self.minimumControlSize)
    }
  }

  private var movementContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let notice = model.state.notice { browseNotice(notice) }
        statsStrip
        seasonChips
        map
          .frame(minHeight: 380)
        playbackShelf
        focusCard
        Text(model.accessibilitySummary)
          .font(.flukeBody)
          .foregroundStyle(Color.deep)
          .accessibilityLabel("Movement summary")
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(16)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.whale.name ?? model.whale.catalogId)
        .font(.flukeDisplayMedium)
        .foregroundStyle(Color.abyss)
      Text("A living record across the Salish Sea")
        .font(.flukeBody)
        .foregroundStyle(Color.deep)
    }
    .accessibilityElement(children: .combine)
  }

  private var statsStrip: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) { statCards }
      VStack(spacing: 10) { statCards }
    }
  }

  @ViewBuilder
  private var statCards: some View {
    if let stats = model.stats {
      statCard("Sightings", value: String(stats.sightingCount))
      statCard(
        "North–south",
        value: Measurement(value: stats.northSouthDistanceMeters, unit: UnitLength.meters)
          .converted(to: .kilometers)
          .formatted(.measurement(width: .abbreviated, usage: .road))
      )
      statCard("First seen", value: stats.firstSeen.formatted(date: .abbreviated, time: .omitted))
      statCard("Last seen", value: stats.lastSeen.formatted(date: .abbreviated, time: .omitted))
    }
  }

  private func statCard(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label.uppercased()).font(.flukeLabel)
      Text(value).font(.flukeBody.weight(.semibold))
    }
    .foregroundStyle(Color.abyss)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .padding(.horizontal, 12)
    .background(Color.bone, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
  }

  private var seasonChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(MovementSeason.allCases) { season in
          let selected = model.selectedSeasons.contains(season)
          Button(season.rawValue) { model.toggleSeason(season) }
            .font(.flukeLabel)
            .foregroundStyle(selected ? Color.bone : Color.abyss)
            .padding(.horizontal, 12)
            .frame(minWidth: Self.minimumControlSize, minHeight: Self.minimumControlSize)
            .background(selected ? Color.tide : Color.bone, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
    }
    .accessibilityLabel("Movement seasons")
  }

  private var map: some View {
    GeometryReader { geometry in
      ZStack {
        BasemapView()
        AnimatedPolylineLayer(
          coordinates: model.visiblePolyline.map { ($0.latitude, $0.longitude) },
          color: .tide,
          drawDuration: reduceMotion ? 0 : 2.5
        )
        latestPoint(in: geometry.size)
      }
      .clipShape(RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.mist, lineWidth: 1))
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture().onEnded { value in
          let normalizedX = value.location.x / max(geometry.size.width, 1)
          let normalizedY = value.location.y / max(geometry.size.height, 1)
          let coordinate = SalishSeaProjection.salishSea.unproject(
            x: normalizedX,
            y: normalizedY
          )
          model.focus(nearestToLatitude: coordinate.lat, longitude: coordinate.lng)
        }
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Movement map")
    .accessibilityValue(model.accessibilitySummary)
    .accessibilityHint("Tap near the track to focus the closest sighting")
  }

  @ViewBuilder
  private func latestPoint(in size: CGSize) -> some View {
    if let latest = model.visiblePolyline.last {
      let position = SalishSeaProjection.salishSea.project(
        lat: latest.latitude,
        lng: latest.longitude
      )
      ZStack {
        Circle().stroke(Color.ember.opacity(0.55), lineWidth: 3).frame(width: 20, height: 20)
        Circle().fill(Color.ember).frame(width: 9, height: 9)
      }
      .position(x: position.x * size.width, y: position.y * size.height)
      .accessibilityHidden(true)
    }
  }

  private var playbackShelf: some View {
    VStack(spacing: 8) {
      HStack {
        Button {
          model.togglePlayback()
        } label: {
          Label(
            model.isPlaying ? "Pause" : "Play",
            systemImage: model.isPlaying ? "pause.fill" : "play.fill"
          )
          .frame(minWidth: Self.minimumControlSize, minHeight: Self.minimumControlSize)
        }
        .buttonStyle(.borderedProminent)
        .tint(.abyss)
        .disabled(reduceMotion)
        Spacer()
        Text(reduceMotion ? "Full track shown for Reduce Motion" : "One year every six seconds")
          .font(.flukeLabel)
          .foregroundStyle(Color.deep)
      }
      if let range = model.dateRange, range.lowerBound < range.upperBound {
        DateScrubberAtlas(
          date: Binding(
            get: { model.scrubberDate },
            set: { model.setScrubberDate($0) }
          ),
          range: range
        )
        .frame(minHeight: Self.minimumControlSize)
        .accessibilityLabel("Movement date")
        .accessibilityValue(model.scrubberDate.formatted(date: .abbreviated, time: .omitted))
      }
    }
    .padding(12)
    .background(Color.bone, in: RoundedRectangle(cornerRadius: 14))
  }

  @ViewBuilder
  private var focusCard: some View {
    if let point = model.focusedPoint {
      VStack(alignment: .leading, spacing: 5) {
        Text(point.locationName ?? "Salish Sea")
          .font(.flukeDisplaySmall)
        Text(point.observedAt.formatted(date: .complete, time: .omitted))
          .font(.flukeLabel)
        if let notes = point.behaviorNotes, !notes.isEmpty {
          Text(notes).font(.flukeBody)
        }
      }
      .foregroundStyle(Color.abyss)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(Color.bone, in: RoundedRectangle(cornerRadius: 14))
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Focused sighting")
    }
  }

  private func browseNotice(_ notice: BrowseNotice) -> some View {
    Group {
      switch notice {
      case .offline: BrowseStatusView(kind: .offline) { Task { await model.retry() } }
      case .stale(let failure):
        BrowseStatusView(kind: .stale(failure)) { Task { await model.retry() } }
      }
    }
  }
}
