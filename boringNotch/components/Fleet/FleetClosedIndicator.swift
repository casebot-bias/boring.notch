//
//  FleetClosedIndicator.swift
//  boringNotch
//
//  Closed-notch fleet indicator row and header freshness label; the collapsed row itself is
//  drawn by `FleetClosedRowView`.
//

import Defaults
import SwiftUI

// MARK: - Closed Notch Indicator

struct FleetClosedIndicator: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }
    private var visible: Bool {
        return Defaults[.showFleet] && store.isReachable && vm.effectiveClosedNotchHeight > 0
    }

    var body: some View {
        if visible {
            // The closed row's fit rule measures the speed reading with the bundled mono face.
            // Register here so the width helper doesn't pin the fallback path (memoised, free after first call).
            let _ = FleetType.registerBundledFonts()
            let model = store.panelModel
            // The geometry this bar draws in: a display with a camera cutout keeps the gap the cutout
            // needs and gives each wing 6 pt of padding, so the closed bar hugs the camera there.
            // `safeAreaInsets.top` is the hardware cutout's own height and 0 where there is none.
            let hardwareNotchHeight = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }?
                .safeAreaInsets.top ?? 0
            let hasHardwareNotch = hardwareNotchHeight > 0
            // Both sides take the wider text's width so the camera gap sits on the physical notch's
            // centre; unequal sides would push the gap off-centre and the notch would cover text.
            FleetClosedRowView(
                working: model.workingCount,
                alert: FleetFormat.closedAlert(critical: model.criticalCount, down: model.downCount),
                reading: FleetFormat.closedRightReading(speed: model.speed,
                                                       jobs: model.runningTaskCount),
                theme: theme,
                // The middle of the closed row: a display with a hardware notch keeps the camera gap
                // (`notchWidth + 10`, the cutout plus 5 pt of clearance per side); a display without one has
                // no cutout to clear, so the middle is one padding wide and the bar fits its content.
                gapWidth: FleetPanelMetrics.closedRowGap(
                    notchWidth: vm.closedNotchSize.width,
                    hasHardwareNotch: hasHardwareNotch),
                hasHardwareNotch: hasHardwareNotch,
                // The bar's height follows the display: beside the camera cutout it is the hardware
                // notch's own height, whatever the notch height setting makes of the closed notch (a
                // custom height, a measured menu bar and the real notch size all leave the bar as tall
                // as the cutout, never shorter); a display without a cutout keeps the shorter 70 % bar
                // that clears the menu bar.
                height: FleetPanelMetrics.closedBarHeight(vm.effectiveClosedNotchHeight,
                                                          hardwareNotchHeight: hardwareNotchHeight),
                toolRuns: model.toolRuns,
                trend: model.speed?.trend,
                blackHole: FleetBlackHoleState.resolve(working: model.workingCount, toolRuns: model.toolRuns)
            )
        } else {
            // Original spacer — keeps layout identical when fleet is unreachable
            // The bare notch keeps the closed notch's own height; only the fleet bar is shortened.
            Rectangle()
                .fill(.clear)
                .frame(
                    width: vm.closedNotchSize.width - 20,
                    height: vm.effectiveClosedNotchHeight
                )
        }
    }
}


// MARK: - Updated Label

struct FleetUpdatedLabel: View {
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }
    @ViewBuilder
    var body: some View {
        if Defaults[.showFleet], store.isReachable, let lastUpdated = store.lastUpdated {
            let age = max(0, Int(Date().timeIntervalSince(lastUpdated)))
            Text("updated ")
                .font(.system(size: 11))
                .foregroundColor(theme.muted)
            + Text("\(age)")
                .font(FleetType.mono(size: 11, weight: .medium))
                .foregroundColor(theme.muted)
            + Text("s ago")
                .font(.system(size: 11))
                .foregroundColor(theme.muted)
        }
    }
}

// MARK: - Decision Pip

/// The notch's needs-decision pip: a small red dot at the trailing edge of the
/// collapsed notch while Odin waits on a decision. `ContentView.NotchLayout` owns
/// the placement, so every collapsed-notch mode shows it: the fleet glance, the
/// media live activity, the face animation and the inline HUD all replace the
/// glance but share that container. Pulses unless Reduce Motion is on.
struct FleetDecisionPip: View {
    @Default(.fleetSkin) private var fleetSkin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        Circle()
            .fill(theme.alert)
            .frame(width: 5, height: 5)
            // The alert dot breathes by size, never by opacity: dimming it would drop the pip under
            // the 3:1 dot floor. Reduce Motion parks it at its full size.
            .scaleEffect(reduceMotion ? 1 : (pulsing ? FleetPanelMetrics.alertPulseScale : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
