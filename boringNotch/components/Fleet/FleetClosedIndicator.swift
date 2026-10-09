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

    private var visible: Bool {
        return Defaults[.showFleet] && store.isReachable && vm.effectiveClosedNotchHeight > 0
    }

    var body: some View {
        if visible {
            let model = store.panelModel
            HStack(spacing: 10) {
                // Compact six-signal map of the agents
                FleetMiniSignalMap(lanes: model.agents, origin: model.origin)

                // Working count over link / critical status
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.workingCount) working")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(theme.text)
                    if model.criticalCount == 0 {
                        Text(FleetFormat.linked(model.linkedCount, of: model.agentCount))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(theme.dim)
                    } else {
                        Text(FleetFormat.status(model.criticalCount))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(theme.hot)
                    }
                }

                // Hardware-notch gap spacer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: vm.closedNotchSize.width + 10,
                        height: vm.effectiveClosedNotchHeight
                    )

                // Total output on the right of the camera gap
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    let total = FleetFormat.fleetOutput(model.totalTokPerSec)
                    Text(total)
                        .font(.system(size: 20, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(model.totalTokPerSec == nil ? theme.dim : theme.accent)
                    Text("tok/s")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(theme.dim)
                }
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
