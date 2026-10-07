//
//  FleetButterflyView.swift
//  boringNotch
//
//  Butterfly rows for the opened fleet panel: the processor bar grows from the right
//  edge leftwards, the name sits centred, the memory bar grows from the left edge
//  rightwards, then the right-hand metric (tok/s in the accent colour, temperature
//  and labels in dim). Columns and gaps follow the approved
//  "B - Butterfly" design (mock: 1fr | 70 | 1fr | 50 with 8 pt gaps); both bars are
//  15 % shorter than the mock and the freed width goes to the name (70 -> 100) and
//  metric (50 -> 80) columns.
//

import SwiftUI
import Defaults

struct FleetButterflyView: View {
    let lanes: [FleetLane]

    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    // MARK: - Layout constants

    /// Derived from mock columns 1fr | 70 | 1fr | 50 with 8 pt gaps. Each bar is a
    /// further 15 % shorter than the butterfly layout (168.5 -> 143 pt at the real
    /// 541 pt row width) and the freed width joined the name (70 -> 100) and meta
    /// (80 -> 131) columns.
    private let rowHeight: CGFloat = 15
    private let rowGap: CGFloat = 7
    private let columnGap: CGFloat = 8
    private let nameWidth: CGFloat = 100
    private let metaWidth: CGFloat = 131
    private let barHeight: CGFloat = 7
    private let headRowHeight: CGFloat = 12

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            headRow
            ForEach(lanes) { lane in
                row(lane)
            }
        }
        .frame(
            height: headRowHeight + rowGap
                + CGFloat(lanes.count) * rowHeight
                + CGFloat(max(0, lanes.count - 1)) * rowGap,
            alignment: .top
        )
    }

    // MARK: - Head row

    private var headRow: some View {
        HStack(spacing: columnGap) {
            Text("◀ processor")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: nameWidth, height: 1)
            Text("memory ▶")
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: metaWidth, height: 1)
        }
        .font(.system(size: 10))
        .foregroundColor(theme.dim)
        .frame(height: headRowHeight)
    }

    // MARK: - Row

    private func row(_ lane: FleetLane) -> some View {
        HStack(spacing: columnGap) {
            bar(lane.cpu, fill: theme.accent, fromRight: true)
            Text(lane.label)
                .font(.system(size: 12))
                .foregroundColor(
                    lane.busy
                        ? theme.text
                        : (lane.state == .offline ? theme.nameOff : theme.nameText)
                )
                .lineLimit(1)
                .fixedSize()
                .frame(width: nameWidth)
            bar(
                lane.ram,
                fill: FleetFormat.isRAMWarning(lane.ram) ? theme.hot : theme.memory,
                fromRight: false
            )
            meta(lane.meta)
        }
        .frame(height: rowHeight)
    }

    // MARK: - Meta

    /// Right column: tok/s in the accent colour, the temperature and the labels dim,
    /// side by side with a middot between them, tabular figures, right aligned.
    private func meta(_ meta: FleetMeta) -> some View {
        let parts = FleetFormat.metaParts(meta)
        return HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("·")
                        .foregroundColor(theme.dim)
                }
                Text(part.text)
                    .foregroundColor(part.accent ? theme.accent : theme.dim)
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .frame(width: metaWidth, alignment: .trailing)
    }

    // MARK: - Bar helper

    private func bar(_ reading: Reading, fill: Color, fromRight: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: fromRight ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 3).fill(theme.barTrack)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: geo.size.width * CGFloat(FleetFormat.barFraction(reading)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }
}
