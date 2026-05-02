# Testing

Test strategy for the iOS app. Coverage targets, what gets tested at each layer, and the patterns we use.

## Targets

| Layer | Coverage target | Strategy |
| --- | --- | --- |
| `FlukeKit` (domain) | 80%+ | XCTest unit tests; `MockURLProtocol` for HTTP; in-memory `ModelContainer` for SwiftData |
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
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Or `⌘U` in Xcode with the `Fluke` scheme selected.

Note: `iPhone 17` reflects the local Xcode 16 / iOS 26 toolchain. Older Xcode installs may need `iPhone 15` or `iPhone 16`. CI uses `OS=latest` and `iPhone 16` on `macos-15` runners — see [`build-and-ci.md`](build-and-ci.md).

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

### In-memory SwiftData container for persistence tests

```swift
let container = try ModelContainer.fluke(inMemory: true)
let context = ModelContext(container)
context.insert(CachedWhale(/* … */))
try context.save()

let fetched = try context.fetch(FetchDescriptor<CachedWhale>())
XCTAssertEqual(fetched.count, 1)
```

The in-memory mode uses `isStoredInMemoryOnly: true` on `ModelConfiguration` — no disk write, fresh state per test.

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

- **Don't test framework internals.** A test that just exercises SwiftData's CRUD doesn't cover our code; it covers Apple's. Test our wrappers + behavior.
- **Don't mock what you don't own** *too* aggressively. Mocking `URLSession` (we own the wrapper around it) is fine. Mocking SwiftData itself isn't worth the bother; use the in-memory configuration.
- **Don't test private state.** Test through the public API. If you can't reach the behavior through the public interface, the API is wrong, not the test.
- **Don't share state between tests.** `setUp`/`tearDown` reset everything. The order of test execution should not matter.

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

Aim for 80%+ on `FlukeKit`. `FlukeUI` is dominated by view code where snapshot tests carry the regression load. `FlukeFeatures` covers view-model logic plus minimal render tests; coverage there is meaningful for view models and incidental for views.

## CI

Every push and PR runs:

- `swift test` for each of the three packages (matrix of 3 jobs).
- `xcodebuild test` for the full Xcode workspace.

Failures upload an `.xcresult` bundle as an artifact you can download and open in Xcode for diagnosis. See [`build-and-ci.md`](build-and-ci.md) for the workflow details.
