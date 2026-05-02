import SwiftUI

public extension Animation {
    /// Spring used for sheets, expansions, draggable surfaces.
    /// Ported from web's `{ stiffness: 360, damping: 32, mass: 0.9 }`.
    static let flukeSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)

    /// Utility transitions — color shifts, hover, focus rings.
    /// Web token: `--duration-fast` 150ms.
    static let flukeFast = Animation.easeOut(duration: 0.15)

    /// Default transitions — appear, dismiss.
    /// Web token: `--duration-base` 300ms.
    static let flukeBase = Animation.easeOut(duration: 0.30)

    /// Slow, deliberate motion — hero entrances, atmospheric reveals.
    /// Web token: `--duration-slow` 600ms.
    static let flukeSlow = Animation.easeOut(duration: 0.60)
}
