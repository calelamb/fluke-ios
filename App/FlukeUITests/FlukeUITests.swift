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
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()

        try capture("01-sightings", in: app) {
            app.descendants(matching: .any)["sightings.loaded"].waitForExistence(timeout: 75)
        }
        try captureTab("Whales", named: "02-whales", loadedIdentifier: "whales.loaded", in: app)
        try captureTab("Learn", named: "03-learn", in: app)

        app.tabBars.buttons["Sightings"].tap()
        let atlasButton = app.buttons["Open Atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3))
        atlasButton.tap()
        try capture("04-atlas", in: app) {
            app.descendants(matching: .any)["atlas.timeline.loaded"].waitForExistence(timeout: 75)
        }
    }

    @MainActor
    private func captureTab(
        _ title: String,
        named name: String,
        loadedIdentifier: String? = nil,
        in app: XCUIApplication
    ) throws {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(title) tab")
        tab.tap()
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
}
