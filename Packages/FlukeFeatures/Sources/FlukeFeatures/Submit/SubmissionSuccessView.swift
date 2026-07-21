import FlukeUI
import SwiftUI

public struct SubmissionSuccessView: View {
  let title: String
  let message: String
  public init(title: String, message: String) { self.title = title; self.message = message }
  public var body: some View {
    ContentUnavailableView(title, systemImage: "checkmark.circle", description: Text(message))
      .foregroundStyle(Color.abyss)
  }
}
