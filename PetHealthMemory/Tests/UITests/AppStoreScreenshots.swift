import XCTest

/// Raw App Store screenshots (light mode, seeded demo data, 9:41 status bar set by CI).
/// Run only by `.github/workflows/appstore.yml`; `scripts/appstore_frames.py` adds captions and
/// renders the exact App Store sizes. The order is the store order: the first three appear in
/// App Store search results, so they carry the core story.
///
///   01 home      — everything in one place
///   02 review    — scan a vet document, check what was found
///   03 history   — timeline linked to source documents
///   04 reminders — never miss a booster
///   05 search    — find anything, offline
///   06 document  — the original, kept privately on device
#if os(iOS)
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "YES", "-seed-sample-data", "YES", "-color-scheme", "light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 20), "Seeded pet should appear")
    }

    func testAppStoreScreens() {
        capture("appstore-01-home")

        // 02 — review sheet for the seeded check-up report.
        open("Documents")
        if !isPad { tap(app.staticTexts["Check-up report"].firstMatch) }
        if tap(app.buttons["Review"].firstMatch) {
            capture("appstore-02-review")
            tap(app.buttons["Later"].firstMatch)
        }
        if !isPad { back() }

        // 03 — timeline (iPad: first record auto-selected in the detail column).
        open("Health History")
        capture("appstore-03-history")

        // 04 — reminders.
        open("Reminders")
        capture("appstore-04-reminders")

        // 05 — search with results.
        if isPad {
            open("Search")
        } else {
            open("Home")
            tap(app.buttons["Search"].firstMatch)
        }
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("Rab\n") // Return submits and hides the keyboard
            sleep(1)
            // iPad: open the matching record so the detail column isn't a placeholder.
            if isPad { tap(app.staticTexts["Riverside Animal Clinic"].firstMatch) }
            capture("appstore-05-search")
        }
        if !isPad, app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }

        // 06 — document detail with the original.
        open("Documents")
        if tap(app.staticTexts["Rabies certificate"].firstMatch) {
            capture("appstore-06-document")
        }
    }

    // MARK: - Helpers

    private func open(_ section: String) {
        if isPad {
            // Sidebar row (the first list). Plain staticTexts[section] can hit a same-named
            // heading in the detail column, e.g. the "Reminders" card.
            let sidebarRow = app.collectionViews.firstMatch.staticTexts[section].firstMatch
            if !tap(sidebarRow) { tap(app.staticTexts[section].firstMatch) }
        } else {
            tap(app.tabBars.buttons[section].firstMatch)
        }
    }

    private func back() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @discardableResult
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return true
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1.0) // thumbnails and charts settle
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
