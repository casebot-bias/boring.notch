//
//  FleetClosedRowView.swift
//  boringNotch
//
//  The collapsed notch's fleet row: the working count, the camera gap and the speed reading.
//  A leaf view (no store, no defaults, no view model), so the render tests can draw it.
//

import SwiftUI

// MARK: - Closed Notch Row

/// The collapsed-notch fleet row: "N working" with its alert on the left, the hardware gap in the
/// middle and the speed reading on the right. Split out of `FleetClosedIndicator` (which owns the
/// store, the skin default and the view model) so the row itself can be rendered without them.
struct FleetClosedRowView: View {
    let working: Int
    let alert: String?
    /// The speed side, or nil when the feed never measured a speed and no job runs: the row then
    /// shows its count alone, never a placeholder.
    let reading: FleetFormat.FleetClosedRightReading?
    let theme: FleetTheme
    /// The hardware notch plus 5 pt clearance per side.
    let gapWidth: CGFloat
    let height: CGFloat

    var body: some View {
        // Both sides take the wider text's width so the camera gap sits on the physical notch's
        // centre; unequal sides would push the gap off-centre and the notch would cover text.
        FleetEqualSidesLayout {
            // Left block: "2 working", plus "· 1 down" / "· 3 critical" only when something is wrong.
            // All linked is the normal case and is not shown: the notch stays narrow (owner request).
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(working)")
                    .font(FleetType.mono(size: 12, weight: .medium))
                    .foregroundColor(theme.text)
                    + Text(" working")
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                if let alert {
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
                .frame(width: gapWidth, height: height)

            // Right block: the fleet's decode speed while the API reported one (the unit reads
            // "tok/s total"); while only cloud jobs run (the case's model reports no tok/s) the row
            // shows how many jobs run. No reading at all leaves the side empty.
            if let reading {
                HStack(alignment: .firstTextBaseline, spacing: FleetPanelMetrics.closedSpeedSpacing) {
                    Text(reading.number)
                        .font(FleetType.mono(size: FleetPanelMetrics.closedSpeedNumberSize, weight: .medium))
                        .foregroundColor(reading.dim ? theme.dim : theme.accent)
                        .lineLimit(1)
                    Text(reading.unit)
                        .font(FleetType.mono(size: FleetPanelMetrics.minTextSize))
                        .foregroundColor(theme.dim)
                }
                .fixedSize()
            } else {
                // Keeps the layout's three subviews, so an absent reading still lays the row out.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .frame(height: height)
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
