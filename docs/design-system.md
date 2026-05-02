# Design system

Editorial PNW palette, Fraunces display typography, dorsal-fin glyph as the canonical brand mark. The visual language matches the web — see [`../../fluke/apps/web/src/styles/tokens.css`](../../fluke/apps/web/src/styles/tokens.css) for the source of truth.

## Voice

The Fluke iOS app feels like Fluke from across the room and behaves like an iOS app under the thumb. Color and type are the brand; structural patterns (sheet detents, large titles, swipe-back, haptics) are the platform. If a mobile decision pulls against the editorial palette, the dorsal-fin glyph, or the atmospheric aesthetic — the mobile decision is wrong.

## Color tokens

Defined in [`Packages/FlukeUI/Sources/FlukeUI/Tokens/Color+Fluke.swift`](../Packages/FlukeUI/Sources/FlukeUI/Tokens/Color+Fluke.swift).

| Token | Hex | Use |
| --- | --- | --- |
| `Color.bone` | `#FAFBFC` | Primary card / content background |
| `Color.fog` | `#E8EEF1` | Page background; lightest semantic surface |
| `Color.mist` | `#B3C0C8` | Subtle borders, dividers, low-contrast type |
| `Color.tide` | `#2E5972` | Brand accent — active state, links, primary affordance hover |
| `Color.deep` | `#4A6478` | Body text on light surfaces |
| `Color.abyss` | `#0A1F2E` | Display text + primary CTAs |
| `Color.ember` | `#C65A3F` | Warm accent (sparingly) — status dots, BIGGS ecotype, warning moments |

### Semantic mapping per ecotype

| Ecotype | Color |
| --- | --- |
| `RESIDENT` | `tide` |
| `BIGGS` | `ember` |
| `OFFSHORE` | `deep` |
| `UNKNOWN` | `mist` |

Tests in [`ColorTokenTests`](../Packages/FlukeUI/Tests/FlukeUITests/ColorTokenTests.swift) lock each token's RGB values against drift. Adding a new token? Add a matching test asserting the hex.

### Custom hex initializer

```swift
public extension Color {
    /// Initialize a Color from a 24-bit hex value (0xRRGGBB).
    init(hex: UInt32) { … }
}
```

Use this for one-off color values; prefer named tokens for anything that appears more than once.

## Typography

Defined in [`Packages/FlukeUI/Sources/FlukeUI/Tokens/Font+Fluke.swift`](../Packages/FlukeUI/Sources/FlukeUI/Tokens/Font+Fluke.swift).

### Display: Fraunces (variable, ~SIL OFL)

Bundled at [`Packages/FlukeUI/Sources/FlukeUI/Resources/Fonts/Fraunces-Variable.ttf`](../Packages/FlukeUI/Sources/FlukeUI/Resources/Fonts/Fraunces-Variable.ttf). Registered with the system at app launch via `FlukeUIFontRegistration.registerIfNeeded()` in `RootScene.onAppear`.

| Token | Size | Use |
| --- | --- | --- |
| `Font.flukeDisplayLarge` | 44pt | Hero / page titles |
| `Font.flukeDisplayMedium` | 28pt | Section headings inside cards / detail views |
| `Font.flukeDisplaySmall` | 20pt | Card titles, sheet titles |

### Body: SF Pro Text (system)

| Token | Style | Use |
| --- | --- | --- |
| `Font.flukeBody` | `Font.system(.body)` | Body copy. Dynamic Type works automatically. |
| `Font.flukeLabel` | `Font.system(.caption2, design: .monospaced).weight(.medium)` | Small uppercase tracking-wide labels |

### Dynamic Type

The display tokens currently use fixed sizes (`Font.custom("Fraunces", size: 44)`). M-iOS-7's accessibility pass swaps these for the relative-to-system form (`Font.custom("Fraunces", size: 44, relativeTo: .largeTitle)`) so Dynamic Type scaling works on display headings too.

## Motion tokens

Defined in [`Packages/FlukeUI/Sources/FlukeUI/Tokens/Animation+Fluke.swift`](../Packages/FlukeUI/Sources/FlukeUI/Tokens/Animation+Fluke.swift).

| Token | Curve | Use |
| --- | --- | --- |
| `Animation.flukeSpring` | `spring(response: 0.4, dampingFraction: 0.75)` | Sheets, expansions, draggable surfaces (matches web's `{ stiffness: 360, damping: 32 }`) |
| `Animation.flukeFast` | `easeOut(duration: 0.15)` | Color shifts, hover, focus rings |
| `Animation.flukeBase` | `easeOut(duration: 0.30)` | Default appear/dismiss |
| `Animation.flukeSlow` | `easeOut(duration: 0.60)` | Hero entrances, atmospheric reveals |

### Reduce Motion

`@Environment(\.accessibilityReduceMotion)` is respected throughout. When ON: springs flatten to fades, polyline-unspool animations are skipped, marker pulses stop. M-iOS-7 has the audit pass.

## DorsalFinShape

Defined in [`Packages/FlukeUI/Sources/FlukeUI/Shapes/DorsalFinShape.swift`](../Packages/FlukeUI/Sources/FlukeUI/Shapes/DorsalFinShape.swift).

The canonical Fluke brand mark — used as:

- App icon
- Sightings tab icon (template-rendered, tinted by tab tint)
- Map markers (with ecotype color)
- Empty-state glyph
- Splash screen logo

```swift
DorsalFinShape()
    .fill(Color.abyss)
    .frame(width: 56, height: 56)
```

The path is `M10 24 L10 14 Q14 8 20 24 Z` on a 28×28 viewBox — exactly mirrors the SVG used on the web in [`MobileBottomNav.tsx`](../../fluke/apps/web/src/components/layout/MobileBottomNav.tsx). Snapshot tests in [`DorsalFinShapeSnapshotTests.swift`](../Packages/FlukeUI/Tests/FlukeUITests/DorsalFinShapeSnapshotTests.swift) lock the shape against accidental edits.

## Components

Live in [`Packages/FlukeUI/Sources/FlukeUI/Components/`](../Packages/FlukeUI/Sources/FlukeUI/Components/). Shipping order:

| Component | Lands in | Purpose |
| --- | --- | --- |
| `PlaceholderScreen` | M-iOS-1 | Empty-state scaffold (used by all 5 tab placeholders) |
| `EcotypeBadge` | M-iOS-2 | Pill for `RESIDENT`/`BIGGS`/`OFFSHORE`/`UNKNOWN` with semantic color |
| `MapMarker` | M-iOS-2 | 28pt dorsal-fin glyph with ecotype color + 44pt invisible hit area |
| `SearchField` | M-iOS-2 | Magnifying-glass + clear-on-text-input |
| `FilterChip` | M-iOS-2 | Toggleable rounded pill (active = `abyss` bg + `bone` fg) |
| `PrimaryButton` | M-iOS-4 | `abyss` bg, `bone` fg, full-width default |
| `SecondaryButton` | M-iOS-4 | `bone` bg, `deep` fg, `mist` border |
| `FormField` | M-iOS-4 | Label + input + optional hint scaffold |
| `QueueBadge` | M-iOS-4 | Numbered count pill in `ember` |
| `DisclaimerRibbon` | M-iOS-6 | Pinned info-icon + caption ribbon |
| `ConfidenceBar` | M-iOS-6 | Color-graded confidence bar (`tide` / `ember` / `deep` by threshold) |
| `Haptics` | M-iOS-7 | Helper for `.impact(.soft)`, `.notification(.success)`, `.notification(.error)` |

### Component conventions

- All public APIs use named init parameters.
- `public init(...)` is required because consumers cross module boundaries.
- Snapshot tests live in `FlukeUITests/<Component>SnapshotTests.swift` for any visual component. First run records reference images to `__Snapshots__/`; subsequent runs compare.
- Components never import `FlukeKit` — they take primitive Swift types as inputs (`String`, `Color`, `Int`, closures). The feature module mediates between the domain model and the component.

### Anti-patterns to avoid

- **Don't pass domain models into components.** A `WhaleCard` takes the fields it renders (`catalogId: String`, `name: String?`, `ecotype: Ecotype`); it does NOT take `whale: Whale`. Wait, scratch that for `Ecotype` specifically — `Ecotype` is so small and so design-system-flavored that we accept it as a cross-boundary type. For everything else: primitives.
  - **Update**: in practice, `WhaleCard(whale: Whale)` IS what we ship in M-iOS-2 because the verbosity of pass-the-fields-individually outweighs the boundary purity. The compromise: cards in `FlukeFeatures` (where we DO know about Whale) accept the model; truly reusable widgets in `FlukeUI` don't. See [`architecture.md`](architecture.md) for the rule.
- **Don't bake feature-specific colors into a component.** If a button in M-iOS-4's Submit form needs a different style than the global `PrimaryButton`, make it a one-off in the feature folder, not a `PrimaryButton.SubmitVariant`.
- **Don't add a token for a one-off shade.** If you need `Color.tide.opacity(0.3)`, write that inline; don't add `Color.tideMuted` unless it's used in 3+ places.

## App icon

Living source: [`App/Fluke/Assets.xcassets/AppIcon.appiconset/`](../App/Fluke/Assets.xcassets/AppIcon.appiconset/).

M-iOS-1 ships a placeholder generated by [`scripts/generate-placeholder-icon.swift`](../scripts/generate-placeholder-icon.swift) — `abyss` dorsal fin on `fog` background. M-iOS-7 swaps in the final design (with `ember` highlight at the fin tip and a `mist`-gradient atmosphere at the bottom). The dorsal-fin path comes from the SAME `DorsalFinShape` SVG path the rest of the app uses — there is one canonical glyph.

Tinted-icon variants (iOS 18+) are out of scope for M-iOS-1; M-iOS-7 adds them.

## Light vs dark

Phone-first; iOS 26's automatic appearance support handles dark mode for system surfaces. **Tokens are currently single-value** (no light/dark variants). When the project commits to a dedicated dark-mode pass — likely Phase 2 — each token gains a `dark` companion via the asset catalog or a `Color(name:bundle:)` lookup. Until then: assume light interface.

## Web alignment

The iOS color/typography port is intentional duplication: same hex values, same names, same vibe. When the web's tokens change (rare), keep the iOS side in sync. The `ColorTokenTests` will fail loudly if a hex value drifts.

If you're touching tokens, also update:

- The web's [`tokens.css`](../../fluke/apps/web/src/styles/tokens.css)
- This doc

The point of "design system" is consistency. A token that exists only on one platform is a brand fragmentation, not a design system.
