# Fluke Full-Spec TestFlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production-signed TestFlight build of Fluke with the original five-tab native experience, working submissions and optional Sign in with Apple, a useful Logbook, an honestly disabled identification experience, the complete illustrated Atlas, and a cohesive accessible Pacific Northwest editorial design.

**Architecture:** Keep public browsing in `FlukeKit`, presentation in `FlukeUI`, and screens in `FlukeFeatures`; activate the existing `FlukeReleaseB` target for authenticated and mutating services instead of widening the public browse client. The app target owns Apple framework adapters, session state, capability routing, and dependency injection. The deployed API remains the source of truth; capabilities must report `accounts: true`, `submissions: true`, and `identification: false` for this build, and the app must fail closed if that contract is malformed or unavailable.

**Tech Stack:** Swift 5.10, SwiftUI, Observation, Swift Testing, XCTest/XCUITest, AuthenticationServices, PhotosUI, AVFoundation, Security/Keychain Services, SwiftData, URLSession, GitHub Actions, Xcode 26.0.1, App Store Connect.

## Global Constraints

- Target iOS 17.0+, iPhone-first; keep the existing `app.fluke.Fluke` bundle identifier and Apple team `86RBV2JZ8F`.
- Ship exactly five tabs in this order: Sightings, Whales, Identify, Learn, You. Atlas is opened from Sightings and whale profiles, not a sixth tab.
- Accounts are optional. Anonymous browsing and anonymous sighting submission remain complete flows.
- Identification is server-side only. With `identification == false`, do not request camera or photo-library permission, do not upload a photo, and never display fabricated matches.
- The identification unavailable copy is: “Photo identification is still in training. We are building a rights-cleared reference catalog before we compare your photo. Browse the whale catalog or submit a sighting in the meantime.”
- Use the deployed HTTPS API at `https://fluke-api.onrender.com`; never weaken App Transport Security.
- Validate every external response, user-entered string, selected image, URL, date, latitude, longitude, group size, and multipart payload at its boundary.
- Store session hints in Keychain, never `UserDefaults`; let the API's HttpOnly cookie remain the authentication credential.
- Store queued photo bytes under `Application Support/queued-photos`, excluded from backup, with immutable value records referenced by SwiftData storage rows.
- Keep user-visible error text safe and actionable; never surface response bodies, tokens, Apple subjects, file paths, or server internals.
- Maintain 80%+ line coverage for `FlukeKit`, all testable `FlukeFeatures` view-model logic, and the app target.
- Every interactive control has a 44×44-point minimum target, a visible text or VoiceOver label, and a logical focus order.
- Fraunces display text scales relative to Dynamic Type; body copy uses system text styles. Accessibility sizes replace horizontal segmented controls with menus or vertical layouts.
- Reduce Motion disables pulsing, flowing dashes, autoplay, and path-unspool animation; information remains equivalent.
- Keep functions under 50 lines and files under 800 lines. Prefer immutable structs and actor-isolated stores; do not introduce shared mutable singletons.
- Match the web source-of-truth palette exactly: fog `#E8EEF1`, bone `#F4F0E8`, abyss `#0A1F2E`, tide `#2C6E8F`, deep `#143B52`, mist `#A8C5D1`, ember `#D97742`, plus Atlas `swell` `#3B5F75`.
- App Store privacy data must declare email, optional display name, photos, and coarse submitted location as linked data used for app functionality, with no tracking.
- Do not upload until all package tests, app tests, UI tests, coverage gates, screenshot validation, archive validation, API smoke checks, and manual accessibility checks pass.

## External API and App Store Prerequisites

These are hard interfaces for the iOS work, not authorization to implement backend changes in this repository. The standalone API plan owns their implementation and deployment.

- `GET /api/v1/capabilities` must return exactly `{"accounts":true,"identification":false,"submissions":true}` for the upload candidate.
- `POST /api/v1/auth/apple`, `GET /api/v1/auth/me`, and `POST /api/v1/auth/logout` must support the observer-cookie contract in the original spec.
- `DELETE /api/v1/auth/account` must authenticate the observer, delete or irreversibly anonymize account-linked personal data, clear the observer cookie, and return `204`. Apple requires deletion to be initiated inside an app that creates accounts; the You tab must expose this action before upload.
- `GET /api/v1/sightings/me`, `POST /api/v1/sightings`, and `POST /api/v1/sightings/:id/photos` must support Logbook, anonymous/account-linked submission, and photo-upload-token replay.
- Submitted photos and identification uploads must use durable object storage with stable HTTPS URLs. Render's ephemeral filesystem is not an acceptable production store; a restart/deploy smoke test must prove an uploaded test photo remains retrievable.
- `GET /api/v1/whales/:id/track`, `GET /api/v1/sightings/historical`, and `GET /api/v1/predict` must continue matching the packaged fixtures.
- `POST /api/v1/identify` remains deployed but capability-disabled until the rights-cleared reference catalog and model attestations are complete.
- App Store Connect must have the `app.fluke.Fluke` record, Sign in with Apple capability, privacy answers, agreements, tax/banking state appropriate for a free app, and an internal tester group ready.

## Delivery Order and Parallel Boundaries

Task 1 establishes shared contracts and must land first. After Task 1, Tasks 2 (account loop), 3 (submission loop), and 4 (Identify) can execute in separate worktrees. Task 5 integrates movement and Atlas. Tasks 6–8 are the sequential release gate. Do not let parallel agents edit `RootScene.swift`, `AppEnvironment.swift`, `project.pbxproj`, App Store metadata, or release scripts simultaneously; those are integration-owner files.

---

### Task 1: Activate Full-Launch Capabilities and Five-Tab Product Shell

**Files:**
- Modify: `Packages/FlukeKit/Package.swift`
- Modify: `Packages/FlukeFeatures/Package.swift`
- Modify: `App/Fluke/AppEnvironment.swift`
- Modify: `App/Fluke/RootScene.swift`
- Modify: `App/FlukeTests/ReleaseAShellTests.swift`
- Modify: `scripts/verify-release-a-boundaries.sh`
- Modify: `.github/workflows/ci.yml`
- Create: `App/FlukeTests/LaunchCapabilityTests.swift`

**Interfaces:**
- Produces: `LaunchCapabilities { accounts, identification, submissions }`, `LaunchCapabilityState`, and `RootTab.sightings/.whales/.identify/.learn/.you`.
- Produces: environment closures `openSubmit`, `openAtlas`, and a single `AuthSession` injected at the root in later tasks.

- [ ] **Step 1: Write the failing shell and capability tests**

```swift
@Test("The launch app exposes the five approved destinations")
func launchTabs() {
  #expect(RootTab.allCases.map(\.title) == ["Sightings", "Whales", "Identify", "Learn", "You"])
}

@Test("Accounts and submissions enable independently while identify stays honest")
func releaseCapabilities() async throws {
  let decoded = try JSONDecoder().decode(
    Capabilities.self,
    from: Data(#"{"accounts":true,"identification":false,"submissions":true}"#.utf8)
  )
  let state = await LaunchCapabilityState.load { decoded }
  #expect(state == .available(.init(accounts: true, identification: false, submissions: true)))
}

@Test("Malformed or unavailable capability state fails closed")
func unavailableCapabilities() async {
  let state = await LaunchCapabilityState.load { throw URLError(.cannotConnectToHost) }
  #expect(state == .unavailable)
}
```

- [ ] **Step 2: Run the focused app tests and confirm RED**

Run:

```bash
xcodebuild test -workspace Fluke.xcworkspace -scheme Fluke -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' -only-testing:FlukeTests/ReleaseAShellTests -only-testing:FlukeTests/LaunchCapabilityTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the launch capability types and Identify/You tabs do not exist.

- [ ] **Step 3: Implement the immutable capability state and five-tab enum**

```swift
struct LaunchCapabilities: Equatable, Sendable {
  let accounts: Bool
  let identification: Bool
  let submissions: Bool
}

enum LaunchCapabilityState: Equatable, Sendable {
  case loading
  case available(LaunchCapabilities)
  case unavailable

  static func load(using fetch: () async throws -> Capabilities) async -> Self {
    guard let value = try? await fetch() else { return .unavailable }
    return .available(.init(
      accounts: value.accounts,
      identification: value.identification,
      submissions: value.submissions
    ))
  }
}

enum RootTab: CaseIterable, Hashable {
  case sightings, whales, identify, learn, you
}
```

Wire temporary compile-safe `IdentifyView` and `YouView` launch surfaces, move Atlas out of the tab bar, rename the boundary verification and CI job to “Full launch iOS verification,” and make `FlukeReleaseB` depend on `FlukeKit` while `FlukeFeatures` depends on both products.

- [ ] **Step 4: Re-run tests and commit GREEN**

Run the command from Step 2. Expected: PASS with five tab titles in exact order and capability failures closed.

```bash
git add Packages/FlukeKit/Package.swift Packages/FlukeFeatures/Package.swift App/Fluke/AppEnvironment.swift App/Fluke/RootScene.swift App/FlukeTests scripts/verify-release-a-boundaries.sh .github/workflows/ci.yml
git commit -m "feat: activate full launch app shell"
```

#### Task 1B: Complete the PNW Editorial Design System

**Files:**
- Modify: `Packages/FlukeUI/Sources/FlukeUI/Tokens/Color+Fluke.swift`
- Modify: `Packages/FlukeUI/Sources/FlukeUI/Tokens/Font+Fluke.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Components/EditorialHeading.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Components/FlukeButton.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Components/EcotypeBadge.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Components/FlukeCard.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Components/FlukeEmptyState.swift`
- Create: `Packages/FlukeUI/Sources/FlukeUI/Modifiers/FlukeMotion.swift`
- Create: `Packages/FlukeUI/Tests/FlukeUITests/LaunchComponentSnapshotTests.swift`
- Modify: `Packages/FlukeUI/Tests/FlukeUITests/FontTokenTests.swift`
- Modify: `Packages/FlukeUI/Tests/FlukeUITests/ColorTokenTests.swift`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: `Color.swell`, `EditorialHeading(level:text:)`, `FlukeButtonStyle.primary/secondary`, `EcotypeBadge(label:color:)`, `FlukeCard`, `FlukeEmptyState`, and `View.flukeMotion(_:reduceMotion:)`.

- [ ] **Step 1: Add failing token and Dynamic Type tests**

```swift
@Test("Atlas swell remains the approved PNW midtone")
func swellToken() { #expect(Color.swell.flukeHex == 0x3B5F75) }

@Test("Every Fraunces token scales relative to a text style")
func displayFontsScale() {
  #expect(FlukeFontDescriptor.displayLarge.relativeStyle == .largeTitle)
  #expect(FlukeFontDescriptor.displayMedium.relativeStyle == .title)
  #expect(FlukeFontDescriptor.displaySmall.relativeStyle == .title3)
}
```

Record snapshots at standard text, accessibility XXXL, increased contrast, and Reduce Motion for primary/disabled buttons, every badge color, a card, and the empty state.

- [ ] **Step 2: Run FlukeUI tests and confirm RED**

Run: `swift test --package-path Packages/FlukeUI --filter 'ColorTokenTests|FontTokenTests|LaunchComponentSnapshotTests'`

Expected: FAIL for missing swell, relative descriptors, and launch components.

- [ ] **Step 3: Implement reusable brand components**

```swift
public enum EditorialHeadingLevel: Sendable { case hero, section, card }

public struct EditorialHeading: View {
  public let level: EditorialHeadingLevel
  public let text: String
  public var body: some View {
    Text(text)
      .font(level.font)
      .foregroundStyle(Color.abyss)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

public enum FlukeButtonKind: Sendable { case primary, secondary }
```

Use quiet fog fields, bone cards, abyss text, tide actions, ember only for warnings/Bigg's, 16-point card radii, 1-pixel mist borders, and no decorative emoji. All button labels remain visible at accessibility sizes.

- [ ] **Step 4: Verify snapshots and commit**

Run: `swift test --package-path Packages/FlukeUI`

Expected: PASS with no unexpected snapshot artifacts.

```bash
git add Packages/FlukeUI docs/design-system.md
git commit -m "feat: complete PNW editorial design system"
```

#### Task 1C: Add a Validated Mutation Transport

**Files:**
- Modify: `Packages/FlukeKit/Sources/FlukeKit/API/APIClient.swift`
- Create: `Packages/FlukeKit/Sources/FlukeKit/API/MultipartForm.swift`
- Create: `Packages/FlukeKit/Sources/FlukeKit/API/MutationRequest.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/MutationAPIClientTests.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/MultipartFormTests.swift`

**Interfaces:**
- Produces: `APIClient.post(_:body:)`, `APIClient.postMultipart(_:parts:headers:)`, `MultipartPart.data(name:fileName:mimeType:bytes:)`, and bounded 10 MiB request bodies.

- [ ] **Step 1: Write transport tests for JSON, multipart, cookies, cancellation, and safe failures**

```swift
@Test("Multipart builder rejects header injection and oversized photos")
func multipartValidation() throws {
  #expect(throws: APIError.invalidRequest) {
    try MultipartPart.data(name: "photo\r\nX-Evil: yes", fileName: "fin.jpg", mimeType: "image/jpeg", bytes: Data())
  }
  #expect(throws: APIError.invalidRequest) {
    try MultipartForm(parts: [.data(name: "photo", fileName: "fin.jpg", mimeType: "image/jpeg", bytes: Data(repeating: 0, count: 10_000_001))])
  }
}
```

Assert JSON uses `Content-Type: application/json`, multipart uses a generated boundary, cookies are applied, 4xx is never retried, one retry occurs for transient transport failure before any response, and cancellation stays `CancellationError`.

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeKit --filter 'MutationAPIClientTests|MultipartFormTests'`

Expected: FAIL because mutation and multipart APIs are absent.

- [ ] **Step 3: Implement the bounded request types and public mutation methods**

```swift
public struct MultipartPart: Sendable {
  public let name: String
  public let fileName: String
  public let mimeType: String
  public let bytes: Data
}

public extension APIClient {
  func post<Request: Encodable & Sendable, Response: Decodable>(
    _ request: APIRequest,
    body: Request
  ) async throws -> Response

  func postMultipart<Response: Decodable>(
    _ request: APIRequest,
    parts: [MultipartPart],
    headers: [String: String] = [:]
  ) async throws -> Response
}
```

Refactor the existing private send method to accept an immutable request body/content type/headers value without exposing raw response bytes.

- [ ] **Step 4: Verify package coverage and commit**

Run:

```bash
swift test --package-path Packages/FlukeKit --enable-code-coverage
coverage_path="$(swift test --package-path Packages/FlukeKit --show-codecov-path | tail -1)"
scripts/verify-swift-package-coverage.sh "$coverage_path" /Sources/FlukeKit/ 80
```

Expected: PASS and coverage at least 80%.

```bash
git add Packages/FlukeKit
git commit -m "feat: add validated mutation transport"
```

### Task 2: Implement Optional Sign in with Apple, You, Logbook, and Account Control

**Files:**
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/AuthModels.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/AuthService.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/SessionHintStore.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Auth/KeychainSessionHintStore.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/AuthServiceTests.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/KeychainSessionHintStoreTests.swift`
- Create: `App/Fluke/Auth/AppleAuthorizationAdapter.swift`
- Create: `App/Fluke/Auth/AuthSession.swift`
- Create: `App/FlukeTests/AuthSessionTests.swift`
- Create: `App/Fluke/Fluke.entitlements`
- Modify: `App/Fluke.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `APIClient.post` and `ReleaseBEndpoint.authApple/authMe/authLogout`.
- Produces: `AuthenticatedUser`, `AppleCredential`, `AuthServiceProtocol`, `SessionHintStore`, and `@MainActor @Observable AuthSession` with `restore()`, `signIn(credential:)`, and `signOut()`.

- [ ] **Step 1: Write failing auth contract and state-machine tests**

```swift
@Test("A valid Apple credential becomes an authenticated observer")
func signIn() async throws {
  let credential = AppleCredential(identityToken: Data("signed.jwt".utf8), fullName: "Cale Lamb")
  let session = AuthSession(service: AuthServiceSpy(result: .success(.fixture)), hints: MemorySessionHintStore())
  await session.signIn(credential: credential)
  #expect(session.state == .signedIn(.fixture))
}

@Test("Missing token fails without changing authenticated state")
func missingToken() async {
  let session = AuthSession(service: AuthServiceSpy(), hints: MemorySessionHintStore())
  await session.signIn(credential: .init(identityToken: Data(), fullName: nil))
  #expect(session.state == .signedOut(error: .invalidAppleCredential))
}
```

Also test: `/auth/me` 401 becomes signed out, network failure preserves a known signed-in user while displaying a retryable notice, logout clears cookies but retains only the non-secret reauthentication hint, and Keychain reads reject malformed/blank data.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --package-path Packages/FlukeKit --filter 'AuthServiceTests|KeychainSessionHintStoreTests'`

Then run the app-target test command from Task 1 with `-only-testing:FlukeTests/AuthSessionTests`.

Expected: FAIL for missing auth types.

- [ ] **Step 3: Implement Apple adapter, service, state, Keychain, and entitlement**

```swift
public struct AuthenticatedUser: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let email: String
  public let displayName: String?
  public let role: String
}

@MainActor @Observable final class AuthSession {
  enum State: Equatable { case restoring, signedOut(error: AuthPresentationError?), signingIn, signedIn(AuthenticatedUser) }
  private(set) var state: State = .restoring
}
```

Use `ASAuthorizationAppleIDProvider`, require a non-empty UTF-8 identity token, request `.fullName` and `.email`, and add only `com.apple.developer.applesignin = [Default]` to the entitlements. Never log credential values.

- [ ] **Step 4: Verify auth tests and commit**

Run both commands from Step 2. Expected: PASS.

```bash
git add Packages/FlukeKit App/Fluke/Auth App/FlukeTests/AuthSessionTests.swift App/Fluke/Fluke.entitlements App/Fluke.xcodeproj/project.pbxproj
git commit -m "feat: add optional Apple sign in"
```

#### Task 2B: Build You, Logbook, Account Recovery, and Account Deletion UI

**Files:**
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Logbook/LogbookModels.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Logbook/LogbookRepository.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/LogbookRepositoryTests.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/YouView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/LogbookView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/LogbookViewModel.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/LogbookViewModelTests.swift`
- Modify: `App/Fluke/RootScene.swift`
- Modify: `App/Fluke/AppEnvironment.swift`

**Interfaces:**
- Consumes: `AuthSession`, `GET /api/v1/sightings/me`, and later `SubmissionQueueProtocol`.
- Produces: signed-out You screen, signed-in Logbook, queued/pending/approved/rejected badges, retry, sign-out, and authenticated account deletion.

- [ ] **Step 1: Write failing repository and view-model tests**

```swift
@Test("Logbook keeps queued entries first and server entries newest first")
func ordering() async {
  let model = LogbookViewModel(repository: FixtureLogbookRepository(), queue: FixtureSubmissionQueue())
  await model.load()
  #expect(model.rows.map(\.status) == [.queued, .pending, .approved, .rejected])
}

@Test("Unauthorized logbook response asks the session to sign out")
func unauthorized() async {
  let model = LogbookViewModel(repository: UnauthorizedLogbookRepository(), queue: FixtureSubmissionQueue())
  await model.load()
  #expect(model.sessionAction == .expire)
}
```

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeFeatures --filter LogbookViewModelTests`

Expected: FAIL because Logbook types are absent.

- [ ] **Step 3: Implement the complete You branches**

Signed-out UI: dorsal-fin mark, “Keep your sightings together,” one system `SignInWithAppleButton`, explicit “Browsing and submitting do not require an account,” About, privacy, support, and attribution links. Signed-in UI: personal greeting, Logbook list, status explanations, retryable error card, sign out, and “Delete account.” Deletion requires a destructive confirmation that says linked personal details are removed while approved public wildlife observations may remain anonymized; call `DELETE /api/v1/auth/account`, clear local cookies/Keychain hints/queued account association only after `204`, and preserve the signed-in state with a retryable error if the request fails. If accounts are disabled, preserve About/support and explain that accounts are temporarily unavailable.

- [ ] **Step 4: Verify and commit**

Run package tests plus app tests. Expected: PASS.

```bash
git add Packages/FlukeKit Packages/FlukeFeatures App/Fluke/RootScene.swift App/Fluke/AppEnvironment.swift
git commit -m "feat: add You tab and observer logbook"
```

### Task 3: Implement Submission, Durable Offline Replay, and Submit UI

**Files:**
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/SubmissionModels.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/SubmissionValidator.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/SubmissionService.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/ImageProcessor.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/SubmissionValidatorTests.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/SubmissionServiceTests.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/ImageProcessorTests.swift`

**Interfaces:**
- Produces: immutable `SubmissionDraft`, `SubmissionPayload`, `ProcessedPhoto`, `SubmissionReceipt`, `SubmissionValidator.validate(_:)`, `ImageProcessor.process(_:)`, and `SubmissionService.submit(payload:photos:)`.

- [ ] **Step 1: Write boundary tests**

```swift
@Test("Submission rejects impossible coordinates and future observation dates")
func invalidGeographyAndDate() {
  #expect(throws: SubmissionValidationError.latitude) {
    try SubmissionValidator.validate(.fixture(latitude: 91, observedAt: .now))
  }
  #expect(throws: SubmissionValidationError.observedAt) {
    try SubmissionValidator.validate(.fixture(observedAt: .now.addingTimeInterval(301)))
  }
}

@Test("Anonymous submission requires a valid bounded email")
func anonymousEmail() {
  #expect(throws: SubmissionValidationError.email) {
    try SubmissionValidator.validate(.fixture(observerEmail: "not-an-email"))
  }
}
```

Cover group size 1...200, notes 2,000 characters, location 200, 1...5 JPEG/HEIC inputs, decompression limits, EXIF orientation, 2,048-pixel longest edge, JPEG output, metadata stripping, and 10 MiB/photo.

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeKit --filter 'SubmissionValidatorTests|SubmissionServiceTests|ImageProcessorTests'`

Expected: FAIL for missing submission types.

- [ ] **Step 3: Implement the two-stage API operation**

```swift
public struct SubmissionReceipt: Codable, Hashable, Sendable {
  public let id: String
  public let photoUploadToken: String
}

public protocol SubmissionServiceProtocol: Sendable {
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt
}
```

POST JSON to `/api/v1/sightings`, then upload each photo to `/api/v1/sightings/{id}/photos` with `x-photo-upload-token`. Treat a created sighting plus partial photo failure as a partial success containing failed photo indices; never create a duplicate sighting while retrying photos.

- [ ] **Step 4: Verify and commit**

Run all FlukeKit tests with coverage. Expected: PASS at 80%+.

```bash
git add Packages/FlukeKit
git commit -m "feat: add validated sighting submission service"
```

#### Task 3B: Add the Durable Offline Submission Queue

**Files:**
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/QueuedSubmission.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/SubmissionQueue.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/QueuedPhotoStore.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Submit/SubmissionReplayActor.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/SubmissionQueueTests.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/SubmissionReplayActorTests.swift`

**Interfaces:**
- Consumes: `SubmissionServiceProtocol`.
- Produces: `SubmissionQueueProtocol.list/enqueue/retry/discard`, `QueuedSubmissionValue`, and `SubmissionReplayActor.flush()`.

- [ ] **Step 1: Write queue lifecycle tests**

Test enqueue is atomic across row and photos; failed photo write leaves no row; replay success removes row and photo files; partial photo upload retains only unuploaded photos with the created sighting ID/token; transient failures increment attempts; three failures become `.failed`; discard removes all bytes; cancellation leaves state retryable; concurrent flush calls serialize.

```swift
@Test("A successful flush removes the queue row and photo files")
func flushSuccess() async throws {
  let queue = try TestSubmissionQueue.make(entries: [.fixture])
  let replay = SubmissionReplayActor(queue: queue, service: SuccessfulSubmissionService())
  await replay.flush()
  #expect(try await queue.list().isEmpty)
  #expect(try queue.photoFiles().isEmpty)
}
```

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeKit --filter 'SubmissionQueueTests|SubmissionReplayActorTests'`

Expected: FAIL for missing queue types.

- [ ] **Step 3: Implement actor-isolated persistence**

Use a private SwiftData `@Model` storage row and convert it immediately to/from immutable `QueuedSubmissionValue`. Put photo files in Application Support, set `URLResourceKey.isExcludedFromBackupKey`, write through a temporary file plus atomic rename, and use a background `URLSessionConfiguration.background(withIdentifier: "app.fluke.Fluke.submissions")` for replay. Invoke flush at launch, foreground, and NWPath transition to satisfied.

- [ ] **Step 4: Verify and commit**

Run all FlukeKit tests and coverage. Expected: PASS.

```bash
git add Packages/FlukeKit
git commit -m "feat: add durable offline submission queue"
```

#### Task 3C: Build the Submit Sheet and Photo Flow

**Files:**
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Submit/SubmitView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Submit/SubmitViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Submit/LocationPickerView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Submit/PhotoPicker.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Submit/SubmissionSuccessView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/SubmitViewModelTests.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsView.swift`
- Modify: `App/Fluke/AppEnvironment.swift`
- Modify: `App/Fluke/RootScene.swift`
- Modify: `App/Fluke/Info.plist`

**Interfaces:**
- Consumes: `SubmissionServiceProtocol`, `SubmissionQueueProtocol`, auth state, and `LaunchCapabilities.submissions`.
- Produces: top-right Add Sighting action, large-detent dirty-guarded sheet, anonymous/signed-in form, photo selection/camera, queued/success/partial-failure states.

- [ ] **Step 1: Write the submit state-machine tests**

```swift
@Test("Offline submit queues once and presents an honest receipt")
func queuesOffline() async {
  let model = SubmitViewModel(service: OfflineSubmissionService(), queue: RecordingQueue())
  await model.submit(.validFixture)
  #expect(model.state == .queued)
  #expect(model.queueCount == 1)
}

@Test("A dirty form requires explicit discard")
func dirtyDismissal() {
  let model = SubmitViewModel(service: RecordingSubmissionService(), queue: RecordingQueue())
  model.updateLocationName("Lime Kiln")
  #expect(model.dismissal == .requiresConfirmation)
}
```

Test duplicate-tap suppression, signed-in email omission, anonymous email requirement, permission denial, five-photo cap, validation focus, online success, partial photo failure, retry, and capability-disabled copy.

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeFeatures --filter SubmitViewModelTests`

Expected: FAIL for missing submit types.

- [ ] **Step 3: Implement the complete modal flow**

Use the system `PhotosPicker` for library access so the app reads only the user's explicit selections without requesting broad photo-library permission. Add a minimal `UIImagePickerController` camera adapter only after the user taps “Take photo,” with `NSCameraUsageDescription = "Fluke uses the camera only when you choose to attach an orca photo to a sighting."` The map coordinate picker starts centered on the Salish Sea and never requests device location.

- [ ] **Step 4: Verify and commit**

Run feature and app tests. Expected: PASS.

```bash
git add Packages/FlukeFeatures App/Fluke/AppEnvironment.swift App/Fluke/RootScene.swift App/Fluke/Info.plist
git commit -m "feat: build sighting submission flow"
```

### Task 4: Build the Honest Identification Destination

**Files:**
- Modify: `Packages/FlukeKit/Sources/FlukeReleaseB/IdentifyResponse.swift`
- Create: `Packages/FlukeKit/Sources/FlukeReleaseB/Identify/IdentifyService.swift`
- Create: `Packages/FlukeKit/Tests/FlukeKitTests/IdentifyServiceTests.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Identify/IdentifyView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Identify/IdentifyViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Identify/IdentifyCameraView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Identify/IdentifyResultsView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/IdentifyViewModelTests.swift`
- Modify: `App/Fluke/RootScene.swift`

**Interfaces:**
- Produces: `IdentifyAvailability.disabled/training/needsInternet/ready`, `IdentifyService.identify(photo:)`, and a results carousel ready for a future capability flip.

- [ ] **Step 1: Write honest-state tests**

```swift
@Test("Disabled identification never requests media or uploads")
func disabledDoesNoWork() async {
  let media = RecordingMediaAuthorization()
  let service = RecordingIdentifyService()
  let model = IdentifyViewModel(capability: false, media: media, service: service)
  await model.openCamera()
  #expect(media.requestCount == 0)
  #expect(service.requestCount == 0)
  #expect(model.state == .training)
}
```

Also test offline ready-state copy, 501 mapping to training, upload cancellation, non-image rejection, top-three ordering, scores outside 0...1 rejected, disclaimer always visible, and “wrong match” disabled until the feedback endpoint is contractually available.

- [ ] **Step 2: Run tests and confirm RED**

Run both FlukeKit Identify tests and `swift test --package-path Packages/FlukeFeatures --filter IdentifyViewModelTests`.

Expected: FAIL for missing service/view model.

- [ ] **Step 3: Implement capability-gated UI and dormant ready path**

The shipping state shows the exact Global Constraints copy, an illustrated dorsal-fin framing guide, “Browse whales,” and “Submit a sighting.” Keep camera controls in source and fully tested, but instantiate them only when capability is true. Results show top three cards and pin “Visual similarity, not a confirmed ID” beneath them.

- [ ] **Step 4: Verify and commit**

Run package tests. Expected: PASS and no camera/photo authorization in the disabled UI test.

```bash
git add Packages/FlukeKit Packages/FlukeFeatures App/Fluke/RootScene.swift
git commit -m "feat: add honest identification experience"
```

### Task 5: Restore Movement Tracks and Polish Atlas

**Files:**
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/MovementTrack/MovementTrackView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/MovementTrack/MovementTrackViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/MovementTrack/MovementTrackStats.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/MovementTrackViewModelTests.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhaleProfileView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingDetailView.swift`

**Interfaces:**
- Consumes: `WhalesRepositoryProtocol.loadTrack`, `AnimatedPolylineLayer`, `DateScrubberAtlas`, and `Submission` route action.
- Produces: season filtering, scrubber reveal, playback, stats, focus card, sighting detail, sparse-state submission action, and Reduce Motion behavior.

- [ ] **Step 1: Write calculation and state tests**

```swift
@Test("A track needs three points before drawing a pattern")
func sparseTrack() async {
  let model = MovementTrackViewModel(repository: TrackRepository(points: [.a, .b]), whale: .fixture)
  await model.load()
  #expect(model.presentation == .sparse)
  #expect(model.visiblePolyline.isEmpty)
}

@Test("Season and scrubber filters compose")
func combinedFilters() async {
  let model = MovementTrackViewModel(repository: TrackRepository(points: .yearFixture), whale: .fixture)
  await model.load()
  model.setSeasons([.summer, .fall])
  model.setScrubberDate(.octoberFirst)
  #expect(model.visiblePoints.allSatisfy { [.summer, .fall].contains($0.season) && $0.observedAt <= .octoberFirst })
}
```

Test northernmost-to-southernmost haversine range, first/last seen, nearest focus point, six-seconds-per-year playback, pause at end, and Reduce Motion immediate reveal.

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift test --package-path Packages/FlukeFeatures --filter MovementTrackViewModelTests`

Expected: FAIL for missing movement types.

- [ ] **Step 3: Implement the destination and presentation**

Present from “See movement” as a `fullScreenCover`, with close button, stats strip, season chips, hand-illustrated basemap, unspooling path, ember latest-point ring, focus card, play/pause, and scrubber. With fewer than three points, render “Not enough sightings yet to trace a movement pattern.” and route the action to Submit.

- [ ] **Step 4: Verify and commit**

Run all feature tests. Expected: PASS.

```bash
git add Packages/FlukeFeatures
git commit -m "feat: add full-screen whale movement tracks"
```

#### Task 5B: Correct and Polish Atlas as the Signature Experience

**Files:**
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/AtlasView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/AtlasViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/BasemapView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Timeline/TimelineSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Timeline/TimelineViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Range/RangeSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Range/RangeViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Trace/TraceSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Predict/PredictSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Predict/PredictViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Common/AnimatedPolylineLayer.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/AtlasProductTests.swift`
- Create: `Packages/FlukeUI/Tests/FlukeUITests/AtlasVisualSnapshotTests.swift`

**Interfaces:**
- Produces: Atlas full-screen cover from Sightings globe action; correct Timeline, Range, Trace, Predict; meaningful accessible summaries for every visual mode.

- [ ] **Step 1: Add failing product-correctness tests**

```swift
@Test("Atlas defaults to Timeline and exposes the approved mode order")
func atlasModes() {
  #expect(AtlasViewModel.SubView.allCases.map(\.rawValue) == ["Timeline", "Range", "Trace", "Predict"])
  #expect(AtlasViewModel(repository: FixtureWhalesRepository()).activeSubView == .timeline)
}

@Test("Predict copy never represents an estimate as a live location")
func predictionFraming() {
  let copy = PredictPresentation.summary(.fixture)
  #expect(copy.contains("based on historical sightings"))
  #expect(!copy.localizedCaseInsensitiveContains("will be"))
}
```

Test fixed Salish Sea bounds, coordinate projection/clamping, Timeline date filtering, pod color mapping, Range month+pod composition, Trace picker identity, Predict whale and pod subject support, confidence normalization, empty states, and no division by zero for empty heatmaps.

- [ ] **Step 2: Run feature/UI tests and confirm RED**

Run:

```bash
swift test --package-path Packages/FlukeFeatures --filter AtlasProductTests
swift test --package-path Packages/FlukeUI --filter AtlasVisualSnapshotTests
```

Expected: FAIL for missing product assertions and snapshots.

- [ ] **Step 3: Implement the full-screen editorial Atlas pass**

Sightings toolbar order is Atlas globe then Add Sighting. Atlas opens full screen with a close control and Timeline first. Add Fraunces italic geographic labels, subtle bathymetric bands, consistent pod legend, one shared control shelf, a flowing dashed path only when Reduce Motion is off, and a concise text summary that VoiceOver can read instead of traversing every decorative path/cell.

- [ ] **Step 4: Verify all Atlas modes against live contract fixtures and commit**

Run both commands from Step 2 and `scripts/verify-contract-fixtures.sh --no-upstream`.

Expected: PASS with no projection, empty-state, contract, or snapshot failures.

```bash
git add Packages/FlukeFeatures Packages/FlukeUI
git commit -m "feat: polish Atlas signature experience"
```

### Task 6: Complete Accessibility, Privacy, and Permission Audits

**Files:**
- Modify: `App/Fluke/PrivacyInfo.xcprivacy`
- Modify: `App/Fluke/Info.plist`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/**/*.swift`
- Modify: `Packages/FlukeUI/Sources/FlukeUI/**/*.swift`
- Create: `App/FlukeUITests/AccessibilityUITests.swift`
- Create: `scripts/verify-full-launch-privacy.sh`
- Create: `scripts/tests/full-launch-privacy-tests.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: automated permission/privacy assertions plus a manual VoiceOver/Dynamic Type/contrast/Reduce Motion checklist.

- [ ] **Step 1: Write failing script and UI tests**

The script must assert camera/photo usage strings are specific, Sign in with Apple entitlement exists, ATS is not disabled, no location usage description exists, privacy declarations match the four linked-data categories, and no tracking domains or ATT usage exist.

```swift
func testAccessibilityLayoutsAndLabels() throws {
  let app = XCUIApplication()
  app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"]
  app.launch()
  XCTAssertTrue(app.tabBars.buttons["Identify"].isHittable)
  XCTAssertTrue(app.tabBars.buttons["You"].isHittable)
  XCTAssertFalse(app.buttons.matching(identifier: "unlabeled").firstMatch.exists)
}
```

- [ ] **Step 2: Run checks and confirm RED**

Run `scripts/tests/full-launch-privacy-tests.sh` and the app UI test target.

Expected: FAIL because full-launch declarations and audit test identifiers are absent.

- [ ] **Step 3: Fix every audited surface**

Combine complex cards into one meaningful accessibility element, expose status and action separately, hide decorative coastline/polylines, announce queue flush and submission success, keep focus on the first invalid field, provide escape actions for full-screen covers, and ensure no text truncates at accessibility XXXL in portrait.

- [ ] **Step 4: Perform automated and manual verification, then commit**

Run the Step 2 checks. On a physical iPhone, traverse all five tabs, Submit, Movement Track, and four Atlas modes with VoiceOver; repeat at accessibility XXXL, Increase Contrast, Reduce Transparency, and Reduce Motion. Expected: all controls reachable in logical order, no clipped required copy, and no motion-only information.

```bash
git add App/Fluke/PrivacyInfo.xcprivacy App/Fluke/Info.plist App/FlukeUITests Packages/FlukeFeatures Packages/FlukeUI scripts .github/workflows/ci.yml
git commit -m "fix: complete launch accessibility and privacy audit"
```

### Task 7: Replace Release-A Store Assets with Full-Launch Assets

**Files:**
- Modify: `AppStore/1.0/en-US/metadata.json`
- Modify: `AppStore/README.md`
- Replace: `AppStore/1.0/en-US/screenshots/6.9-inch/01-sightings.png`
- Replace: `AppStore/1.0/en-US/screenshots/6.9-inch/02-whales.png`
- Replace: `AppStore/1.0/en-US/screenshots/6.9-inch/03-learn.png`
- Replace: `AppStore/1.0/en-US/screenshots/6.9-inch/04-atlas.png`
- Create: `AppStore/1.0/en-US/screenshots/6.9-inch/03-submit.png`
- Create: `AppStore/1.0/en-US/screenshots/6.9-inch/04-identify.png`
- Create: `AppStore/1.0/en-US/screenshots/6.9-inch/06-you.png`
- Modify: `App/FlukeUITests/FlukeUITests.swift`
- Modify: `scripts/capture-app-store-screenshots.sh`
- Modify: `scripts/verify-app-store-release.sh`
- Modify: `scripts/verify-app-store-archive.sh`

**Interfaces:**
- Produces: seven truthful 1320×2868 screenshots and metadata matching the binary's permissions, accounts, submission, disabled identification, and Atlas behavior.

- [ ] **Step 1: Update verifier tests first**

Require screenshot names `01-sightings`, `02-whales`, `03-submit`, `04-identify`, `05-atlas`, `06-you`, `07-learn`; reject any metadata saying read-only, four tabs, or identification available; require optional accounts, submissions, moderation, queued uploads, rights-cleared training copy, and all privacy categories.

- [ ] **Step 2: Run verification and confirm RED**

Run:

```bash
scripts/tests/verification-scripts-tests.sh
scripts/verify-app-store-release.sh
scripts/verify-app-store-screenshots.sh AppStore/1.0/en-US/screenshots/6.9-inch
```

Expected: FAIL against Release A metadata and four-image set.

- [ ] **Step 3: Write exact truthful metadata and deterministic screenshot states**

Review notes must say Sign in with Apple is optional, provide the reviewer flow, describe public moderation, disclose Render cold starts, state that Identify is visibly in training, and provide no secret credentials. UI tests inject deterministic fixture repositories and capability state so screenshots never capture a loading/error banner or submit real data.

- [ ] **Step 4: Capture, visually inspect, verify, and commit**

Run `scripts/capture-app-store-screenshots.sh` into an empty temporary directory, inspect every PNG at original resolution, replace canonical assets, then rerun Step 2. Expected: seven valid 1320×2868 images, no black bands, permission alerts, loading states, personal data, or misleading identification results.

```bash
git add AppStore App/FlukeUITests/FlukeUITests.swift scripts
git commit -m "chore: prepare full launch App Store assets"
```

### Task 8: Certify, Archive, Upload, and Confirm TestFlight Processing

**Files:**
- Modify: `App/Fluke.xcodeproj/project.pbxproj`
- Modify: `App/ExportOptions.plist`
- Create: `docs/testflight-release-runbook.md`
- Modify: `docs/testing.md`
- Modify: `docs/build-and-ci.md`

**Interfaces:**
- Consumes: Apple team `86RBV2JZ8F`, bundle `app.fluke.Fluke`, the signed-in Xcode/App Store Connect account, and the live API.
- Produces: one uploaded build visible in App Store Connect TestFlight with processing complete and no export-compliance or privacy warning.

- [ ] **Step 1: Add final launch-gate assertions before changing the build number**

Document and execute:

```bash
curl --fail --silent --show-error --max-time 90 https://fluke-api.onrender.com/api/v1/health | jq -e '.status == "ok"'
curl --fail --silent --show-error --max-time 90 https://fluke-api.onrender.com/api/v1/capabilities | jq -e '.accounts == true and .submissions == true and .identification == false'
scripts/verify-contract-fixtures.sh --no-upstream
scripts/verify-app-store-release.sh
scripts/verify-app-store-screenshots.sh AppStore/1.0/en-US/screenshots/6.9-inch
```

Expected: every command exits 0. Stop if capabilities differ; do not upload a binary whose enabled features cannot work against production.

- [ ] **Step 2: Run the entire local test and coverage matrix**

```bash
scripts/tests/verification-scripts-tests.sh
for package in FlukeKit FlukeUI FlukeFeatures; do
  swift test --package-path "Packages/$package" --enable-code-coverage
done
scripts/verify-release-a-boundaries.sh
xcodebuild build -quiet -workspace Fluke.xcworkspace -scheme Fluke -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass, enforced coverage is at least 80%, and Release builds without warnings promoted to errors by the project.

- [ ] **Step 3: Push and verify the real GitHub Actions run**

```bash
git status --short
git push -u origin HEAD
gh run list --workflow CI --branch "$(git branch --show-current)" --limit 1
gh run watch "$(gh run list --workflow CI --branch "$(git branch --show-current)" --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: clean worktree and a green remote workflow. Do not substitute local results for remote CI.

- [ ] **Step 4: Increment the build, archive with distribution signing, and validate**

Set `CURRENT_PROJECT_VERSION` to one greater than the latest App Store Connect build while keeping `MARKETING_VERSION = 1.0`, commit that single change, then run:

```bash
xcodebuild archive -workspace Fluke.xcworkspace -scheme Fluke -configuration Release -destination 'generic/platform=iOS' -archivePath build/testflight/Fluke.xcarchive -allowProvisioningUpdates
scripts/verify-archive-metadata.sh build/testflight/Fluke.xcarchive app.fluke.Fluke 17.0
scripts/verify-app-store-archive.sh build/testflight/Fluke.xcarchive
codesign -d --entitlements :- build/testflight/Fluke.xcarchive/Products/Applications/Fluke.app
```

Expected: archive succeeds with an Apple Distribution identity for team `86RBV2JZ8F`, correct bundle/version, Sign in with Apple entitlement, privacy manifest, and Fraunces license.

- [ ] **Step 5: Upload through Xcode and capture evidence**

```bash
xcodebuild -exportArchive -archivePath build/testflight/Fluke.xcarchive -exportPath build/testflight/export -exportOptionsPlist App/ExportOptions.plist -allowProvisioningUpdates
```

Expected: `** EXPORT SUCCEEDED **` and the upload completes because `destination = upload`. Record the build number, upload timestamp, and Xcode distribution log path in `docs/testflight-release-runbook.md`; do not commit account data or tokens.

- [ ] **Step 6: Confirm processing in App Store Connect and commit the runbook**

Open App Store Connect → Fluke → TestFlight. Wait until the exact uploaded build changes from Processing to Ready to Test, resolve export-compliance prompts with “uses only exempt standard HTTPS encryption,” assign it to the internal tester group, install it on a physical iPhone, and smoke-test all five tabs, Atlas, anonymous submit, queued submit, Apple sign-in, Logbook, sign-out, and disabled Identify.

Expected: the exact build is Ready to Test and installable; every smoke flow matches production capabilities.

```bash
git add App/Fluke.xcodeproj/project.pbxproj docs/testflight-release-runbook.md docs/testing.md docs/build-and-ci.md
git commit -m "chore: certify TestFlight build"
git push
```

## Final Acceptance Checklist

- [ ] Production API health is 200/`ok`; capabilities are accounts true, submissions true, identification false.
- [ ] Sightings and Whales remain fully functional online and from validated stale/offline caches.
- [ ] Five tabs appear in exact approved order; Atlas is not a sixth tab.
- [ ] Anonymous and signed-in submissions work; offline submissions replay without duplicate sightings or lost photos.
- [ ] Optional Sign in with Apple, session restoration, Logbook, and sign-out work on physical hardware.
- [ ] In-app account deletion succeeds against production, clears the observer session, and leaves no recoverable account-linked personal data.
- [ ] A submitted production test photo remains retrievable after an API restart/deploy, proving durable object storage.
- [ ] Identify requests no permission and uploads nothing while disabled; copy explains the rights-cleared training gate.
- [ ] Movement Track and all four Atlas modes show truthful empty, sparse, loading, offline, stale, and error states.
- [ ] Visual review confirms the same PNW editorial identity as the website across every screen.
- [ ] VoiceOver, accessibility XXXL, Reduce Motion, Increase Contrast, and permission-denial paths pass on device.
- [ ] Privacy manifest, nutrition-label answers, usage descriptions, support page, and privacy page match actual behavior.
- [ ] Seven canonical screenshots are truthful, beautiful, and pass automated dimension/band checks.
- [ ] Local tests, coverage gates, archive checks, and the latest GitHub Actions workflow are green.
- [ ] The production-signed build is visible as Ready to Test in TestFlight and installs successfully.
