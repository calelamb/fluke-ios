import XCTest

final class FlukeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPublicBrowseTabsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let navigationTabs = ["Sightings", "Whales", "Identify", "Learn", "You"]
        XCTAssertEqual(app.tabBars.buttons.count, navigationTabs.count)

        for title in navigationTabs {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(title) tab")
            tab.tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 3),
                "Missing \(title) shipping surface"
            )
        }

        app.tabBars.buttons["Sightings"].tap()
        let atlasButton = app.buttons["Open Atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3), "Missing Atlas entry point")
        atlasButton.tap()
        XCTAssertTrue(
            app.segmentedControls.firstMatch.waitForExistence(timeout: 3),
            "Missing Atlas mode control"
        )
        XCTAssertTrue(
            app.buttons["Close Atlas"].waitForExistence(timeout: 3),
            "Missing Atlas close control"
        )
    }

    @MainActor
    func testAtlasPresentationKeepsControlsBelowTheStatusBar() throws {
        let app = XCUIApplication()
        app.launchArguments.append(AppStoreScreenshotFixtureArgument.value)
        app.launchEnvironment["FLUKE_XCTEST_FIXTURES"] = "1"
        app.launch()

        let atlasButton = app.buttons["Open Atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3))
        atlasButton.tap()

        let title = app.staticTexts["Atlas"]
        let close = app.buttons["Close Atlas"]
        let window = app.windows.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Missing the Atlas title")
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        let minimumSafeY = max(44, window.frame.height * 0.045)
        XCTAssertGreaterThanOrEqual(title.frame.minY, minimumSafeY)
        XCTAssertGreaterThanOrEqual(close.frame.minY, minimumSafeY)
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            AppStoreScreenshotFixtureArgument.value,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launchEnvironment["FLUKE_XCTEST_FIXTURES"] = "1"
        app.launch()

        try capture("01-sightings", in: app) {
            app.descendants(matching: .any)["sightings.loaded"].waitForExistence(timeout: 75)
        }
        try captureTab(
            "Whales",
            named: "02-whales",
            loadedIdentifier: "whales.loaded",
            in: app
        ) {
            assertWhaleFiltersAreFullyFramed(in: app)
        }

        app.tabBars.buttons["Sightings"].tap()
        let addSightingButton = app.buttons["Add Sighting"]
        XCTAssertTrue(addSightingButton.waitForExistence(timeout: 3))
        addSightingButton.tap()
        reframeSubmitFormWithoutUnloadedMapTiles(in: app)
        try capture("03-submit", in: app) {
            app.navigationBars["Add Sighting"].waitForExistence(timeout: 10)
        }
        app.buttons["Close"].tap()

        try captureTab("Identify", named: "04-identify", in: app) {
            reframeAboveTabBar(app.buttons["Submit a sighting"], in: app)
        }

        app.tabBars.buttons["Sightings"].tap()
        let atlasButton = app.buttons["Open Atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3))
        atlasButton.tap()
        try capture("05-atlas", in: app) {
            app.descendants(matching: .any)["atlas.timeline.loaded"].waitForExistence(timeout: 75)
        }
        app.buttons["Close Atlas"].tap()

        try captureTab("You", named: "06-you", in: app)
        try captureTab("Learn", named: "07-learn", in: app) {
            let savedDataCard = app.buttons.containing(
                .staticText,
                identifier: "What saved data means"
            ).firstMatch
            reframeAboveTabBar(savedDataCard, in: app)
        }
    }

    @MainActor
    private func captureTab(
        _ title: String,
        named name: String,
        loadedIdentifier: String? = nil,
        in app: XCUIApplication,
        beforeCapture: () -> Void = {}
    ) throws {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(title) tab")
        tab.tap()
        beforeCapture()
        try capture(name, in: app) {
            if let loadedIdentifier {
                return app.descendants(matching: .any)[loadedIdentifier].waitForExistence(timeout: 75)
            }
            return app.navigationBars[title].waitForExistence(timeout: 10)
        }
    }

    @MainActor
    private func capture(
        _ name: String,
        in app: XCUIApplication,
        whenReady: () -> Bool
    ) throws {
        XCTAssertTrue(whenReady(), "Screen was not ready for \(name)")
        Thread.sleep(forTimeInterval: 1)
        assertNoReleaseErrorBanner(in: app, screenshotName: name)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertNoReleaseErrorBanner(
        in app: XCUIApplication,
        screenshotName: String
    ) {
        let rejectedMessages = [
            "A required service is temporarily unavailable.",
            "Sightings unavailable",
            "Catalog unavailable",
        ]
        for message in rejectedMessages {
            XCTAssertFalse(
                app.staticTexts[message].exists,
                "Release screenshot \(screenshotName) contains an error state: \(message)"
            )
        }
    }

    @MainActor
    private func assertWhaleFiltersAreFullyFramed(in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for label in ["All", "Resident", "Bigg's", "Offshore", "Unknown"] {
            let filter = app.buttons[label]
            XCTAssertTrue(filter.waitForExistence(timeout: 3), "Missing \(label) whale filter")
            XCTAssertGreaterThanOrEqual(filter.frame.minX, window.minX + 12)
            XCTAssertLessThanOrEqual(filter.frame.maxX, window.maxX - 12)
        }
    }

    @MainActor
    private func reframeSubmitFormWithoutUnloadedMapTiles(in app: XCUIApplication) {
        let preview = app.descendants(matching: .any)["location.preview"]
        XCTAssertTrue(
            preview.waitForExistence(timeout: 3),
            "Screenshot fixtures must use the deterministic coarse-coordinate preview"
        )
        XCTAssertFalse(app.maps.firstMatch.exists, "Screenshot fixtures must not wait on map tiles")
    }

    @MainActor
    private func reframeAboveTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing screenshot framing anchor")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<4 where element.frame.maxY > tabBar.frame.minY - 12 {
            dragUpSlightly(in: scrollView)
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, tabBar.frame.minY - 12)
    }

    @MainActor
    private func dragUpSlightly(in scrollView: XCUIElement) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}

private enum AppStoreScreenshotFixtureArgument {
    static let value = "-FlukeXCTestAppStoreFixtures"
}
