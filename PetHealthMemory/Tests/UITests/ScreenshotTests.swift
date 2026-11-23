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

    #if os(iOS)
    /// German is the longest of the shipping languages: this run catches truncation and overflow.
    func testTourGerman() { tour(scheme: "light", lang: "de") }
    #endif

    // MARK: - Tour

    private func tour(scheme: String, lang: String = "en") {
        self.lang = lang
        let copy = SampleCopy.forLanguage(lang)
        let prefix = lang == "en" ? scheme : "\(lang)-\(scheme)"
        let app = launch(seeded: true, scheme: scheme)
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 15), "Seeded pet should be on Home")
        snapshot(app, "\(prefix)-01-home")

        #if os(iOS)
        open(app, tab: L("Health History"))
        snapshot(app, "\(prefix)-02-history")

        if tapIfExists(app.staticTexts[copy.rabies].firstMatch) {
            snapshot(app, "\(prefix)-03-event-detail")
            goBack(app)
        }

        // New record form (the "+" menu's primary action).
        if tapIfExists(app.buttons[L("Add record")].firstMatch) {
            snapshot(app, "\(prefix)-12-new-record")
            tapIfExists(app.buttons[L("Cancel")].firstMatch)
        }

        open(app, tab: L("Documents"))
        snapshot(app, "\(prefix)-04-documents")

        if tapIfExists(app.staticTexts[copy.certificateTitle].firstMatch) {
            snapshot(app, "\(prefix)-04b-document-detail")
            goBack(app)
        }

        if tapIfExists(app.staticTexts[copy.reportTitle].firstMatch) {
            if tapIfExists(app.buttons[L("Review")].firstMatch) {
                snapshot(app, "\(prefix)-04c-review")
                tapIfExists(app.buttons[L("Later")].firstMatch)
            }
            goBack(app)
        }

        open(app, tab: L("Reminders"))
        snapshot(app, "\(prefix)-05-reminders")
        if tapIfExists(app.buttons[L("Add reminder")].firstMatch) {
            snapshot(app, "\(prefix)-13-new-reminder")
            tapIfExists(app.buttons[L("Cancel")].firstMatch)
        }

        open(app, tab: L("Home"))
        if tapIfExists(app.buttons[L("Search")].firstMatch) {
            snapshot(app, "\(prefix)-06-search")
            dismissSheet(app)
        }

        if tapIfExists(app.buttons[L("Settings")].firstMatch) {
            snapshot(app, "\(prefix)-07-settings")
            tapIfExists(app.buttons[L("Done")].firstMatch)
        }

        if tapIfExists(app.buttons[L("Export PDF")].firstMatch) {
            snapshot(app, "\(prefix)-08-export")
            tapIfExists(app.buttons[L("Close")].firstMatch)
        }

        // Pet profile → weight log → add weight; profile → edit.
        let openProfile = String(format: L("Open %@ profile"), "Mochi")
        if tapIfExists(app.buttons[openProfile].firstMatch) {
            snapshot(app, "\(prefix)-09-pet-profile")
            if tapIfExists(app.staticTexts[L("Weight")].firstMatch) {
                snapshot(app, "\(prefix)-10-weight-log")
                if tapIfExists(app.buttons[L("Add weight")].firstMatch) {
                    snapshot(app, "\(prefix)-10b-add-weight")
                    tapIfExists(app.buttons[L("Cancel")].firstMatch)
                }
                goBack(app)
            }
            if tapIfExists(app.buttons[L("Edit")].firstMatch) {
                snapshot(app, "\(prefix)-11-edit-pet")
                tapIfExists(app.buttons[L("Cancel")].firstMatch)
            }
            goBack(app)
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

    private var lang = "en"

    /// The app's own translation of a UI string (the catalog is compiled into this test bundle too).
    private func L(_ key: String) -> String {
        guard lang != "en",
              let path = Bundle(for: Self.self).path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private func launch(seeded: Bool, scheme: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Always `-key value` pairs (see LaunchOptions in the app).
        app.launchArguments = ["-ui-testing", "YES", "-color-scheme", scheme]
        if lang != "en" {
            let locale = ["de": "de_DE", "fr": "fr_FR", "ja": "ja_JP"][lang] ?? "en_US"
            app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        }
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

    /// Swipes a sheet down by its grabber area (works while the search field hides the nav bar).
    private func dismissSheet(_ app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        Thread.sleep(forTimeInterval: 1)
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
