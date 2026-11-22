import XCTest

/// End-to-end screenshot tour. Launches the real app (in-memory store, seeded demo pet),
/// walks the main screens and attaches a screenshot of each one to the test result.
/// CI exports the attachments from the .xcresult bundle and uploads them as an artifact.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testFirstLaunch() {
        let app = launch(seeded: false, scheme: "light")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15), "Pet form should open on first launch")
        snapshot(app, "00-first-launch")
    }

    func testTourLight() { tour(scheme: "light") }

    func testTourDark() { tour(scheme: "dark") }

    // MARK: - Tour

    private func tour(scheme: String) {
        let app = launch(seeded: true, scheme: scheme)
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 15), "Seeded pet should be on Home")
        snapshot(app, "\(scheme)-01-home")

        #if os(iOS)
        open(app, tab: "Health History")
        snapshot(app, "\(scheme)-02-history")

        if tapIfExists(app.staticTexts["Rabies"].firstMatch) {
            snapshot(app, "\(scheme)-03-event-detail")
            goBack(app)
        }

        open(app, tab: "Documents")
        snapshot(app, "\(scheme)-04-documents")

        if tapIfExists(app.staticTexts["Rabies certificate"].firstMatch) {
            snapshot(app, "\(scheme)-04b-document-detail")
            goBack(app)
        }

        if tapIfExists(app.staticTexts["Check-up report"].firstMatch) {
            if tapIfExists(app.buttons["Review"].firstMatch) {
                snapshot(app, "\(scheme)-04c-review")
                tapIfExists(app.buttons["Later"].firstMatch)
            }
            goBack(app)
        }

        open(app, tab: "Reminders")
        snapshot(app, "\(scheme)-05-reminders")

        open(app, tab: "Home")
        if tapIfExists(app.buttons["Search"].firstMatch) {
            snapshot(app, "\(scheme)-06-search")
        }
        #else
        // macOS: three-column split view. Sidebar section → content list → detail.
        openSection(app, "Health History")
        selectRow(app, "Rabies")
        snapshot(app, "\(scheme)-02-history")

        // Wide layouts auto-select the first document: the report waiting for review.
        openSection(app, "Documents")
        snapshot(app, "\(scheme)-04-documents")
        if tapIfExists(app.buttons["Review"].firstMatch) {
            snapshot(app, "\(scheme)-04c-review")
            tapIfExists(app.buttons["Later"].firstMatch)
        }
        if selectRow(app, "Rabies certificate") {
            snapshot(app, "\(scheme)-04b-document-detail")
        }

        openSection(app, "Reminders")
        snapshot(app, "\(scheme)-05-reminders")

        openSection(app, "Search")
        snapshot(app, "\(scheme)-06-search")

        app.typeKey(",", modifierFlags: .command)
        if app.windows.count > 1 || app.windows.firstMatch.waitForExistence(timeout: 3) {
            snapshot(app, "\(scheme)-07-settings")
        }
        #endif
    }

    // MARK: - Helpers

    private func launch(seeded: Bool, scheme: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Always `-key value` pairs (see LaunchOptions in the app).
        app.launchArguments = ["-ui-testing", "YES", "-color-scheme", scheme]
        if seeded { app.launchArguments += ["-seed-sample-data", "YES"] }
        #if os(macOS)
        // Start from a fresh window instead of restoring the previous test's state.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        return app
    }

    #if os(iOS)
    private func open(_ app: XCUIApplication, tab: String) {
        let button = app.tabBars.buttons[tab].firstMatch
        if !tapIfExists(button) {
            XCTFail("Tab '\(tab)' not found")
        }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }
    #else
    private func openSection(_ app: XCUIApplication, _ title: String) {
        let sidebarRow = app.outlines.firstMatch.staticTexts[title].firstMatch
        if !tapIfExists(sidebarRow, timeout: 3), !tapIfExists(app.staticTexts[title].firstMatch) {
            XCTFail("Sidebar section '\(title)' not found")
        }
    }

    /// Clicks the list row showing `title`. SwiftUI list rows on macOS often report
    /// isHittable == false, so click the text's centre by coordinate instead.
    @discardableResult
    private func selectRow(_ app: XCUIApplication, _ title: String) -> Bool {
        let text = app.staticTexts[title].firstMatch
        guard text.waitForExistence(timeout: 3) else { return false }
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        return true
    }
    #endif

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
        return true
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        // Let transitions and async thumbnails settle (animations are disabled in -ui-testing).
        _ = app.wait(for: .runningForeground, timeout: 2)
        Thread.sleep(forTimeInterval: 0.5)
        #if os(macOS)
        // The frontmost window only (not the whole runner desktop).
        let window = app.windows.firstMatch
        let image = window.exists ? window.screenshot() : app.screenshot()
        #else
        let image = app.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
