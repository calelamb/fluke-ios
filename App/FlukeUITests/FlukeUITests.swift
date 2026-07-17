import XCTest

final class FlukeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPublicBrowseTabsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let navigationTabs = ["Sightings", "Whales", "Learn"]
        XCTAssertEqual(app.tabBars.buttons.count, navigationTabs.count + 1)

        for title in navigationTabs {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(title) tab")
            tab.tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 3),
                "Missing \(title) shipping surface"
            )
        }

        let atlasTab = app.tabBars.buttons["Atlas"]
        XCTAssertTrue(atlasTab.waitForExistence(timeout: 3), "Missing Atlas tab")
        atlasTab.tap()
        XCTAssertTrue(
            app.segmentedControls.firstMatch.waitForExistence(timeout: 3),
            "Missing Atlas mode control"
        )
    }
}
