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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var visible: Bool {
        return Defaults[.showFleet] && store.isReachable && vm.effectiveClosedNotchHeight > 0
    }

    var body: some View {
        if visible {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255), radius: 4)
                    .opacity(pulsing ? 0.35 : 1.0)
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
                    .foregroundColor(Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255))
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

    @ViewBuilder
    var body: some View {
        if Defaults[.showFleet], store.isReachable, let lastUpdated = store.lastUpdated {
            let age = max(0, Int(Date().timeIntervalSince(lastUpdated)))
            Text("updated \(age)s ago")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255))
                .monospacedDigit()
        }
    }
}
