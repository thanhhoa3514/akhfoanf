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

    /// Screenshot language. CI passes `TEST_RUNNER_APPSTORE_LANG=de` (xcodebuild strips the prefix).
    private let lang = ProcessInfo.processInfo.environment["APPSTORE_LANG"] ?? "en"
    private var copy: SampleCopy { SampleCopy.forLanguage(lang) }
    private var locale: String {
        ["en": "en_US", "de": "de_DE", "fr": "fr_FR", "ja": "ja_JP"][lang] ?? "en_US"
    }

    /// The app's own translation of a UI string (the catalog is compiled into this test bundle too).
    private func L(_ key: String) -> String {
        guard let path = Bundle(for: Self.self).path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "YES", "-seed-sample-data", "YES", "-color-scheme", "light",
                               "-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 20), "Seeded pet should appear")
    }

    func testAppStoreScreens() {
        capture("appstore-01-home")

        // 02 — review sheet for the seeded check-up report.
        open(L("Documents"))
        if !isPad { tap(app.staticTexts[copy.reportTitle].firstMatch) }
        if tap(app.buttons[L("Review")].firstMatch) {
            capture("appstore-02-review")
            tap(app.buttons[L("Later")].firstMatch)
        }
        if !isPad { back() }

        // 03 — timeline (iPad: first record auto-selected in the detail column).
        open(L("Health History"))
        capture("appstore-03-history")

        // 04 — reminders.
        open(L("Reminders"))
        capture("appstore-04-reminders")

        // 05 — search with results.
        if isPad {
            open(L("Search"))
        } else {
            open(L("Home"))
            tap(app.buttons[L("Search")].firstMatch)
        }
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText(copy.searchTerm + "\n") // Return submits and hides the keyboard
            sleep(1)
            // iPad: open the matching record so the detail column isn't a placeholder.
            if isPad { tap(app.staticTexts[copy.clinicName].firstMatch) }
            capture("appstore-05-search")
        }
        if !isPad, app.buttons[L("Done")].firstMatch.exists { app.buttons[L("Done")].firstMatch.tap() }

        // 06 — document detail with the original.
        open(L("Documents"))
        if tap(app.staticTexts[copy.certificateTitle].firstMatch) {
            capture("appstore-06-document")
        }
    }

    // MARK: - Helpers

    private func open(_ section: String) {
        if isPad {
            // Sidebar row (the first list). Plain staticTexts[section] can hit a same-named
            // heading in the detail column, e.g. the "Reminders" card.
            // The sidebar is the left-most column, so take the left-most match.
            _ = app.staticTexts[section].firstMatch.waitForExistence(timeout: 5)
            let matches = app.staticTexts.matching(identifier: section).allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
            if let row = matches.min(by: { $0.frame.minX < $1.frame.minX }) {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
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
