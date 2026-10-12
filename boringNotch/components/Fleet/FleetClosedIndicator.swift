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
            // Both sides take the wider text's width so the camera gap sits on the physical notch's
            // centre; unequal sides would push the gap off-centre and the notch would cover text.
            FleetEqualSidesLayout {
                // Left block: "2 working", plus "· 1 down" / "· 3 critical" only when something is wrong.
                // All linked is the normal case and is not shown: the notch stays narrow (owner request).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(model.workingCount)")
                        .font(FleetType.mono(size: 12, weight: .medium))
                        .foregroundColor(theme.text)
                        + Text(" working")
                        .font(.system(size: 12))
                        .foregroundColor(theme.text)
                    if let alert = FleetFormat.closedAlert(critical: model.criticalCount,
                                                           linked: model.linkedCount, of: model.agentCount) {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundColor(theme.dim)
                        Text(alert)
                            .font(FleetType.mono(size: 11))
                            .foregroundColor(theme.hotText)
                    }
                }
                .lineLimit(1)
                .fixedSize()

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
                .fixedSize()
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

// MARK: - Equal Sides Layout

/// Lays out [left, gap, right] with both sides as wide as the wider of the two (see
/// `FleetPanelMetrics.closedRowSide`): the left text hugs the gap from the left, the right text from
/// the right, and the gap stays on the row's centre, over the camera.
struct FleetEqualSidesLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = FleetPanelMetrics.closedRowSide(left: sizes[0].width, right: sizes[2].width)
        return CGSize(width: side * 2 + sizes[1].width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = FleetPanelMetrics.closedRowSide(left: sizes[0].width, right: sizes[2].width)
        let leftWidth = min(sizes[0].width, side)
        let rightWidth = min(sizes[2].width, side)
        subviews[0].place(at: CGPoint(x: bounds.minX + side - leftWidth, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: leftWidth, height: sizes[0].height))
        subviews[1].place(at: CGPoint(x: bounds.minX + side, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: sizes[1].width, height: sizes[1].height))
        subviews[2].place(at: CGPoint(x: bounds.minX + side + sizes[1].width, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: rightWidth, height: sizes[2].height))
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
