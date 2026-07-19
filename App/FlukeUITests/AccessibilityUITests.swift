import XCTest

final class AccessibilityUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testAccessibilityXXXLReduceMotionFiveTabsAndAtlasModes() throws {
    let app = launchAccessibilityApp()

    for title in ["Sightings", "Whales", "Identify", "Learn", "You"] {
      let tab = app.tabBars.buttons[title]
      XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing \(title) tab")
      XCTAssertTrue(
        waitForHittable(tab, timeout: 5),
        "\(title) tab is not reachable at accessibility XXXL"
      )
    }

    app.tabBars.buttons["Sightings"].tap()
    let addSighting = app.buttons["Add Sighting"]
    XCTAssertTrue(addSighting.waitForExistence(timeout: 8))
    XCTAssertTrue(addSighting.isHittable)

    let atlas = app.buttons["Open Atlas"]
    XCTAssertTrue(atlas.isHittable)
    atlas.tap()
    XCTAssertTrue(app.otherElements["atlas.fullScreen"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons["Close Atlas"].isHittable)

    let mode = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Atlas mode:")
    ).firstMatch
    XCTAssertTrue(
      mode.waitForExistence(timeout: 8), "Atlas mode menu must replace segmented controls")
    for title in ["Timeline", "Range", "Trace", "Predict"] {
      mode.tap()
      let option = app.buttons[title]
      XCTAssertTrue(option.waitForExistence(timeout: 3), "Missing Atlas mode \(title)")
      XCTAssertTrue(waitForHittable(option, timeout: 3), "Atlas mode \(title) is not reachable")
      option.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["\(title) Atlas mode"]
          .waitForExistence(timeout: 8),
        "Missing accessible \(title) surface"
      )
    }
  }

  @MainActor
  func testIdentifyDisabledDoesNotRequestCameraOrPhotoPermission() throws {
    let app = launchAccessibilityApp(resetPermissions: true)
    app.tabBars.buttons["Identify"].tap()
    XCTAssertTrue(
      app.staticTexts["On-device identification unavailable"].waitForExistence(timeout: 8))
    XCTAssertFalse(
      app.alerts.firstMatch.exists, "Disabled Identify must not request media permission")
    XCTAssertFalse(app.buttons["Take photo"].exists)
    XCTAssertFalse(app.buttons["Choose photo"].exists)
  }

  @MainActor
  private func launchAccessibilityApp(resetPermissions: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    if resetPermissions {
      app.launchArguments += ["-FlukeResetPermissionsForUITests", "YES"]
    }
    app.launchArguments += [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-UIAccessibilityReduceMotionEnabled", "YES",
      "-UIAccessibilityReduceTransparencyEnabled", "YES",
      "-UIAccessibilityDarkerSystemColorsEnabled", "YES",
    ]
    app.launch()
    return app
  }

  @MainActor
  private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true"),
      object: element
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }
}
