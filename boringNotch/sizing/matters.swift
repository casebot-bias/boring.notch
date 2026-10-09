//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let fleetSectionWidth: CGFloat = 560
let fleetMusicWidth: CGFloat = 220
/// Hard cap for the cover in the compact column, whatever the art size or shape.
/// 150 pt keeps the cover, the track block, the progress bar and the control
/// toolbar inside the opened notch's 300 pt height.
let fleetCoverMaxSide: CGFloat = 150
let fleetSectionSpacing: CGFloat = 15
let fleetSectionHeight: CGFloat = 300
private let baseOpenNotchSize: CGSize = .init(width: 640, height: 190)

var openNotchSize: CGSize {
    guard Defaults[.showFleet] else { return baseOpenNotchSize }
    return .init(
        width: fleetMusicWidth + 40 + fleetSectionSpacing + 1 + fleetSectionWidth,
        height: max(baseOpenNotchSize.height, fleetSectionHeight)
    )
}

var windowSize: CGSize {
    .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                // A display with no menu bar of its own measures 0, which would collapse the notch
                // to zero height; keep the configured height in that case.
                notchHeight = NotchWindowPlanner.measuredOrConfiguredClosedHeight(
                    measuredMenuBar: screen.frame.maxY - screen.visibleFrame.maxY,
                    configured: Defaults[.notchHeight])
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                // The reported case: a secondary monitor with no menu bar of its own measures 0,
                // which would leave the notch zero height - i.e. invisible - on that screen.
                notchHeight = NotchWindowPlanner.measuredOrConfiguredClosedHeight(
                    measuredMenuBar: screen.frame.maxY - screen.visibleFrame.maxY,
                    configured: Defaults[.nonNotchHeight])
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
