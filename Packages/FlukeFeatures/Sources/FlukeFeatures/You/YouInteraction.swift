import FlukeUI
import SwiftUI

enum YouInteractiveControl: String, CaseIterable {
  case retry = "you.retry"
  case signOut = "you.sign-out"
  case deleteAccount = "you.delete-account"
  case reauthenticateDeletion = "you.reauthenticate-deletion"
  case about = "you.about"
  case privacy = "you.privacy"
  case support = "you.support"
  case attribution = "you.attribution"

  var minimumHitDimension: CGFloat { 44 }
}

extension View {
  func youMinimumHitTarget() -> some View {
    frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
  }

  func youMinimumHitTarget(_ control: YouInteractiveControl) -> some View {
    frame(minWidth: control.minimumHitDimension, minHeight: control.minimumHitDimension)
      .contentShape(Rectangle())
      .accessibilityIdentifier(control.rawValue)
  }
}

struct YouResourceLinks: View {
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) {
        orderedLinks
      }
      VStack(alignment: .leading, spacing: 0) {
        orderedLinks
      }
    }
    .font(.flukeBody)
  }

  @ViewBuilder
  private var orderedLinks: some View {
    resourceLink("About", path: "", control: .about)
    resourceLink("Privacy", path: "privacy", control: .privacy)
    resourceLink("Support", path: "support", control: .support)
    resourceLink("Attribution", path: "sources", control: .attribution)
  }

  @ViewBuilder
  private func resourceLink(
    _ title: String,
    path: String,
    control: YouInteractiveControl
  ) -> some View {
    if let base = URL(string: "https://fluke-pnw.vercel.app"),
      let url = path.isEmpty ? base : URL(string: path, relativeTo: base)
    {
      Link(title, destination: url)
        .youMinimumHitTarget(control)
    }
  }
}
