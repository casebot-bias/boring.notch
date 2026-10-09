//
//  NotchWindowPlannerTests.swift
//  boringNotchTests
//
//  Pure screen -> notch-window planning: two-screen (MacBook + external) placement and
//  window removals.
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

    // MARK: - Helpers

    /// Expected top-centre origin, computed independently of the planner formula.
    private func expectedOrigin(for screen: NotchScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX - windowSize.width / 2,
                y: screen.frame.maxY - windowSize.height)
    }

    /// Expected placement for a screen: this file's own top-centre origin, the window size and
    /// the fact that every placed screen must show its notch.
    private func expectedPlacement(for screen: NotchScreen) -> NotchWindowPlacement {
        NotchWindowPlacement(uuid: screen.uuid,
                             frame: CGRect(origin: expectedOrigin(for: screen), size: windowSize),
                             visible: true)
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
            expectedPlacement(for: macbook),
            expectedPlacement(for: external),
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
        XCTAssertEqual(plan.placements.map(\.frame.origin),
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
            expectedPlacement(for: macbook),
            expectedPlacement(for: external),
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
            expectedPlacement(for: macbook)
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
            expectedPlacement(for: external)
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

    // MARK: - Two screens: one visible window per screen

    /// The owner's setup: a notched MacBook as main display plus a 5K monitor placed above and to
    /// the left, so its frame origin is negative. Both screens must get a window with the right
    /// frame, and both must be visible - a plan that only moves windows cannot say that.
    func testExternalScreenAboveAndLeftGetsAVisibleWindowWithTheRightFrame() {
        let main = NotchScreen(uuid: "main-notched",
                               frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                               hasNotch: true)
        let external5K = NotchScreen(uuid: "external-5k",
                                     frame: CGRect(x: -2560, y: 982, width: 2560, height: 1440),
                                     hasNotch: false)
        let size = CGSize(width: 836, height: 320)

        let plan = NotchWindowPlanner.plan(screens: [main, external5K],
                                           windowSize: size,
                                           existingWindowUUIDs: [],
                                           showOnAllDisplays: true,
                                           selectedUUID: nil)

        XCTAssertEqual(plan.placements.count, 2, "one window per screen")
        for placement in plan.placements {
            XCTAssertTrue(placement.visible, "\(placement.uuid) must be visible")
            XCTAssertEqual(placement.frame.size, size)
            XCTAssertEqual(placement.frame.midX,
                           placement.uuid == main.uuid ? main.frame.midX : external5K.frame.midX,
                           accuracy: 0.001)
            XCTAssertEqual(placement.frame.maxY,
                           placement.uuid == main.uuid ? main.frame.maxY : external5K.frame.maxY,
                           accuracy: 0.001)
        }
        XCTAssertEqual(plan.placements[0].frame,
                       CGRect(x: main.frame.midX - size.width / 2,
                              y: main.frame.maxY - size.height,
                              width: size.width, height: size.height))
        XCTAssertEqual(plan.placements[1].frame,
                       CGRect(x: external5K.frame.midX - size.width / 2,
                              y: external5K.frame.maxY - size.height,
                              width: size.width, height: size.height))
        XCTAssertEqual(plan.removals, [], "both screens keep their window")
    }

    // MARK: - A menu bar that measures 0

    /// A secondary display with no menu bar of its own measures
    /// `frame.maxY - visibleFrame.maxY == 0`. Used directly as the closed-notch height that 0 made
    /// the notch zero height, so the display drew nothing - the "notch only shows on the primary
    /// screen" report. The configured height must win over a 0 measurement.
    func testZeroMenuBarMeasurementFallsBackToTheConfiguredHeight() {
        XCTAssertEqual(
            NotchWindowPlanner.measuredOrConfiguredClosedHeight(measuredMenuBar: 0, configured: 32),
            32, "no menu bar on that display: keep the configured height")
        XCTAssertEqual(
            NotchWindowPlanner.measuredOrConfiguredClosedHeight(measuredMenuBar: 30, configured: 32),
            30, "a real menu bar still wins")
        XCTAssertEqual(
            NotchWindowPlanner.measuredOrConfiguredClosedHeight(measuredMenuBar: 0, configured: 0),
            0, "an explicitly configured 0 stays 0")
    }

    // MARK: - Window sync (create, move, show, close)

    private final class FakeWindow: NotchWindowHandle {
        var frame: CGRect
        private(set) var isOnScreen: Bool
        private(set) var moves: [CGRect] = []
        private(set) var shownFrontCount = 0
        private(set) var isClosed = false

        init(frame: CGRect = .zero, isOnScreen: Bool = false) {
            self.frame = frame
            self.isOnScreen = isOnScreen
        }

        func move(to frame: CGRect) {
            moves.append(frame)
            self.frame = frame
        }

        func showFront() {
            shownFrontCount += 1
            isOnScreen = true
        }

        func closeNotchWindow() {
            isClosed = true
            isOnScreen = false
        }
    }

    private func plan(_ screens: [NotchScreen], existing: Set<String> = []) -> NotchWindowPlan {
        NotchWindowPlanner.plan(screens: screens,
                                windowSize: windowSize,
                                existingWindowUUIDs: existing,
                                showOnAllDisplays: true,
                                selectedUUID: nil)
    }

    /// One screen per window: each placement gets its own window, moved to the planned frame and
    /// ordered to the front. Removing creation or ordering here fails the test.
    func testSyncCreatesOneVisibleWindowPerScreenWithThePlannedFrame() {
        var windows: [String: FakeWindow] = [:]
        let expected = plan([macbook, external])

        NotchWindowSync.sync(plan: expected, windows: &windows) { _ in FakeWindow() }

        XCTAssertEqual(windows.count, 2, "one window per screen")
        XCTAssertEqual(Set(windows.keys), Set(expected.placements.map(\.uuid)))
        for placement in expected.placements {
            guard let window = windows[placement.uuid] else {
                return XCTFail("no window for \(placement.uuid)")
            }
            XCTAssertEqual(window.frame, placement.frame, "\(placement.uuid) must take its planned frame")
            XCTAssertTrue(window.isOnScreen, "\(placement.uuid) must be on screen")
            XCTAssertEqual(window.shownFrontCount, 1, "\(placement.uuid) must be ordered front once")
        }
    }

    /// An existing window is moved, not recreated; a screen that vanished is closed and dropped.
    func testSyncMovesExistingWindowsAndClosesRemovedOnes() {
        let stale = FakeWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        var windows: [String: FakeWindow] = [external.uuid: stale]
        var created = 0

        NotchWindowSync.sync(plan: plan([macbook, external]), windows: &windows) { _ in
            created += 1
            return FakeWindow()
        }

        XCTAssertEqual(created, 1, "only the missing screen's window is created")
        XCTAssertEqual(windows[external.uuid]?.moves.count, 1, "the stale window is moved")
        XCTAssertEqual(windows[external.uuid]?.frame, expectedPlacement(for: external).frame)

        NotchWindowSync.sync(plan: plan([macbook], existing: [macbook.uuid, external.uuid]),
                             windows: &windows) { _ in FakeWindow() }
        XCTAssertTrue(stale.isClosed, "the vanished screen's window is closed")
        XCTAssertNil(windows[external.uuid])
    }

    /// Re-running the sync on an unchanged plan does nothing: no move, no extra ordering to the front.
    func testSyncIsIdempotentForAnUnchangedPlan() {
        var windows: [String: FakeWindow] = [:]
        let expected = plan([macbook, external])
        NotchWindowSync.sync(plan: expected, windows: &windows) { _ in FakeWindow() }
        let movesAfterFirst = windows.mapValues { $0.moves.count }
        let frontsAfterFirst = windows.mapValues { $0.shownFrontCount }

        NotchWindowSync.sync(plan: expected, windows: &windows) { _ in
            XCTFail("no window may be created on the second pass")
            return FakeWindow()
        }

        XCTAssertEqual(windows.mapValues { $0.moves.count }, movesAfterFirst)
        XCTAssertEqual(windows.mapValues { $0.shownFrontCount }, frontsAfterFirst)
    }
}
