//
//  FleetLanesView.swift
//  boringNotch
//
//  Column of lane rows (name dot + label, CPU+RAM bars, right metric).

import SwiftUI
import Defaults

struct FleetLanesView: View {
    let lanes: [FleetLane]

    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

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
                    .fill(lane.state == .busy ? theme.accent : theme.off)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: lane.state == .busy ? theme.accent : .clear,
                        radius: 3
                    )
                Text(lane.label)
                    .font(.system(size: 12))
                    .foregroundColor(
                        busy ? theme.text : (offline ? theme.nameOff : theme.nameText)
                    )
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)

            // 2. Bar column
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.barTrack)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            FleetFormat.isRAMWarning(lane.ram)
                                ? theme.hot.opacity(0.7)
                                : theme.ram.opacity(0.55)
                        )
                        .frame(
                            width: geo.size.width * CGFloat(FleetFormat.barFraction(lane.ram))
                        )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.accent)
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
                .foregroundColor(busy ? theme.accent : theme.dim)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 16)
    }
}
