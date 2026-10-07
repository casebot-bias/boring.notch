//
//  FleetLanesView.swift
//  boringNotch
//
//  Column of lane rows (name dot + label, CPU+RAM bars, right metric).

import SwiftUI

struct FleetLanesView: View {
    let lanes: [FleetLane]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lanes) { lane in
                row(lane)
            }
        }
        .frame(
            height: CGFloat(lanes.count) * 16 + CGFloat(max(0, lanes.count - 1)) * 6,
            alignment: .top
        )
    }

    // MARK: - Row

    private func row(_ lane: FleetLane) -> some View {
        let busy = lane.busy
        let offline = lane.state == .offline

        return HStack(spacing: 10) {
            // 1. Name column
            HStack(spacing: 6) {
                Circle()
                    .fill(lane.state == .busy ? FleetPalette.sage : FleetPalette.off)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: lane.state == .busy ? FleetPalette.sage : .clear,
                        radius: 3
                    )
                Text(lane.label)
                    .font(.system(size: 12))
                    .foregroundColor(
                        busy ? FleetPalette.text : (offline ? FleetPalette.nameOff : FleetPalette.nameText)
                    )
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)

            // 2. Bar column
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(FleetPalette.barTrack)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            FleetFormat.isRAMWarning(lane.ram)
                                ? FleetPalette.hot.opacity(0.7)
                                : FleetPalette.olive.opacity(0.55)
                        )
                        .frame(
                            width: geo.size.width * CGFloat(FleetFormat.barFraction(lane.ram))
                        )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(FleetPalette.sage)
                        .frame(
                            width: geo.size.width * CGFloat(FleetFormat.barFraction(lane.cpu))
                        )
                }
            }
            .frame(height: 6)

            // 3. Right metric
            Text(lane.right)
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(busy ? FleetPalette.sage : FleetPalette.dim)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 16)
    }
}
