import SwiftUI

enum YouInteractiveControl: String, CaseIterable {
  case retry = "you.retry"
  case signOut = "you.sign-out"
  case deleteAccount = "you.delete-account"
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
