import XCTest

/// End-to-end flows through the debug Library screen, driving the real app in the iOS Simulator.
///
/// XCTest, not Swift Testing: XCUITest only runs from `XCTestCase`. Every test launches the app with
/// `-TsuzuriUITesting`, so it opens its own empty Library (named by `TSUZURI_UI_TEST_LIBRARY`) with iCloud
/// unavailable, and never touches the simulator's real Library or iCloud.
@MainActor
final class LibraryFlowTests: XCTestCase {
    /// A fresh simulator's first launch can take well over a minute on an Intel Mac.
    private static let launchTimeout: TimeInterval = 180
    private static let timeout: TimeInterval = 20

    private var app: XCUIApplication!
    /// This test's Library directory name; a relaunch with the same name reopens the same Library.
    private var libraryName = ""

    override func setUp() async throws {
        continueAfterFailure = false
        libraryName = "UITest-\(UUID().uuidString)"
        app = launchApp()
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testEmptyLibraryShowsNoWorksAndTheBuildInfo() {
        XCTAssertTrue(app.staticTexts["No Works"].exists)
        XCTAssertTrue(app.staticTexts["buildInfo"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["buildInfo"].label.hasPrefix("Build "))
        XCTAssertFalse(workRow.exists)
    }

    func testAddingASampleWorkListsItWithOnePage() {
        addSampleWork()

        XCTAssertEqual(workRows.count, 1)
        XCTAssertTrue(workRow.label.contains("Sample Work"), workRow.label)
        XCTAssertTrue(workRow.label.contains("Pages: 1"), workRow.label)
        XCTAssertFalse(emptyLibrary.exists)
    }

    func testTappingAWorkShowsItsPageUntilDone() {
        addSampleWork()

        workRow.tap()
        let page = app.images["pageImage"]
        XCTAssertTrue(page.waitForExistence(timeout: Self.timeout))
        XCTAssertGreaterThan(page.frame.width, 0)

        app.buttons["Done"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(workRow.exists)
    }

    func testRenamingAWorkRefusesABlankNameAndSavesTheTrimmedOne() {
        addSampleWork()

        let alert = openRenameAlert()
        let field = alert.textFields.firstMatch
        let save = alert.buttons["Save"]
        clear(field)
        field.typeText("   ")
        XCTAssertFalse(save.isEnabled, "Save must be disabled for a blank name")

        field.typeText("  Night Market  ")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(waitForRow(named: "Night Market"))
        XCTAssertFalse(workRow.label.contains("  Night Market"), workRow.label)
        XCTAssertFalse(workRow.label.contains("Sample Work"), workRow.label)
    }

    func testDeletingAWorkAsksFirstAndCancelKeepsIt() {
        addSampleWork()

        openContextMenu().buttons["Delete"].tap()
        answerDeleteConfirmation(delete: false)
        XCTAssertTrue(workRow.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(workRows.count, 1)

        openContextMenu().buttons["Delete"].tap()
        answerDeleteConfirmation(delete: true)
        XCTAssertTrue(workRow.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(emptyLibrary.waitForExistence(timeout: Self.timeout))
    }

    func testARenamedWorkSurvivesARelaunch() {
        addSampleWork()
        let alert = openRenameAlert()
        clear(alert.textFields.firstMatch)
        alert.textFields.firstMatch.typeText("Kept Across Launches")
        alert.buttons["Save"].tap()
        XCTAssertTrue(waitForRow(named: "Kept Across Launches"))

        app.terminate()
        app = launchApp()

        XCTAssertTrue(waitForRow(named: "Kept Across Launches"))
        XCTAssertEqual(workRows.count, 1)
    }

    func testTheOfflineBannerShowsWithoutBlockingAdding() {
        let banner = app.descendants(matching: .any)["syncBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["syncStatus"].label.contains("Offline"), app.staticTexts["syncStatus"].label)

        addSampleWork()

        XCTAssertTrue(banner.exists)
        XCTAssertEqual(workRows.count, 1)
    }

    // MARK: - Helpers

    private var workRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "workRow") }
    private var workRow: XCUIElement { workRows.firstMatch }
    private var emptyLibrary: XCUIElement { app.descendants(matching: .any)["emptyLibrary"] }

    /// Launches the app on this test's Library and waits for the Library screen.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-TsuzuriUITesting"]
        app.launchEnvironment = ["TSUZURI_UI_TEST_LIBRARY": libraryName]
        app.launch()
        XCTAssertTrue(app.buttons["addSampleWork"].waitForExistence(timeout: Self.launchTimeout),
                      "The Library screen never appeared")
        return app
    }

    private func addSampleWork() {
        let before = workRows.count
        app.buttons["addSampleWork"].tap()
        XCTAssertTrue(eventually { self.workRows.count == before + 1 }, "No Work was added")
    }

    private func waitForRow(named name: String) -> Bool {
        eventually { self.workRow.exists && self.workRow.label.contains(name) }
    }

    /// Whether `condition` holds within `timeout`, checking it a few times a second.
    private func eventually(timeout: TimeInterval = LibraryFlowTests.timeout, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return condition()
    }

    /// Long-presses the first Work and returns the app, once the context menu is showing.
    @discardableResult
    private func openContextMenu() -> XCUIApplication {
        workRow.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: Self.timeout), "No context menu")
        return app
    }

    private func openRenameAlert() -> XCUIElement {
        openContextMenu().buttons["Rename"].tap()
        let alert = app.alerts["Rename Work"]
        XCTAssertTrue(alert.waitForExistence(timeout: Self.timeout))
        return alert
    }

    /// Answers the delete confirmation with its `Delete` button, or cancels it: with its `Cancel` button where the
    /// OS shows one, else by tapping outside it (iOS 26 shows it on iPhone as a popover without a Cancel button).
    private func answerDeleteConfirmation(delete: Bool) {
        let prompt = app.staticTexts["Delete “Sample Work”?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.timeout), "No delete confirmation")
        if delete {
            app.buttons.matching(identifier: "Delete").element(boundBy: 0).tap()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // The dialog is a popover anchored near the top; its dismiss region covers the screen behind it.
            app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        }
        XCTAssertTrue(prompt.waitForNonExistence(timeout: Self.timeout))
    }

    private func clear(_ field: XCUIElement) {
        field.tap()
        let text = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 2))
    }
}
