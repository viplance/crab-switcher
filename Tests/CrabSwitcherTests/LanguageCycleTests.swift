import XCTest
import CoreGraphics
@testable import CrabSwitcher

final class LanguageCycleTests: XCTestCase {
    private let available = ["english", "russian", "german"]

    func testNoSelectionDoesNothing() {
        XCTAssertNil(LanguageCycle.nextID(
            currentID: "english",
            selectedIDs: [],
            availableIDs: available
        ))
    }

    func testOneSelectionAlwaysSelectsThatLanguage() {
        XCTAssertEqual(LanguageCycle.nextID(
            currentID: "english",
            selectedIDs: ["russian"],
            availableIDs: available
        ), "russian")
    }

    func testMultipleSelectionsAdvanceInAvailableListOrder() {
        let selected: Set<String> = ["english", "german"]
        XCTAssertEqual(LanguageCycle.nextID(
            currentID: "english",
            selectedIDs: selected,
            availableIDs: available
        ), "german")
        XCTAssertEqual(LanguageCycle.nextID(
            currentID: "german",
            selectedIDs: selected,
            availableIDs: available
        ), "english")
    }

    func testCurrentUnselectedLanguageStartsAtFirstSelection() {
        XCTAssertEqual(LanguageCycle.nextID(
            currentID: "russian",
            selectedIDs: ["english", "german"],
            availableIDs: available
        ), "english")
    }

    func testUnavailableSelectionIsIgnored() {
        XCTAssertNil(LanguageCycle.nextID(
            currentID: "english",
            selectedIDs: ["french"],
            availableIDs: available
        ))
    }
}

final class CustomHotkeyTests: XCTestCase {
    func testCustomHotkeyMatchesExactModifiers() {
        let hotkey = CustomHotkey(
            keyCode: 49,
            modifiers: CGEventFlags.maskControl.union(.maskAlternate).rawValue
        )
        XCTAssertTrue(hotkey.matches(
            keyCode: 49,
            flags: [.maskControl, .maskAlternate]
        ))
        XCTAssertFalse(hotkey.matches(
            keyCode: 49,
            flags: [.maskControl, .maskAlternate, .maskShift]
        ))
        XCTAssertFalse(hotkey.matches(
            keyCode: 0,
            flags: [.maskControl, .maskAlternate]
        ))
    }

    func testFnOnlyDoesNotMatchKeyDown() {
        let hotkey = CustomHotkey.fn
        XCTAssertFalse(hotkey.matches(keyCode: 49, flags: [.maskSecondaryFn]))
    }

    func testTitle() {
        XCTAssertEqual(CustomHotkey.fn.title, "Fn")
        let ctrlSpace = CustomHotkey(
            keyCode: 49,
            modifiers: CGEventFlags.maskControl.rawValue
        )
        XCTAssertEqual(ctrlSpace.title, "⌃Space")
    }
}
