//
//  FleetClosedRowView.swift
//  boringNotch
//
//  The collapsed notch's fleet row: the working count, the camera gap and the speed reading.
//  A leaf view (no store, no defaults, no view model), so the render tests can draw it.
//

import SwiftUI

// MARK: - Closed Notch Row

/// The collapsed-notch fleet row: "N working" with its alert on the left (the case's running test or
/// build takes the count's place while nothing works), the hardware gap in the middle and the speed
/// reading on the right. Split out of `FleetClosedIndicator` (which owns the store, the skin default
/// and the view model) so the row itself can be rendered without them.
/// Both wings are as wide as the wider side's content plus the display's padding (6 pt beside a camera
/// cutout, 12 pt otherwise), so the row is only as wide as its text needs. The text hugs the middle
/// either way: the camera gap on a display with a hardware notch, and one padding wide without one,
/// stays on the row's centre, over the camera.
/// The bar draws at 70 % of the closed notch (`FleetPanelMetrics.closedBarHeight`), so every
/// label in it sits on the fleet's 11 pt floor (`FleetPanelMetrics.minTextSize`).
struct FleetClosedRowView: View {
    let working: Int
    let alert: String?
    /// The speed side, or nil when the feed never measured a speed and no job runs: the row then
    /// shows its count alone, never a placeholder.
    let reading: FleetFormat.FleetClosedRightReading?
    let theme: FleetTheme
    /// The hardware notch plus 5 pt clearance per side.
    let gapWidth: CGFloat
    /// The geometry this row draws in: a display with a hardware notch gives each wing only 6 pt of
    /// padding, so the bar hugs the camera and stays narrow.
    var hasHardwareNotch: Bool = false
    let height: CGFloat
    /// The case's running tests and builds. Read only while nothing works: the left side then names
    /// the run ("testing · 10m", "2 running") instead of "0 working".
    var toolRuns: [ToolRun] = []
    /// The speed trend behind the sparkline, 10 s apart, oldest first. nil draws no sparkline (the
    /// job-count reading has none); an empty trend still draws, flat at 0.
    var trend: [Double?]? = nil
    /// The black hole's place in this row, resolved by `FleetClosedIndicator` from the fleet's
    /// working count and the case's running tool runs. `.hidden` is a row with no hole.
    var blackHole: FleetBlackHoleState = .hidden

    var body: some View {
        // Both sides take the wider text's width plus the padding so the camera gap sits on the physical
        // notch's centre; unequal sides would push the gap off-centre and the notch would cover text.
        // The wing padding follows the display: 6 pt beside a camera cutout, 12 pt where the bar can
        // afford the air. The layout is told, so the equal-wings rule keeps the gap on the centre.
        let sidePadding = FleetPanelMetrics.closedRowWingPadding(hasHardwareNotch: hasHardwareNotch)
        FleetEqualSidesLayout(sidePadding: sidePadding) {
            // Left block: the black hole while the fleet works, "2 working" beside it, plus
            // "· 1 down" / "· 3 critical" only when something is wrong. All linked is the normal
            // case and is not shown: the notch stays narrow (owner request).
            HStack(spacing: FleetBlackHoleMetrics.gap) {
                // The hole leads the count while anything works (or the case waits on a test or a
                // build). The row reserves its 18 pt only while it shows and the fade carries the
                // width, so the text slides instead of jumping when the work starts or stops.
                if blackHole.isVisible {
                    FleetBlackHoleView(state: blackHole)
                        .transition(.opacity)
                }
                // The count and its suffix keep their shared baseline; the hole centres on the pair.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    workingLabel
                    if let alert {
                        Text("·")
                            .font(.system(size: FleetPanelMetrics.minTextSize))
                            .foregroundColor(theme.dim)
                        Text(alert)
                            .font(FleetType.mono(size: FleetPanelMetrics.minTextSize))
                            .foregroundColor(theme.hotText)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
            .fixedSize()

            // Hardware-notch gap spacer: notch width plus 5 pt clearance per side
            Rectangle()
                .fill(.clear)
                .frame(width: gapWidth, height: height)

            // Right block: the fleet's decode speed while the API reported one (the unit reads
            // "tok/s total"); while only cloud jobs run (the case's model reports no tok/s) the row
            // shows how many jobs run. No reading at all leaves the side empty.
            if let reading {
                // The sparkline sits left of the number, so the reading reads as the trend, then the value.
                HStack(alignment: .center, spacing: FleetPanelMetrics.closedSpeedSpacing) {
                    if let trend {
                        FleetClosedSparkline(values: FleetFormat.sparklineSeries(trend), theme: theme)
                            .frame(width: FleetPanelMetrics.closedSparklineWidth,
                                   height: FleetPanelMetrics.closedSparklineHeight)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: FleetPanelMetrics.closedSpeedSpacing) {
                        Text(reading.number)
                            .font(FleetType.mono(size: FleetPanelMetrics.closedSpeedNumberSize, weight: .medium))
                            .foregroundColor(reading.dim ? theme.dim : theme.accent)
                            .lineLimit(1)
                            // At least three digits wide, filled from the unit's side: the number grows into its own
                            // reserve instead of moving the sparkline, the wing and so the whole bar.
                            .frame(minWidth: FleetPanelMetrics.closedNumberMinWidth, alignment: .trailing)
                        Text(reading.unit)
                            .font(FleetType.mono(size: FleetPanelMetrics.minTextSize))
                            .foregroundColor(theme.dim)
                    }
                }
                .fixedSize()
            } else {
                // Keeps the layout's three subviews, so an absent reading still lays the row out.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .frame(height: height)
        // Anything that can move the row's width animates: the reading's three-digit reserve absorbs
        // "0" -> "147", but a longer number ("999" -> "1000"), a longer count or alert, the case's run
        // words or the black hole's slice still change the width. Watching one key over all of them
        // carries the change instead of snapping the bar.
        .animation(.easeInOut(duration: FleetPanelMetrics.closedRowWidthSeconds), value: widthKey)
    }

    /// The left block's lead: "2 working" while anything works, otherwise the case's running test or
    /// build ("testing · 10m", "2 running"). A run only ever replaces the count while `working` is 0,
    /// so a busy case keeps its count and the run never hides it.
    @ViewBuilder
    private var workingLabel: some View {
        if working == 0, let run = FleetFormat.closedToolRun(toolRuns) {
            if let number = run.number {
                Text(number)
                    .font(FleetType.mono(size: FleetPanelMetrics.minTextSize, weight: .medium))
                    .foregroundColor(theme.text)
                    + Text(" \(run.word)")
                    .font(.system(size: FleetPanelMetrics.minTextSize))
                    .foregroundColor(theme.text)
            } else {
                Text(run.word)
                    .font(.system(size: FleetPanelMetrics.minTextSize))
                    .foregroundColor(theme.text)
                if let age = run.age {
                    Text("·")
                        .font(.system(size: FleetPanelMetrics.minTextSize))
                        .foregroundColor(theme.dim)
                    Text(age)
                        .font(FleetType.mono(size: FleetPanelMetrics.minTextSize))
                        .foregroundColor(theme.dim)
                }
            }
        } else {
            Text("\(working)")
                .font(FleetType.mono(size: FleetPanelMetrics.minTextSize, weight: .medium))
                .foregroundColor(theme.text)
                + Text(" working")
                .font(.system(size: FleetPanelMetrics.minTextSize))
                .foregroundColor(theme.text)
        }
    }

    /// Everything the row's width depends on, in one comparable value: the count, the alert, the
    /// case's running tool run (its number, word and age), the reading and the black hole's slice.
    /// The width animation watches this, so no content change can move the bar without an animation.
    var widthKey: String {
        let run = FleetFormat.closedToolRun(toolRuns)
        return [String(working), alert ?? "", run?.number ?? "", run?.word ?? "", run?.age ?? "",
                reading?.number ?? "", reading?.unit ?? "", String(blackHole.isVisible)]
            .joined(separator: "|")
    }
}

// MARK: - Closed Sparkline

/// The collapsed row's speed sparkline: the recent fleet decode speed as a plain accent line, with
/// no axes and no labels - the number beside it carries the value. Flat at the bottom while nothing
/// writes, so the row never shows a gap where a reading used to be.
struct FleetClosedSparkline: View {
    let values: [Double]      // already normalised by FleetFormat.sparklineSeries
    let theme: FleetTheme

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let lineWidth: CGFloat = 1.5
            // Half the stroke's width stays clear of the top and bottom edges, so a peak or the flat
            // floor is drawn whole rather than cut off by the box.
            let inset = lineWidth / 2
            let top = inset
            let bottom = size.height - inset
            let span = high - low
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let fraction = span > 0 ? CGFloat((value - low) / span) : 0
                let point = CGPoint(x: step * CGFloat(index), y: bottom - fraction * (bottom - top))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(theme.accent),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Equal Sides Layout

/// Lays out [left, gap, right] with both wings as wide as the wider side's content plus the display's
/// padding (see `FleetPanelMetrics.closedRowSide`): the left text
/// hugs the gap from the left, the right text from the right, and the gap stays on the row's centre,
/// over the camera. The row's total width comes from `FleetPanelMetrics.closedRowWidth`.
struct FleetEqualSidesLayout: Layout {
    /// The wing padding on each side, chosen by the view from the display's hardware notch.
    let sidePadding: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: FleetPanelMetrics.closedRowWidth(left: sizes[0].width, right: sizes[2].width,
                                                              gap: sizes[1].width, padding: sidePadding),
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = FleetPanelMetrics.closedRowSide(left: sizes[0].width, right: sizes[2].width, padding: sidePadding)
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
