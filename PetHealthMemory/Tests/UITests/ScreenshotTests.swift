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
        for (index, section) in ["Health History", "Documents", "Reminders", "Search"].enumerated() {
            if tapIfExists(app.staticTexts[section].firstMatch) {
                snapshot(app, "\(scheme)-0\(index + 2)-\(section.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
        }
        #endif
    }

    // MARK: - Helpers

    private func launch(seeded: Bool, scheme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-color-scheme", scheme]
        if seeded { app.launchArguments.append("-seed-sample-data") }
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
