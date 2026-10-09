import CoreGraphics
import Foundation

/// One display, as the window planning needs it.
struct NotchScreen: Equatable {
    var uuid: String
    var frame: CGRect
    /// Hardware notch present on this display (`NSScreen.safeAreaInsets.top > 0`).
    var hasNotch: Bool
}

/// A window to create or move: the top-centre of that screen's frame.
struct NotchWindowPlacement: Equatable {
    var uuid: String
    var origin: CGPoint
}

struct NotchWindowPlan: Equatable {
    /// One entry per screen that should show a notch window, in screens order.
    var placements: [NotchWindowPlacement]
    /// UUIDs whose screen is gone (or no longer selected); close those windows.
    var removals: [String]
}

/// Pure screen -> notch-window mapping. No AppKit, no I/O, no globals, so it is unit-testable.
///
/// Screen -> window mapping: with `showOnAllDisplays` every screen gets its own window; otherwise
/// only the screen matching `selectedUUID` does. Windows for screens that disappeared, or that are
/// no longer selected, are reported as removals.
///
/// Closed-notch height rule: upstream hides the synthetic notch on a display without a hardware
/// notch while a fullscreen app is running (`hideOnClosed`). In multi-display mode that rule is
/// dropped, because every screen must keep its notch: the fleet glance and media player have to be
/// reachable on every display, including external monitors that have no hardware notch.
enum NotchWindowPlanner {
    /// Top-centre origin for a window of `windowSize` on `screen`:
    /// x = frame.origin.x + frame.width/2 - windowSize.width/2,
    /// y = frame.origin.y + frame.height - windowSize.height.
    ///
    /// Works for any frame origin, including negative ones (a monitor left of or below the main
    /// display in global screen coordinates).
    static func origin(for screen: NotchScreen, windowSize: CGSize) -> CGPoint {
        CGPoint(
            x: screen.frame.origin.x + screen.frame.width / 2 - windowSize.width / 2,
            y: screen.frame.origin.y + screen.frame.height - windowSize.height
        )
    }
    /// Frame a notch window must take on `screen`: the screen's top-centre rect of the current
    /// logical notch size. Callers apply this frame so the window is resized and moved in one
    /// step; a changed `windowSize` (Show Fleet on/off) can then never leave a window at its old
    /// size while the origin is computed from the new one - the drift that pushed the notch off
    /// centre.
    static func frame(for screen: NotchScreen, windowSize: CGSize) -> CGRect {
        CGRect(origin: origin(for: screen, windowSize: windowSize), size: windowSize)
    }

    /// Screen list -> windows mapping.
    /// - `showOnAllDisplays == true`: every screen in the list gets a placement, in order.
    /// - `showOnAllDisplays == false`: only the screen whose uuid == `selectedUUID` (no placement when
    ///   `selectedUUID` is nil or unknown).
    /// - `removals`: existing UUIDs that are not in `screens`, plus - when not showing on all
    ///   displays - existing UUIDs other than the selected one. Never contains a uuid that also
    ///   gets a placement. Sorted for determinism.
    static func plan(screens: [NotchScreen],
                     windowSize: CGSize,
                     existingWindowUUIDs: Set<String>,
                     showOnAllDisplays: Bool,
                     selectedUUID: String?) -> NotchWindowPlan {
        let targetScreens: [NotchScreen]
        if showOnAllDisplays {
            targetScreens = screens
        } else if let selectedUUID, let selected = screens.first(where: { $0.uuid == selectedUUID }) {
            targetScreens = [selected]
        } else {
            targetScreens = []
        }

        let placements = targetScreens.map {
            NotchWindowPlacement(uuid: $0.uuid, origin: origin(for: $0, windowSize: windowSize))
        }
        let placedUUIDs = Set(placements.map(\.uuid))

        let screenUUIDs = Set(screens.map(\.uuid))
        let removals = existingWindowUUIDs
            .filter { uuid in
                if !screenUUIDs.contains(uuid) { return true }
                if showOnAllDisplays { return false }
                return uuid != selectedUUID
            }
            .filter { !placedUUIDs.contains($0) }
            .sorted()

        return NotchWindowPlan(placements: placements, removals: removals)
    }

    /// Height of the closed notch on a screen. Upstream hides the synthetic notch on a display
    /// without a hardware notch while a fullscreen app is running (`hideOnClosed`); in
    /// multi-display mode every screen must keep its notch, so that rule is dropped when the user
    /// asked for all displays:
    /// `(hideOnClosed && !hasNotch && !showOnAllDisplays) ? 0 : closedHeight`
    static func closedNotchHeight(closedHeight: CGFloat, hideOnClosed: Bool, hasNotch: Bool,
                                  showOnAllDisplays: Bool) -> CGFloat {
        (hideOnClosed && !hasNotch && !showOnAllDisplays) ? 0 : closedHeight
    }
}
