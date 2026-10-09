//
//  NotchWindowPlannerTests.swift
//  boringNotchTests
//
//  Pure screen -> notch-window planning: two-screen (MacBook + external) placement,
//  window removals, and the closed-notch height rule that keeps the synthetic notch
//  on displays without a hardware notch while the user asked for all displays.
//

import XCTest
import CoreGraphics
import Foundation

final class NotchWindowPlannerTests: XCTestCase {

    // MARK: - Fixtures

    /// MacBook built-in display: hardware notch, main display at the global origin.
    private let macbook = NotchScreen(
        uuid: "macbook-notched",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        hasNotch: true
    )

    /// External monitor: no hardware notch, placed LEFT of the main display,
    /// so its frame origin is negative and pins the top-centre arithmetic.
    private let external = NotchScreen(
        uuid: "external-flat",
        frame: CGRect(x: -1920, y: -10, width: 2560, height: 1440),
        hasNotch: false
    )

    private let windowSize = CGSize(width: 280, height: 32)
    private let closedHeight: CGFloat = 38

    // MARK: - Helpers

    /// Expected top-centre origin, computed independently of the planner formula.
    private func expectedOrigin(for screen: NotchScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX - windowSize.width / 2,
                y: screen.frame.maxY - windowSize.height)
    }

    /// A plan is only valid if no uuid is simultaneously getting a window and losing one.
    private func assertPlacementsAndRemovalsDisjoint(
        _ plan: NotchWindowPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let placed = Set(plan.placements.map(\.uuid))
        let removed = Set(plan.removals)
        XCTAssertEqual(placed.intersection(removed), [],
                       "a uuid must never appear in both placements and removals",
                       file: file, line: line)
    }

    // MARK: - Origin arithmetic

    func testOriginIsTopCentreForPositiveAndNegativeFrameOrigins() {
        XCTAssertEqual(NotchWindowPlanner.origin(for: macbook, windowSize: windowSize),
                       CGPoint(x: 616, y: 950),
                       "notched main display: x = 0 + 1512/2 - 280/2, y = 0 + 982 - 32")
        XCTAssertEqual(NotchWindowPlanner.origin(for: external, windowSize: windowSize),
                       CGPoint(x: -780, y: 1398),
                       "external left of main: x = -1920 + 2560/2 - 280/2, y = -10 + 1440 - 32")
    }

    // MARK: - Two screens, all displays

    func testShowOnAllDisplaysPlacesBothScreensAtTopCentreInScreenOrder() {
        let screens = [macbook, external]
        let plan = NotchWindowPlanner.plan(screens: screens,
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [],
                                           showOnAllDisplays: true,
                                           selectedUUID: nil)

        XCTAssertEqual(plan.placements, [
            NotchWindowPlacement(uuid: macbook.uuid, origin: expectedOrigin(for: macbook)),
            NotchWindowPlacement(uuid: external.uuid, origin: expectedOrigin(for: external)),
        ], "one window per screen, in screens order, each at its screen's top centre")
        XCTAssertEqual(plan.removals, [], "nothing to remove when no windows existed")
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    func testPlacementOrderFollowsScreensOrder() {
        let screens = [external, macbook]
        let plan = NotchWindowPlanner.plan(screens: screens,
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [],
                                           showOnAllDisplays: true,
                                           selectedUUID: nil)

        XCTAssertEqual(plan.placements.map(\.uuid), [external.uuid, macbook.uuid])
        XCTAssertEqual(plan.placements.map(\.origin),
                       [expectedOrigin(for: external), expectedOrigin(for: macbook)])
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    func testExistingWindowOnStillPresentScreenIsKeptAndMovedNotRemoved() {
        let plan = NotchWindowPlanner.plan(screens: [macbook, external],
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [external.uuid],
                                           showOnAllDisplays: true,
                                           selectedUUID: nil)

        XCTAssertFalse(plan.removals.contains(external.uuid),
                       "the external window's screen is still present: keep the window")
        XCTAssertEqual(plan.removals, [])
        XCTAssertEqual(plan.placements, [
            NotchWindowPlacement(uuid: macbook.uuid, origin: expectedOrigin(for: macbook)),
            NotchWindowPlacement(uuid: external.uuid, origin: expectedOrigin(for: external)),
        ], "the kept window still gets its placement so it can be moved")
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    // MARK: - Screen disappears

    func testVanishedScreenIsRemovedRemainingScreenStillPlaced() {
        let plan = NotchWindowPlanner.plan(screens: [macbook],
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [macbook.uuid, external.uuid],
                                           showOnAllDisplays: true,
                                           selectedUUID: nil)

        XCTAssertEqual(plan.removals, [external.uuid],
                       "the external screen is gone: close its window")
        XCTAssertEqual(plan.placements, [
            NotchWindowPlacement(uuid: macbook.uuid, origin: expectedOrigin(for: macbook))
        ])
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    // MARK: - Single-display mode (showOnAllDisplays == false)

    func testSingleDisplayModePlacesOnlySelectedScreenAndRemovesOthers() {
        let plan = NotchWindowPlanner.plan(screens: [macbook, external],
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [macbook.uuid, external.uuid],
                                           showOnAllDisplays: false,
                                           selectedUUID: external.uuid)

        XCTAssertEqual(plan.placements, [
            NotchWindowPlacement(uuid: external.uuid, origin: expectedOrigin(for: external))
        ], "exactly one window, on the selected screen, at its top centre")
        XCTAssertEqual(plan.removals, [macbook.uuid],
                       "the now-unselected screen's window must close")
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    func testSingleDisplayModeWithNilSelectionRemovesEveryWindow() {
        let plan = NotchWindowPlanner.plan(screens: [macbook, external],
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [macbook.uuid, external.uuid],
                                           showOnAllDisplays: false,
                                           selectedUUID: nil)

        XCTAssertEqual(plan.placements, [], "no selection means no notch window")
        XCTAssertEqual(plan.removals, [external.uuid, macbook.uuid],
                       "every existing window closes, sorted for determinism")
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    func testSingleDisplayModeWithUnknownSelectionRemovesEveryWindow() {
        let plan = NotchWindowPlanner.plan(screens: [macbook, external],
                                           windowSize: windowSize,
                                           existingWindowUUIDs: [macbook.uuid, external.uuid],
                                           showOnAllDisplays: false,
                                           selectedUUID: "screen-that-does-not-exist")

        XCTAssertEqual(plan.placements, [], "an unknown selection is as good as none")
        XCTAssertEqual(plan.removals, [external.uuid, macbook.uuid])
        assertPlacementsAndRemovalsDisjoint(plan)
    }

    // MARK: - Closed-notch height

    func testNotchedScreenKeepsClosedHeightOnEveryFlagCombination() {
        for hideOnClosed in [false, true] {
            for showOnAllDisplays in [false, true] {
                XCTAssertEqual(
                    NotchWindowPlanner.closedNotchHeight(closedHeight: closedHeight,
                                                         hideOnClosed: hideOnClosed,
                                                         hasNotch: true,
                                                         showOnAllDisplays: showOnAllDisplays),
                    closedHeight,
                    "hardware-notch screens never collapse: hideOnClosed=\(hideOnClosed), "
                        + "showOnAllDisplays=\(showOnAllDisplays)")
            }
        }
    }

    func testScreenWithoutNotchCollapsesOnlyWhenHidingAndNotShowingOnAllDisplays() {
        XCTAssertEqual(
            NotchWindowPlanner.closedNotchHeight(closedHeight: closedHeight,
                                                 hideOnClosed: true,
                                                 hasNotch: false,
                                                 showOnAllDisplays: false),
            0,
            "upstream fullscreen-hide rule still applies in single-display mode")
    }

    func testScreenWithoutNotchKeepsClosedHeightWhenShowingOnAllDisplays() {
        // Regression: the external monitor used to collapse to 0 while a fullscreen app
        // was running, so its fleet glance / media player could never render.
        XCTAssertEqual(
            NotchWindowPlanner.closedNotchHeight(closedHeight: closedHeight,
                                                 hideOnClosed: true,
                                                 hasNotch: false,
                                                 showOnAllDisplays: true),
            closedHeight,
            "multi-display mode must not drop the notch on screens without a hardware notch")
    }

    func testWhenNotHidingOnClosedEveryScreenKeepsClosedHeight() {
        for hasNotch in [false, true] {
            for showOnAllDisplays in [false, true] {
                XCTAssertEqual(
                    NotchWindowPlanner.closedNotchHeight(closedHeight: closedHeight,
                                                         hideOnClosed: false,
                                                         hasNotch: hasNotch,
                                                         showOnAllDisplays: showOnAllDisplays),
                    closedHeight,
                    "hasNotch=\(hasNotch), showOnAllDisplays=\(showOnAllDisplays)")
            }
        }
    }

    // MARK: - Show Fleet: resize before positioning

    /// The Show Fleet toggle changes `windowSize` (640x210 off, 836x320 on) without touching
    /// windows that already exist. The window must therefore be resized to `windowSize` and then
    /// centred from its real frame on every screen, or the notch drifts off centre.
    func testShowFleetToggleThenHeightChangeKeepsWindowCentredOnEveryScreen() {
        let fleetOff = CGSize(width: 640, height: 210)
        let fleetOn = CGSize(width: 836, height: 320)
        let screens = [macbook, external]

        // Windows exist at the Show-Fleet-off size on every screen.
        var frames: [String: CGRect] = [:]
        for screen in screens {
            frames[screen.uuid] = NotchWindowPlanner.frame(for: screen, windowSize: fleetOff)
        }

        // Show Fleet on: each window is resized to the new size ...
        for screen in screens {
            frames[screen.uuid] = NotchWindowPlanner.frame(for: screen, windowSize: fleetOn)
        }

        // ... and then, also when the notch height changes later, centred from its real frame.
        for _ in 0..<2 {
            for screen in screens {
                var frame = frames[screen.uuid]!
                frame.origin = NotchWindowPlanner.origin(for: screen, windowSize: frame.size)
                frames[screen.uuid] = frame
            }
        }

        for screen in screens {
            let frame = frames[screen.uuid]!
            XCTAssertEqual(frame.size, fleetOn, "\(screen.uuid): window must take the new notch size")
            XCTAssertEqual(frame.midX, screen.frame.midX, accuracy: 0.001,
                           "\(screen.uuid): notch must stay horizontally centred")
            XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 0.001,
                           "\(screen.uuid): notch must stay at the top edge")
        }
    }
}
