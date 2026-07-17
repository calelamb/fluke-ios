# Testing

Test strategy for the iOS app. Coverage targets, what gets tested at each layer, and the patterns we use.

## Targets

| Layer | Coverage target | Strategy |
| --- | --- | --- |
| `FlukeKit` (domain) | 80%+ source lines | Swift Testing/XCTest; injected `HTTPTransport`; in-memory actor cache |
| `FlukeUI` (design system) | Snapshot regression on visual components | `swift-snapshot-testing` PNG references in `__Snapshots__/` |
| `FlukeFeatures` (screens) | View model logic + render-doesn't-crash | XCTest unit tests for view models; minimal smoke render tests |
| `App` (UI tests) | Critical user flows | XCUITest — sign in (mocked), submit a sighting, browse a whale, identify-tab placeholder |

## Running tests

### Per-package (fast feedback)

```bash
# From repo root
cd Packages/FlukeKit && swift test
cd Packages/FlukeUI && swift test
cd Packages/FlukeFeatures && swift test
```

Or all three in one shot:

```bash
for pkg in FlukeKit FlukeUI FlukeFeatures; do
  echo "--- $pkg ---"
  ( cd "Packages/$pkg" && swift test )
done
```

Each package runs in <1s for cached builds, ~30s on first build (resolving dependencies).

### Xcode workspace (full integration + UI tests)

```bash
xcodebuild test \
  -workspace Fluke.xcworkspace \
  -scheme Fluke \
  -destination 'platform=iOS Simulator,id=<resolved-udid>' \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1
```

Or `⌘U` in Xcode with the `Fluke` scheme selected.

Run `scripts/prepare-ios-simulator.sh` to resolve and boot the same iPhone 17 / iOS 26.0 destination used by CI. CI serializes app tests to avoid CoreSimulator startup races and always collects simulator diagnostics — see [`build-and-ci.md`](build-and-ci.md).

## Patterns

### `MockURLProtocol` for HTTP tests

Lives at [`Packages/FlukeKit/Tests/FlukeKitTests/Mocks/MockURLProtocol.swift`](../Packages/FlukeKit/Tests/FlukeKitTests/Mocks/MockURLProtocol.swift). A `URLProtocol` subclass that intercepts requests sent through a configured `URLSession`. Set the static `handler` closure to return per-request responses.

Use:

```swift
override func setUp() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    apiClient = APIClient(baseURL: URL(string: "http://localhost:4000")!, session: session)
}

func test_get_decodesArrayOfWhales() async throws {
    MockURLProtocol.handler = { request in
        XCTAssertEqual(request.url?.path, "/api/v1/whales")
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            stubBody
        )
    }
    let whales: [Whale] = try await apiClient.get("/api/v1/whales")
    XCTAssertEqual(whales.count, 1)
}
```

**Always** clear the handler in `tearDown`:

```swift
override func tearDown() async throws {
    MockURLProtocol.handler = nil
}
```

### In-memory browse cache for persistence tests

```swift
let cache = MemoryBrowseCacheStore()
let key = BrowseCacheKey(resource: "whales", identity: "catalog")
let document = BrowseCacheDocument(
    resource: key.resource,
    fetchedAt: Date(),
    payload: BrowsePayload.value([whale])
)
try await cache.replace(document, for: key)

let fetched = try await cache.load([Whale].self, for: key)
#expect(fetched?.payload == .value([whale]))
```

The actor store has no disk writes and starts empty for each test. File-store tests inject a writer, clock, diagnostics sink, and temporary directory to verify atomic last-known-good behavior, schema handling, active-cache quotas, and optional-first eviction.

### Snapshot tests for UI components

Land in `FlukeUI/Tests/FlukeUITests/`. Use [`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing).

```swift
import SwiftUI
import XCTest
import SnapshotTesting
@testable import FlukeUI

final class EcotypeBadgeSnapshotTests: XCTestCase {
    func test_resident() {
        let view = EcotypeBadge(label: "Resident", color: .tide)
            .padding(16)
            .background(Color.bone)
        assertSnapshot(of: view, as: .image)
    }
}
```

**First run records** reference PNGs to `__Snapshots__/<TestClass>/<TestName>.1.png` and reports the test as "failed" with `Recorded:` messages. **Run again** — subsequent runs compare against the recorded reference and pass when they match.

To re-record (e.g., after a deliberate visual change), delete the relevant PNG file and run again.

The recorded snapshots are committed to git — they're the visual contract. PRs touching components should show the updated PNG diffs.

### View model tests

View models live in `FlukeFeatures/<Feature>/<Feature>ViewModel.swift`. Test them with mocked repositories:

```swift
let repo = MockWhalesRepository(stubAll: [Whale.fixture()])
let vm = WhalesViewModel(repository: repo)

await vm.load()

XCTAssertEqual(vm.allWhales.count, 1)
XCTAssertEqual(vm.loadState, .loaded)
```

Repositories pass an `actor` interface; the mock conforms to the same interface and stubs the responses. Don't introduce a protocol just for testing — actors are already a clean boundary.

### XCUITest for critical flows

Live in `App/FlukeUITests/`. Cover the user-visible flows the app promises:

- Tab bar smoke test (all 5 tabs reachable)
- Submit sheet open/cancel
- Sightings list/map toggle
- Whales catalog search

Don't try to UI-test every interaction — UI tests are slow (~30s per launch). They protect critical paths; unit tests cover logic.

```swift
final class TabBarSmokeTests: XCTestCase {
    func test_appLaunchesAndAllFiveTabsAreReachable() {
        let app = XCUIApplication()
        app.launch()
        for label in ["Sightings", "Whales", "Identify", "Learn", "You"] {
            app.tabBars.buttons[label].tap()
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 2))
        }
    }
}
```

## Test naming

Pattern: `test_<methodOrFeature>_<expectedBehavior>`.

- `test_get_decodesArrayOfWhales` ✓
- `test_signInWithApple_postsTokenAndReturnsUser` ✓
- `test_emptyState_showsCTAWhenNoSightings` ✓
- `test1` ✗ (anti-pattern — say what it tests)

## Avoiding test pitfalls

- **Don't test framework internals.** Test our cache wrappers, validation, and fallback behavior rather than Foundation's JSON implementation.
- **Don't mock what you don't own** *too* aggressively. Inject `HTTPTransport` and `BrowseCacheStore`, which are boundaries we own.
- **Don't test private state.** Test through the public API. If you can't reach the behavior through the public interface, the API is wrong, not the test.
- **Don't share state between tests.** `setUp`/`tearDown` reset everything. The order of test execution should not matter.
- **Exercise hostile boundaries.** Repository tests cover invalid date windows and identifiers, path/query encoding, array and item caps, absolute timeouts (including transports that ignore cancellation), cross-identity responses, and malformed cache schemas.

## Coverage commands

```bash
# Per-package coverage
cd Packages/FlukeKit
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/FlukeKitPackageTests.xctest/Contents/MacOS/FlukeKitPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata \
  --use-color
```

CI runs `scripts/verify-swift-package-coverage.sh` against `/Sources/FlukeKit/` and requires 80%+. Test targets and generated runner files are excluded from the calculation. `FlukeUI` is dominated by view code where snapshot tests carry the regression load. `FlukeFeatures` covers view-model logic plus minimal render tests; coverage there is meaningful for view models and incidental for views.

## CI

Every push and PR runs:

- `swift test` for each of the three packages (matrix of 3 jobs).
- `xcodebuild test` for the full Xcode workspace.

Failures upload an `.xcresult` bundle as an artifact you can download and open in Xcode for diagnosis. See [`build-and-ci.md`](build-and-ci.md) for the workflow details.
