import FlukeReleaseB
import FlukeUI
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

public struct SubmitView: View {
  @State private var model: SubmitViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsDiscard = false
  @FocusState private var focusedField: SubmissionFormField?
  @AccessibilityFocusState private var accessibilityFocusedField: SubmissionFormField?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(model: SubmitViewModel) { _model = State(initialValue: model) }

  public var body: some View {
    NavigationStack {
      Group {
        switch model.state {
        case .success:
          SubmissionSuccessView(
            title: "Sighting submitted", message: "Thank you for contributing to the shared record."
          )
        case .queued:
          SubmissionSuccessView(
            title: "Saved on this device",
            message: "Fluke will upload this sighting when a connection is available.")
        case .partial:
          SubmissionSuccessView(
            title: "Sighting submitted", message: "Some photos are queued to finish uploading.")
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
      .accessibilityAction(.escape) { close() }
      .onChange(of: model.state) { _, state in announce(state) }
    }
  }

  private var form: some View {
    ScrollViewReader { proxy in
      Form {
        if let message = model.disabledMessage { Text(message).foregroundStyle(Color.ember) }
        if let message = model.failureMessage {
          Text(message)
            .foregroundStyle(Color.ember)
            .accessibilityIdentifier("submission.failure")
        }
        LocationPickerView(latitude: $model.latitude, longitude: $model.longitude)
          .id(SubmissionFormField.location)
          .listRowBackground(validationBackground(for: .location))
          .accessibilityFocused($accessibilityFocusedField, equals: .location)
        TextField("Location name", text: $model.locationName)
          .focused($focusedField, equals: .locationName)
          .id(SubmissionFormField.locationName)
          .listRowBackground(validationBackground(for: .locationName))
          .accessibilityFocused($accessibilityFocusedField, equals: .locationName)
        DatePicker("Observed", selection: $model.observedAt)
          .id(SubmissionFormField.observedAt)
          .listRowBackground(validationBackground(for: .observedAt))
          .accessibilityFocused($accessibilityFocusedField, equals: .observedAt)
        Stepper("Group size: \(model.groupSize)", value: $model.groupSize, in: 1...100)
          .id(SubmissionFormField.groupSize)
          .listRowBackground(validationBackground(for: .groupSize))
          .accessibilityFocused($accessibilityFocusedField, equals: .groupSize)
        if model.showsObserverEmail {
          TextField("Observer email", text: $model.email)
            .textContentType(.emailAddress)
            .focused($focusedField, equals: .email)
            .id(SubmissionFormField.email)
            .listRowBackground(validationBackground(for: .email))
            .accessibilityFocused($accessibilityFocusedField, equals: .email)
        }
        TextField("Notes", text: $model.notes, axis: .vertical)
          .lineLimit(3...8)
          .focused($focusedField, equals: .notes)
          .id(SubmissionFormField.notes)
          .listRowBackground(validationBackground(for: .notes))
          .accessibilityFocused($accessibilityFocusedField, equals: .notes)
        PhotoPicker(addPhotos: model.addPhotos, reportFailure: model.reportPhotoFailure)
          .id(SubmissionFormField.photos)
          .listRowBackground(validationBackground(for: .photos))
          .accessibilityFocused($accessibilityFocusedField, equals: .photos)
        if let message = model.photoErrorMessage {
          Text(message).foregroundStyle(Color.ember)
        }
        Text("\(model.photos.count) of 5 photos")
        if case .validation = model.state {
          Text("Check the highlighted sighting detail.").foregroundStyle(Color.ember)
        }
        Button(model.state == .submitting ? "Submitting…" : "Submit sighting") {
          Task { await model.submit() }
        }
        .disabled(model.state == .submitting || model.disabledMessage != nil)
      }
      .onChange(of: model.validationField) { _, field in
        guard let field else { return }
        focusedField = field.acceptsKeyboardFocus ? field : nil
        accessibilityFocusedField = field
        if reduceMotion {
          proxy.scrollTo(field, anchor: .center)
        } else {
          withAnimation { proxy.scrollTo(field, anchor: .center) }
        }
      }
    }
  }

  private func validationBackground(for field: SubmissionFormField) -> Color {
    model.validationField == field ? Color.ember.opacity(0.16) : Color.clear
  }

  private func close() {
    if model.dismissal == .requiresConfirmation { confirmsDiscard = true } else { dismiss() }
  }

  private func announce(_ state: SubmitViewModel.State) {
    let message: String? =
      switch state {
      case .success: "Sighting submitted"
      case .queued: "Sighting saved on this device and queued for upload"
      case .partial: "Sighting submitted; some photos are queued"
      case .failed(let message): message
      default: nil
      }
    #if canImport(UIKit)
      if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    #endif
  }
}
