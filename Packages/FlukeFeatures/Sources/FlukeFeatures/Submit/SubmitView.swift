import FlukeReleaseB
import FlukeUI
import SwiftUI

public struct SubmitView: View {
  @State private var model: SubmitViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsDiscard = false

  public init(model: SubmitViewModel) { _model = State(initialValue: model) }

  public var body: some View {
    NavigationStack {
      Group {
        switch model.state {
        case .success:
          SubmissionSuccessView(title: "Sighting submitted", message: "Thank you for contributing to the shared record.")
        case .queued:
          SubmissionSuccessView(title: "Saved on this device", message: "Fluke will upload this sighting when a connection is available.")
        case .partial:
          SubmissionSuccessView(title: "Sighting submitted", message: "Some photos are queued to finish uploading.")
        default: form
        }
      }
      .background(Color.fog)
      .navigationTitle("Add Sighting")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { close() } }
      }
      .interactiveDismissDisabled(model.dismissal == .requiresConfirmation)
      .confirmationDialog("Discard this sighting?", isPresented: $confirmsDiscard) {
        Button("Discard", role: .destructive) { dismiss() }
        Button("Keep editing", role: .cancel) {}
      }
    }
  }

  private var form: some View {
    Form {
      if let message = model.disabledMessage { Text(message).foregroundStyle(Color.ember) }
      LocationPickerView(latitude: $model.latitude, longitude: $model.longitude)
      TextField("Location name", text: $model.locationName)
      DatePicker("Observed", selection: $model.observedAt)
      Stepper("Group size: \(model.groupSize)", value: $model.groupSize, in: 1...100)
      if model.showsObserverEmail {
        TextField("Observer email", text: $model.email).textContentType(.emailAddress)
      }
      TextField("Notes", text: $model.notes, axis: .vertical).lineLimit(3...8)
      PhotoPicker(addPhotos: model.addPhotos, reportFailure: model.reportPhotoFailure)
      if let message = model.photoErrorMessage {
        Text(message).foregroundStyle(Color.ember)
      }
      Text("\(model.photos.count) of 5 photos")
      if case .validation = model.state { Text("Check the highlighted sighting details.").foregroundStyle(Color.ember) }
      Button(model.state == .submitting ? "Submitting…" : "Submit sighting") {
        Task { await model.submit() }
      }
      .disabled(model.state == .submitting || model.disabledMessage != nil)
    }
  }

  private func close() {
    if model.dismissal == .requiresConfirmation { confirmsDiscard = true } else { dismiss() }
  }
}
