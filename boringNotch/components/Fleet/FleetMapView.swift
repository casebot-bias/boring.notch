//
//  FleetMapView.swift
//  boringNotch
//
//  Fixed 440 x 110 fleet topology canvas ported from the SVG in notch-design.html:
//  origin `case` at (220,55) r16 joined by cubic curves to frank/dali/nova/MacBook.
//  Busy nodes pulse a sage ring and their link runs as an animated dashed flow.
//

import SwiftUI

// MARK: - Static layout

/// Canvas geometry for one node; every lookup is keyed by `FleetMapNode.id`, never by position.
private struct FleetNodeGeometry {
    var center: CGPoint
    var radius: CGFloat
    /// Label: box of `labelWidth` centered on `labelCenter`, text aligned to `labelAlignment`.
    /// The values reproduce the design's `<text x=… text-anchor=…>` placement.
    var labelCenter: CGPoint
    var labelWidth: CGFloat
    var labelAlignment: Alignment
    /// Cubic control points of the `case → node` link in final-absolute form
    /// (`C c1x c1y, c2x c2y, x y`); nil draws a straight segment.
    var curveControls: [CGPoint]?
}

private enum FleetMapLayout {
    static let canvas = CGSize(width: 440, height: 110)

    static let origin = FleetNodeGeometry(
        center: CGPoint(x: 220, y: 55), radius: 16,
        labelCenter: CGPoint(x: 220, y: 84), labelWidth: 120, labelAlignment: .center,
        curveControls: nil
    )

    // Curves are the design's `d` attributes verbatim:
    //   frank   "M220 55 C170 55 150 30 100 30",   label <text x="75"  y="33" text-anchor="end">
    //   dali    "M220 55 C270 55 290 30 340 30",    label <text x="358" y="33">
    //   nova    "M220 55 C170 55 150 88 110 88",    label <text x="85"  y="91" text-anchor="end">
    //   macbook "M220 55 C270 55 290 88 330 88",    label <text x="348" y="91">
    // `position` centers views, so an end/start anchor becomes an aligned box whose edge sits
    // on the design's text x; label centers below encode that (edge = labelCenter.x ∓ width/2).
    static let nodes: [String: FleetNodeGeometry] = [
        "frank": FleetNodeGeometry(
            center: CGPoint(x: 100, y: 30), radius: 11,
            labelCenter: CGPoint(x: 40, y: 30), labelWidth: 70, labelAlignment: .trailing,
            curveControls: [CGPoint(x: 170, y: 55), CGPoint(x: 150, y: 30)]
        ),
        "dali": FleetNodeGeometry(
            center: CGPoint(x: 340, y: 30), radius: 11,
            labelCenter: CGPoint(x: 383, y: 30), labelWidth: 50, labelAlignment: .leading,
            curveControls: [CGPoint(x: 270, y: 55), CGPoint(x: 290, y: 30)]
        ),
        "nova": FleetNodeGeometry(
            center: CGPoint(x: 110, y: 88), radius: 11,
            labelCenter: CGPoint(x: 45, y: 88), labelWidth: 80, labelAlignment: .trailing,
            curveControls: [CGPoint(x: 170, y: 55), CGPoint(x: 150, y: 88)]
        ),
        "macbook": FleetNodeGeometry(
            center: CGPoint(x: 330, y: 88), radius: 11,
            labelCenter: CGPoint(x: 383, y: 88), labelWidth: 70, labelAlignment: .leading,
            curveControls: [CGPoint(x: 270, y: 55), CGPoint(x: 290, y: 88)]
        ),
    ]
}

private enum FleetMapColors {
    static let sage = Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255)
    static let foreground = Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
    static let busyFill = Color(red: 0x1D / 255, green: 0x24 / 255, blue: 0x18 / 255)
    static let idleFill = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    static let idleStroke = Color(red: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255)
    static let lineGrey = Color(red: 0x44 / 255, green: 0x44 / 255, blue: 0x44 / 255)
}

// MARK: - View

struct FleetMapView: View {
    let model: FleetMapModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the ring pulse — the design's `r` keyframes (2 s ease-in-out cycle:
    /// stroke-opacity 1→0.2 while r grows r→r+4, back autoreversing).
    @State private var pulse = false
    /// Drives the dash phase on busy links — the design's `f` keyframes
    /// (1 s linear loop: stroke-dashoffset 0→-10, one full 4+6 dash period).
    @State private var flow = false

    var body: some View {
        ZStack {
            ForEach(model.nodes) { node in
                if let geometry = FleetMapLayout.nodes[node.id] {
                    connection(for: node, to: geometry)
                    nodeCircle(node, geometry: geometry)
                    nodeLabel(node.label, geometry: geometry)
                }
            }
            // The origin always renders, styled by its own state; its "links" are the
            // case→node curves drawn for each node above.
            nodeCircle(model.origin, geometry: FleetMapLayout.origin)
            nodeLabel(model.origin.label, geometry: FleetMapLayout.origin)
        }
        .frame(width: FleetMapLayout.canvas.width, height: FleetMapLayout.canvas.height)
        .onAppear { startMotion() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Motion

    private func startMotion() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            flow = true
        }
    }

    // MARK: Connections

    /// Working links are a sage dash flow (1.5 pt, dash 4/6, moving phase); idle/offline links
    /// are a solid 1 pt grey line. Under reduce motion busy links keep the static dash pattern.
    private func connection(for node: FleetMapNode, to geometry: FleetNodeGeometry) -> some View {
        let active = node.state == .working
        let color = active ? FleetMapColors.sage : FleetMapColors.lineGrey
        let dashPhase: CGFloat = (active && !reduceMotion && flow) ? -10 : 0
        let style = active
            ? StrokeStyle(lineWidth: 1.5, dash: [4, 6], dashPhase: dashPhase)
            : StrokeStyle(lineWidth: 1)
        return connectionPath(to: geometry)
            .stroke(color, style: style)
            .frame(width: FleetMapLayout.canvas.width, height: FleetMapLayout.canvas.height)
    }

    /// Cubic curve from the case centre to the node, exactly as in the design's `d` attributes.
    private func connectionPath(to geometry: FleetNodeGeometry) -> Path {
        Path { path in
            path.move(to: FleetMapLayout.origin.center)
            if let controls = geometry.curveControls, controls.count == 2 {
                path.addCurve(to: geometry.center, control1: controls[0], control2: controls[1])
            } else {
                path.addLine(to: geometry.center)
            }
        }
    }

    // MARK: Nodes

    /// `FleetNodeState` alone decides the styling: `working` gets the sage treatment,
    /// `idle` and `offline` share the grey one.
    private func nodeCircle(_ node: FleetMapNode, geometry: FleetNodeGeometry) -> some View {
        let active = node.state == .working
        return ZStack {
            Circle()
                .fill(active ? FleetMapColors.busyFill : FleetMapColors.idleFill)
            Circle()
                .strokeBorder(
                    active ? FleetMapColors.sage : FleetMapColors.idleStroke,
                    lineWidth: 1.5
                )
            if active && !reduceMotion {
                Circle()
                    .strokeBorder(FleetMapColors.sage, lineWidth: 1.5)
                    .scaleEffect(pulse ? 1 + 4 / geometry.radius : 1)
                    .opacity(pulse ? 0.2 : 1)
            }
        }
        .frame(width: geometry.radius * 2, height: geometry.radius * 2)
        .position(x: geometry.center.x, y: geometry.center.y)
    }

    private func nodeLabel(_ label: String, geometry: FleetNodeGeometry) -> some View {
        Text(label)
            .font(.system(size: 9))
            .foregroundColor(FleetMapColors.foreground)
            .fixedSize()
            .frame(width: geometry.labelWidth, alignment: geometry.labelAlignment)
            .position(x: geometry.labelCenter.x, y: geometry.labelCenter.y)
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        let activeNames = model.nodes.filter(\.busy).map(\.label)
        guard !activeNames.isEmpty else { return "Fleet map, no active nodes" }
        return "Fleet map, \(activeNames.joined(separator: ", ")) active"
    }
}
