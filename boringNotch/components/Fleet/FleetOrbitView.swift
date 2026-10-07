//
//  FleetOrbitView.swift
//  boringNotch
//
//  150×150 orbit view: ring, spokes, core, satellite nodes, labels.
//

import SwiftUI

struct FleetOrbitView: View {
    let model: FleetOrbitModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var flow = false

    // MARK: - Computed Spoke Paths

    private var busySpokePath: Path {
        var path = Path()
        for (index, lane) in model.nodes.enumerated() where lane.state == .busy {
            path.move(to: FleetOrbitBuilder.orbitCenter)
            path.addLine(to: FleetOrbitBuilder.position(index: index, count: model.nodes.count))
        }
        return path
    }
    private var idleSpokePath: Path {
        var path = Path()
        for (index, lane) in model.nodes.enumerated() where lane.state != .busy {
            path.move(to: FleetOrbitBuilder.orbitCenter)
            path.addLine(to: FleetOrbitBuilder.position(index: index, count: model.nodes.count))
        }
        return path
    }


    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Ring
            Circle()
                .stroke(FleetPalette.line, lineWidth: 1)
                .frame(width: 116, height: 116)

            // 2. Spokes
            busySpokePath
                .stroke(
                    FleetPalette.sage,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [3, 4],
                        dashPhase: reduceMotion ? 0 : (flow ? -14 : 0)
                    )
                )
                .frame(width: 150, height: 150)

            idleSpokePath
                .stroke(FleetPalette.line, lineWidth: 1)
                .frame(width: 150, height: 150)

            // 3. Core glow
            Circle()
                .stroke(FleetPalette.sage.opacity(0.25), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(breathe && !reduceMotion ? 1.18 : 1)
                .opacity(breathe && !reduceMotion ? 0 : 1)

            // 4. Core
            Circle()
                .fill(FleetPalette.coreFill)
                .overlay(
                    Circle()
                        .stroke(FleetPalette.sage, lineWidth: 2)
                )
                .frame(width: 34, height: 34)

            // 5. Core label
            Text("case")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(FleetPalette.text)

            // 6. Satellites + Labels
            ForEach(Array(model.nodes.enumerated()), id: \.element.id) { index, lane in
                satellite(lane, index: index)
            }
        }
        .frame(width: 150, height: 150)
        .onAppear { startMotion() }
        .onChange(of: reduceMotion) { _, rm in
            if rm {
                breathe = false
                flow = false
            } else {
                startMotion()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Satellite Builder

    @ViewBuilder
    private func satellite(_ lane: FleetLane, index: Int) -> some View {
        let pos = FleetOrbitBuilder.position(index: index, count: model.nodes.count)
        let labelPos = FleetOrbitBuilder.labelPosition(index: index, count: model.nodes.count)
        let busy = lane.busy
        let offline = lane.state == .offline

        let fill: Color = busy ? FleetPalette.busyFill : (offline ? FleetPalette.offFill : FleetPalette.satFill)
        let stroke: Color = busy ? FleetPalette.sage : (offline ? FleetPalette.offStroke : FleetPalette.off)
        let d: CGFloat = busy ? 14 : 12

        ZStack {
            // Satellite circle
            ZStack {
                Circle()
                    .fill(fill)
                    .overlay(Circle().strokeBorder(stroke, lineWidth: 1.5))

                // Agent inner dashed ring
                if lane.kind == .agent {
                    Circle()
                        .strokeBorder(
                            stroke,
                            style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])
                        )
                }
            }
            .frame(width: d, height: d)
            .position(pos)

            // Label
            Text(lane.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(lane.state == .busy ? FleetPalette.sage : FleetPalette.muted)
                .fixedSize()
                .position(labelPos)
        }
    }

    // MARK: - Motion

    private func startMotion() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            flow = true
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let activeNodes = model.nodes.filter(\.busy).map(\.label)
        if activeNodes.isEmpty {
            return "Fleet orbit, no active nodes"
        }
        return "Fleet orbit, \(activeNodes.joined(separator: ", ")) active"
    }
}
