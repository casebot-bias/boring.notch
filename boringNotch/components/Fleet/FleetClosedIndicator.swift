//
//  FleetClosedIndicator.swift
//  boringNotch
//
//  Closed-notch fleet indicator row and header freshness label.
//

import Defaults
import SwiftUI

// MARK: - Closed Notch Indicator

struct FleetClosedIndicator: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }
    // Both sides share one fixed width so the camera gap sits on the physical notch's
    // centre; unequal sides would push the gap off-centre and the notch would cover text.
    // Wide enough for the mini map, its gap and the full "3 critical" / "1 working" strings, so
    // neither side block truncates at 11 pt.
    private var sideWidth: CGFloat { FleetPanelMetrics.closedRowSideWidth }

    private var visible: Bool {
        return Defaults[.showFleet] && store.isReachable && vm.effectiveClosedNotchHeight > 0
    }

    var body: some View {
        if visible {
            let model = store.panelModel
            HStack(spacing: 0) {
                // Left block: mini map and working / status text, right-aligned toward the gap
                HStack(spacing: 10) {
                    // Compact six-signal map of the agents
                    FleetMiniSignalMap(lanes: model.agents, origin: model.origin)

                    // Working count over link / critical status
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.workingCount) working")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundColor(theme.text)
                        if model.criticalCount == 0 {
                            Text(FleetFormat.linked(model.linkedCount, of: model.agentCount))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.dim)
                                .lineLimit(1)
                        } else {
                            Text(FleetFormat.status(model.criticalCount))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.hot)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: sideWidth, alignment: .trailing)

                // Hardware-notch gap spacer: notch width plus 5 pt clearance per side
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: vm.closedNotchSize.width + 10,
                        height: vm.effectiveClosedNotchHeight
                    )

                // Right block: total output, left-aligned away from the gap
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    let total = FleetFormat.fleetOutput(model.totalTokPerSec)
                    Text(total)
                        .font(.system(size: 20, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(model.totalTokPerSec == nil ? theme.dim : theme.accent)
                        .lineLimit(1)
                    Text("tok/s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.dim)
                }
                .frame(width: sideWidth, alignment: .leading)
            }
            .frame(height: vm.effectiveClosedNotchHeight)
        } else {
            // Original spacer — keeps layout identical when fleet is unreachable
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
            Text("updated \(age)s ago")
                .font(.system(size: 11))
                .foregroundColor(theme.muted)
                .monospacedDigit()
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
