import FlukeKit
import FlukeUI
import SwiftUI

public struct SightingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: SightingsViewModel.DisplayItem
    private let openWhaleMovement: ((String) -> Void)?

    public init(
        item: SightingsViewModel.DisplayItem,
        onOpenWhaleMovement: ((String) -> Void)? = nil
    ) {
        self.item = item
        openWhaleMovement = onOpenWhaleMovement
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.locationLabel)
                        .font(.flukeDisplayMedium)
                        .foregroundStyle(Color.abyss)
                    Label(
                        item.observedAt.formatted(date: .complete, time: .shortened),
                        systemImage: "calendar"
                    )
                    .font(.flukeBody)
                    facts
                    if let notes = normalized(item.notes) {
                        detailSection("Field notes", text: notes)
                    }
                    sourceSection
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(20)
            }
            .background(Color.fog)
            .navigationTitle("Sighting")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let group = item.groupSize {
                Label("Group size: \(group)", systemImage: "water.waves")
            }
            if let ecotype = item.ecotype {
                Label(ecotypeLabel(ecotype), systemImage: "tag")
            }
            Text("Coordinates \(item.latitude.formatted(.number.precision(.fractionLength(3)))), \(item.longitude.formatted(.number.precision(.fractionLength(3))))")
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
        }
        .font(.flukeBody)
        .foregroundStyle(Color.abyss)
    }

    @ViewBuilder
    private var sourceSection: some View {
        switch item.payload {
        case .fluke(let sighting):
            VStack(alignment: .leading, spacing: 10) {
                detailSection(
                    "Source",
                    text: sighting.identifiedWhales.isEmpty
                        ? "Fluke public sighting"
                        : "Fluke public sighting. Identified whales: \(sighting.identifiedWhales.map(\.catalogId).joined(separator: ", "))."
                )
                if let openWhaleMovement {
                    ForEach(sighting.identifiedWhales, id: \.catalogId) { whale in
                        Button {
                            SightingDetailNavigation.openMovement(
                                catalogID: whale.catalogId,
                                stage: openWhaleMovement,
                                dismiss: dismiss.callAsFunction
                            )
                        } label: {
                            Label(
                                "See \(whale.catalogId) movement",
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Opens the whale's full-screen movement record")
                    }
                }
            }
        case .external(let sighting):
            VStack(alignment: .leading, spacing: 8) {
                detailSection("Source", text: sighting.attribution)
                if let sourceURL = sighting.sourceURL, let url = URL(string: sourceURL) {
                    Link("Open source", destination: url)
                        .font(.flukeBody.weight(.semibold))
                }
            }
        case .feedInternal(let sighting):
            VStack(alignment: .leading, spacing: 10) {
                detailSection(
                    "Source",
                    text: sighting.identifiedWhales.isEmpty
                        ? "Fluke public sighting"
                        : "Fluke public sighting. Identified whales: \(sighting.identifiedWhales.map(\.catalogId).joined(separator: ", "))."
                )
                if let openWhaleMovement {
                    ForEach(sighting.identifiedWhales, id: \.catalogId) { whale in
                        Button {
                            SightingDetailNavigation.openMovement(
                                catalogID: whale.catalogId,
                                stage: openWhaleMovement,
                                dismiss: dismiss.callAsFunction
                            )
                        } label: {
                            Label(
                                "See \(whale.catalogId) movement",
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case .feedExternal(let sighting):
            VStack(alignment: .leading, spacing: 8) {
                detailSection("Source", text: sighting.attribution)
                if let sourceURL = sighting.sourceUrl, let url = URL(string: sourceURL) {
                    Link("Open source", destination: url)
                        .font(.flukeBody.weight(.semibold))
                }
            }
        }
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
            Text(text)
                .font(.flukeBody)
                .foregroundStyle(Color.abyss)
                .textSelection(.enabled)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func ecotypeLabel(_ ecotype: Ecotype) -> String {
        switch ecotype {
        case .resident: "Resident ecotype"
        case .biggs: "Bigg's ecotype"
        case .offshore: "Offshore ecotype"
        case .unknown: "Unknown ecotype"
        }
    }
}

enum SightingDetailNavigation {
    @MainActor
    static func openMovement(
        catalogID: String,
        stage: (String) -> Void,
        dismiss: () -> Void
    ) {
        stage(catalogID)
        dismiss()
    }
}
