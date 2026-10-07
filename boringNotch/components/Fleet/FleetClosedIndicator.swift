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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var visible: Bool {
        return Defaults[.showFleet] && store.isReachable && vm.effectiveClosedNotchHeight > 0
    }

    var body: some View {
        if visible {
            HStack(spacing: 8) {
                // Dot row: one 5-pt dot per lane
                HStack(spacing: 4) {
                    ForEach(store.orbitModel.lanes) { lane in
                        Circle()
                            .fill(lane.state == .busy ? theme.accent : theme.off)
                            .frame(width: 5, height: 5)
                            .opacity(pulsing && lane.state == .busy ? 0.35 : 1)
                    }
                }
                .task(id: store.isBusy && !reduceMotion) {
                    guard store.isBusy, !reduceMotion else {
                        pulsing = false
                        return
                    }
                    pulsing = true
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(0.8 * 1_000_000_000))
                            if Task.isCancelled { return }
                            pulsing = !pulsing
                        } catch {
                            return
                        }
                    }
                }

                // Hardware-notch gap spacer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: vm.closedNotchSize.width + 10,
                        height: vm.effectiveClosedNotchHeight
                    )

                // Active count label
                Text("\(store.activeCount) active")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
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
