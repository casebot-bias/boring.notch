//
//  FleetResponseMapView.swift
//  boringNotch
//
//  The RESPONSE MAP column of the expanded Fleet panel: the agent signals
//  (frank, claire, ciri, morpheus | dali, nova, pika, odin) flank the centred
//  `case` box, thin wires drawn in a Canvas overlay tying every signal to the
//  box, plus its compact companion for the closed notch. Colours come only
//  from FleetTheme(skin); nothing draws a background (the notch is already
//  black). The animations are the busy-pulse of the mini signals and the dots
//  travelling along the busy wires, both honoured off under Reduce Motion.
//  A node with an open decision (an open Odin decision) draws `theme.alert` and outranks the
//  node's activity state. The response map keeps its name and says "Needs you" in `hot`; the grid
//  is one row per `responseMapMinRowHeight`.
//

import Defaults
import SwiftUI

// MARK: - Response Map

/// Expanded-panel response map: a label row over two columns of agent
/// signals (four left, the other four right) with the case box centred between them.
struct FleetResponseMapView: View {
    let lanes: [FleetLane]
    let origin: FleetLane

    @Default(.fleetSkin) private var fleetSkin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    /// True while any lane runs; only then does the dot clock need to tick.
    private var hasBusyLane: Bool { lanes.contains { $0.state == .busy } }

    /// Left column: the first four agents (frank, claire, ciri, morpheus). Right column: the
    private var leftIndexes: [Int] { Array(lanes.indices.prefix(4)) }
    private var rightIndexes: [Int] { Array(lanes.indices.dropFirst(4)) }
    /// The map's grid: as many rows as its longer agent column (four both sides with morpheus and pika).
    private var gridRows: Int { max(leftIndexes.count, rightIndexes.count) }

    // MARK: - Layout constants

    /// Mock geometry at our ≈0.65 scale: a 60 pt case box (wires stop at
    /// width/2 ± 30). Each column keeps a fixed `wireGap` clear of the box, so
    /// the wires always run forward into it.
    private let caseSize: CGFloat = 60
    private let signalSize: CGFloat = 6
    private let wireGap: CGFloat = 22

    /// Travelling-dot timing on busy wires: `t` runs 0 → 1 over
    /// `busyDotCycle` seconds and repeats, offset per row by
    /// `busyDotStagger` of a cycle; Reduce Motion parks the dot at
    /// `busyDotStaticPhase`.
    private let busyDotCycle: Double = 1.6
    private let busyDotStagger: Double = 0.18
    private let busyDotStaticPhase: CGFloat = 0.55
    private let dotRadius: CGFloat = 2.5

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelRow
                .padding(.bottom, 8)
            map
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Label row

    /// "RESPONSE MAP" leading, the working-agent count trailing; the count and
    /// word render even at zero.
    private var labelRow: some View {
        let working = lanes.filter { $0.state == .busy }.count
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("RESPONSE MAP")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundColor(theme.muted)
            Spacer(minLength: 0)
            (Text("\(working)")
                .font(FleetType.mono(size: 11))
                .foregroundColor(theme.dim)
             + Text(" WORKING")
                .font(FleetType.mono(size: 11))
                .tracking(0)
                .foregroundColor(theme.dim))
        }
    }

    // MARK: - Map

    /// Two agent columns and the case box in an HStack. Each column is sized
    /// from the fixed `wireGap` to the box, and also keeps
    /// `FleetPanelMetrics.responseMapColumnWidth` as a floor, so it can never
    /// overlap the box; the Canvas wire anchors sit on the columns' inner edges.
    private var map: some View {
        GeometryReader { geo in
            let rowHeight = geo.size.height / CGFloat(max(1, gridRows))
            // The column floor leaves room for the name and detail lines, so no status truncates
            // at 11 pt; a wider map still gets the freed space.
            let colWidth = max(FleetPanelMetrics.responseMapColumnWidth,
                               (geo.size.width - caseSize) / 2 - wireGap - 6)
            ZStack {
                if reduceMotion || !hasBusyLane {
                    Canvas { context, size in
                        drawWires(in: context, size: size, rowHeight: rowHeight, colWidth: colWidth, clock: nil)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        Canvas { context, size in
                            drawWires(
                                in: context,
                                size: size,
                                rowHeight: rowHeight,
                                colWidth: colWidth,
                                clock: timeline.date.timeIntervalSinceReferenceDate
                            )
                        }
                    }
                }
                HStack(spacing: 0) {
                    column(indexes: leftIndexes, colWidth: colWidth, rowHeight: rowHeight)
                        .frame(maxHeight: .infinity, alignment: .center)
                    Spacer(minLength: 0)
                    caseBox
                    Spacer(minLength: 0)
                    column(indexes: rightIndexes, colWidth: colWidth, rowHeight: rowHeight)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        // The grid is exactly one `responseMapMinRowHeight` per row: the columns and the Canvas
        // wires read `rowHeight` off this same geometry, so the anchors stay on the row centres,
        // and the panel's spare room stays below the map.
        .frame(height: FleetPanelMetrics.responseMapHeight(rows: gridRows), alignment: .top)
    }

    /// One cubic per agent: starts at its column's inner edge on the row
    /// centre, ends on the case box's edge fanned across ±12 pt (rows spread
    /// 24 pt apart, centred on the box). Horizontal tangents at the midpoint x
    /// keep each wire a single monotone curve running forward into the box.
    /// Idle wires stroke in
    /// `wire` at 1 pt, busy wires in `accent` at 1.25 pt. A 4 pt square marks
    /// the box end (`accent` while busy, `wire` otherwise); every busy wire
    /// also carries one 2.5 pt `accent` dot travelling along the same cubic,
    /// start → box, staggered per row. A nil `clock` draws the static frame
    /// (Reduce Motion parks busy dots at `busyDotStaticPhase`).
    private func drawWires(
        in context: GraphicsContext,
        size: CGSize,
        rowHeight: CGFloat,
        colWidth: CGFloat,
        clock: Double?
    ) {
        let columns: [(indexes: [Int], leading: Bool)] = [(leftIndexes, true), (rightIndexes, false)]
        let gridRows = max(columns[0].indexes.count, columns[1].indexes.count)
        for column in columns {
            let count = column.indexes.count
            // a short column is centred in the grid, so its first row starts half a row in
            let gridOffset = (CGFloat(gridRows) - CGFloat(count)) / 2
            // the fan spreads the column's wires across the box's ±12 pt; a lone wire runs straight
            let fanStep: CGFloat = count > 1 ? 24 / CGFloat(count - 1) : 0
            for (row, index) in column.indexes.enumerated() {
                guard let lane = lane(at: index) else { continue }
                let isLeft = column.leading
                let busy = lane.state == .busy
                let start = CGPoint(
                    x: isLeft ? colWidth : size.width - colWidth,
                    y: rowHeight * (gridOffset + CGFloat(row) + 0.5)
                )
                let end = CGPoint(
                    x: size.width / 2 + (isLeft ? -caseSize / 2 : caseSize / 2),
                    y: size.height / 2 + (CGFloat(row) - CGFloat(count - 1) / 2) * fanStep
                )
                let midX = start.x + (end.x - start.x) * 0.5
                let control1 = CGPoint(x: midX, y: start.y)
                let control2 = CGPoint(x: midX, y: end.y)

                var wire = Path()
                wire.move(to: start)
                wire.addCurve(to: end, control1: control1, control2: control2)
                context.stroke(wire, with: .color(busy ? theme.accent : theme.wire), lineWidth: busy ? 1.25 : 1)

                let marker = CGRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)
                let markerColor = busy ? theme.accent : theme.wire
                context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(markerColor))

                guard busy else { continue }
                let t = dotPhase(clock: clock, row: row)
                let mt = 1 - t
                let w0 = mt * mt * mt
                let w1 = 3 * mt * mt * t
                let w2 = 3 * mt * t * t
                let w3 = t * t * t
                let dot = CGPoint(
                    x: w0 * start.x + w1 * control1.x + w2 * control2.x + w3 * end.x,
                    y: w0 * start.y + w1 * control1.y + w2 * control2.y + w3 * end.y
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.x - dotRadius,
                        y: dot.y - dotRadius,
                        width: 2 * dotRadius,
                        height: 2 * dotRadius
                    )),
                    with: .color(theme.accent)
                )
            }
        }
    }

    /// Loop phase `t` in 0…1 for the dot on `row`: the clock drives it 0 → 1
    /// over `busyDotCycle` seconds with a per-row stagger so the four wires
    /// of a column do not move in lockstep; the static frame parks it at
    /// `busyDotStaticPhase`.
    private func dotPhase(clock: Double?, row: Int) -> CGFloat {
        guard let clock else { return busyDotStaticPhase }
        let cycles = clock / busyDotCycle + Double(row) * busyDotStagger
        return CGFloat(cycles.truncatingRemainder(dividingBy: 1))
    }

    // MARK: - Columns and rows

    /// One side of the map: stacked agent rows, each filling one grid row (the
    /// column's share of the height) so the Canvas row anchors line up.
    private func column(indexes: [Int], colWidth: CGFloat, rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(indexes, id: \.self) { index in
                if let lane = lane(at: index) {
                    agentRow(lane: lane)
                        .frame(width: colWidth, height: rowHeight, alignment: .leading)
                }
            }
        }
        .frame(width: colWidth)
    }

    /// Signal square, name over the state line, job badge at the column's far right. Busy and
    /// open-decision names are L1 (`text`, semibold); idle and offline names are L2 (`muted`, and
    /// `nameOff` for offline, medium). An offline signal is a hollow square; an open-decision lane draws its signal
    /// in `theme.alert`, keeps its own name, says "Needs you" in `hotText` and drops the badge.
    @ViewBuilder
    private func agentRow(lane: FleetLane) -> some View {
        let needsYou = lane.hasOpenDecision
        let live = needsYou || lane.state == .busy
        let nameColor: Color = live ? theme.text : (lane.state == .offline ? theme.nameOff : theme.muted)
        HStack(spacing: 5) {
            Group {
                if lane.state == .offline && !needsYou {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(theme.off, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(needsYou ? theme.alert : signalColor(lane.state))
                }
            }
            .frame(width: signalSize, height: signalSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(lane.label)
                    .font(.system(size: 12, weight: live ? .semibold : .medium))
                    .foregroundColor(nameColor)
                    .lineLimit(1)
                    // A long name plus a job badge can run short of the column; the longest agent
                    // name ("morpheus") shrinks a little rather than reading as "morph…".
                    .minimumScaleFactor(0.75)
                Text(FleetFormat.responseDetail(lane))
                    .font(!needsYou && FleetFormat.speedDetail(lane) != nil
                          ? FleetType.mono(size: 11, weight: .medium)
                          : FleetType.mono(size: 11))
                    .foregroundColor(needsYou ? theme.hotText : theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !needsYou, let badge = FleetFormat.jobBadge(lane.jobs.count) {
                Text(badge)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Case box

    /// The centred origin node: name over Online/Offline inside a 1 px square.
    private var caseBox: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(theme.line, lineWidth: 1)
            .frame(width: caseSize, height: caseSize)
            .overlay {
                VStack(spacing: 2) {
                    Text(origin.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.text)
                    Text(origin.state == .offline ? "Offline" : "Online")
                        .font(FleetType.mono(size: 11))
                        .foregroundColor(theme.dim)
                }
            }
    }

    // MARK: - Palette helpers

    private func signalColor(_ state: FleetNodeState) -> Color {
        switch state {
        case .busy: return theme.accent
        case .idle: return theme.off
        case .offline: return theme.off
        }
    }

    private func lane(at index: Int) -> FleetLane? {
        guard index >= 0, index < lanes.count else { return nil }
        return lanes[index]
    }
}
