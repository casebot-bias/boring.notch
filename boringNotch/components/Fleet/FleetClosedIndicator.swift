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
                        Text("\(model.workingCount)")
                            .font(FleetType.mono(size: 12, weight: .medium))
                            .foregroundColor(theme.text)
                            + Text(" working")
                            .font(.system(size: 12))
                            .foregroundColor(theme.text)
                        if model.criticalCount == 0 {
                            Text(FleetFormat.linked(model.linkedCount, of: model.agentCount))
                                .font(FleetType.mono(size: 11))
                                .foregroundColor(theme.dim)
                                .lineLimit(1)
                        } else {
                            Text(FleetFormat.status(model.criticalCount))
                                .font(FleetType.mono(size: 11))
                                .foregroundColor(theme.hotText)
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

                // Right block: decode speed (live, idle or no reading), left-aligned away from the gap
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    let speed = model.speed
                    let idle = FleetFormat.speedIsIdle(speed)
                    let last = FleetFormat.speedLastValue(speed)
                    Text(FleetFormat.speedNumberText(speed))
                        .font(FleetType.mono(size: 20, weight: .medium))
                        .foregroundColor(idle ? theme.dim : theme.accent)
                        .lineLimit(1)
                    Text(idle && last != nil ? " idle" : " tok/s")
                        .font(FleetType.mono(size: 11))
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
