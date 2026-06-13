import XCTest

/// Tests for the Folders History dialog (View ▸ Folders History…).
///
/// The dialog is an editor over the active pane's recent-directory
/// history: deleting an entry edits that list. Those edits are the
/// source of truth and must persist regardless of how the dialog is
/// dismissed — Cancel means "do not navigate", not "discard my edits".
/// This regression test pins that contract.
final class FoldersHistoryUITests: ShichiZipUITestCase {
    private static let viewMenu = "View"
    private static let foldersHistoryItem = "Folders History..."

    /// Deleting an entry and then dismissing with Cancel must still drop
    /// that entry from the recent-directory history.
    ///
    /// Seeds three distinct directories, deletes the oldest — a
    /// non-current entry, so directory auto-refresh cannot silently
    /// re-record it between Cancel and reopening — clicks Cancel, then
    /// reopens and asserts the surviving count is one lower. Fails before
    /// the fix (Cancel discards the deletion), passes after.
    func testDeletingEntryThenCancellingPersistsTheDeletion() throws {
        let first = try makeTemporaryDirectory(named: "History-First")
        let second = try makeTemporaryDirectory(named: "History-Second")
        let third = try makeTemporaryDirectory(named: "History-Third")

        // Seed history most-recent-first: [third, second, first, …].
        navigate(to: first)
        navigate(to: second)
        navigate(to: third)

        openFoldersHistory()
        let initialCount = try folderHistoryCount()
        XCTAssertGreaterThanOrEqual(initialCount, 3,
                                    "Navigating three directories should seed at least three history entries")

        // Delete `first`: the oldest entry, never the current directory,
        // so an auto-refresh cannot re-record it after we cancel.
        let firstCell = historyCell(endingWith: first.lastPathComponent)
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5),
                      "The seeded directory should be listed in the dialog")
        firstCell.click()
        deleteButton.click()
        waitForFolderHistoryCount(initialCount - 1,
                                  message: "Deleting an entry should drop the in-dialog count immediately")

        cancelButton.click()

        openFoldersHistory()
        let persistedCount = try folderHistoryCount()
        XCTAssertEqual(persistedCount, initialCount - 1,
                       "Cancelling after a delete must still persist the deletion")
        XCTAssertFalse(historyCell(endingWith: first.lastPathComponent).exists,
                       "The deleted directory must not reappear after Cancel")

        cancelButton.click()
    }

    /// Refreshing a directory must not re-record it as a recent visit, so
    /// deleting the *current* directory from the dialog sticks even when
    /// the pane subsequently refreshes.
    ///
    /// Deletes the current directory, dismisses with Cancel, then forces a
    /// refresh — synchronised on a freshly added marker file so the reload
    /// has demonstrably completed — and asserts the directory does not
    /// reappear. Fails before the fix (the refresh re-records the current
    /// directory), passes after.
    func testRefreshingDoesNotResurrectADeletedCurrentDirectory() throws {
        let older = try makeTemporaryDirectory(named: "Refresh-Older")
        let current = try makeTemporaryDirectory(named: "Refresh-Current")

        navigate(to: older)
        navigate(to: current) // `current` is now the current directory and history's front.

        openFoldersHistory()
        let initialCount = try folderHistoryCount()
        XCTAssertGreaterThanOrEqual(initialCount, 2,
                                    "Navigating two directories should seed at least two history entries")

        let currentCell = historyCell(endingWith: current.lastPathComponent)
        XCTAssertTrue(currentCell.waitForExistence(timeout: 5),
                      "The current directory should be listed in the dialog")
        currentCell.click()
        deleteButton.click()
        waitForFolderHistoryCount(initialCount - 1,
                                  message: "Deleting an entry should drop the in-dialog count immediately")
        cancelButton.click()

        // Force a refresh of the still-displayed current directory and wait
        // for it to finish by observing a newly added marker file.
        try createTextFile(at: current.appendingPathComponent("marker.txt"))
        refreshActivePane()
        XCTAssertTrue(leftPaneTable.cells.staticTexts["marker.txt"].waitForExistence(timeout: 10),
                      "Refresh should reload the current directory and surface the new file")

        openFoldersHistory()
        let persistedCount = try folderHistoryCount()
        XCTAssertEqual(persistedCount, initialCount - 1,
                       "Refreshing the current directory must not re-record it after deletion")
        XCTAssertFalse(historyCell(endingWith: current.lastPathComponent).exists,
                       "The deleted current directory must not reappear after a refresh")

        cancelButton.click()
    }

    // MARK: - Helpers

    private var foldersHistoryTable: XCUIElement {
        app.tables.matching(identifier: "foldersHistory.tableView").firstMatch
    }

    private var deleteButton: XCUIElement {
        app.buttons.matching(identifier: "foldersHistory.deleteButton").firstMatch
    }

    private var cancelButton: XCUIElement {
        app.buttons.matching(identifier: "modal.button.0").firstMatch
    }

    private var statusLabel: XCUIElement {
        app.staticTexts.matching(identifier: "foldersHistory.statusLabel").firstMatch
    }

    /// Locates a history row by the trailing component of its path.
    ///
    /// Matching the full path is impossible: XCUI rejects element
    /// subscripts longer than 128 characters, and the cell text is
    /// middle-truncated. The unique (UUID-bearing) last component is short
    /// and survives truncation, which preserves the path's tail.
    private func historyCell(endingWith component: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label ENDSWITH %@ OR value ENDSWITH %@", component, component)
        return foldersHistoryTable.staticTexts.matching(predicate).firstMatch
    }

    private func navigate(to directory: URL) {
        navigateLeftPane(to: directory.path)
        let predicate = NSPredicate(format: "value CONTAINS %@", directory.lastPathComponent)
        let arrived = XCTNSPredicateExpectation(predicate: predicate, object: leftPanePathField)
        wait(for: [arrived], timeout: 5)
    }

    private func openFoldersHistory() {
        app.menuBars.menuBarItems[Self.viewMenu].click()
        app.menuBars.menuBarItems[Self.viewMenu].menus.menuItems[Self.foldersHistoryItem].click()
        XCTAssertTrue(foldersHistoryTable.waitForExistence(timeout: 10),
                      "Folders History dialog should appear")
    }

    private func refreshActivePane() {
        app.menuBars.menuBarItems[Self.viewMenu].click()
        app.menuBars.menuBarItems[Self.viewMenu].menus.menuItems["Refresh"].click()
    }

    private func folderHistoryCount() throws -> Int {
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5), "Status label should exist")
        let value = (statusLabel.value as? String) ?? statusLabel.label
        let digits = value.prefix { $0.isNumber }
        return try XCTUnwrap(Int(digits), "Status label should begin with a count, got: \(value)")
    }

    private func waitForFolderHistoryCount(_ count: Int, message: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", "\(count) ")
        let reached = XCTNSPredicateExpectation(predicate: predicate, object: statusLabel)
        let result = XCTWaiter().wait(for: [reached], timeout: 5)
        XCTAssertEqual(result, .completed, message)
    }
}
