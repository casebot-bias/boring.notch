//
//  FleetPressureView.swift
//  boringNotch
//
//  Footer machine strip: one triple ring per machine (outer CPU, middle GPU, inner RAM) with the
//  machine's name over its highest reading, so every machine of the fleet is visible at once.
//

import Defaults
import SwiftUI

struct FleetPressureView: View {
    let hosts: [FleetHostReading]

    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                if index > 0 { Spacer(minLength: 8) }
                HostRings(host: host, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One machine: its 34 pt triple ring beside the name over the highest reading.
private struct HostRings: View {
    let host: FleetHostReading
    let theme: FleetTheme

    var body: some View {
        HStack(spacing: 6) {
            TripleRing(host: host, theme: theme)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(host.label)
                    .font(FleetType.size(11, weight: .semibold))
                    .foregroundColor(host.live ? theme.text : theme.off)
                Text(FleetFormat.ringHeadline(host))
                    .font(FleetType.mono(size: 11, weight: .medium))
                    .foregroundColor(theme.ringTextColor(FleetFormat.ringLevel(host.hottest?.value)))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(FleetFormat.ringDetail(host))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FleetFormat.ringDetail(host))
    }
}

/// The cluster's three arcs: outer CPU (r 15), middle GPU (r 11), inner RAM (r 7), each a 3 pt
/// round-capped stroke that starts at 12 o'clock and runs clockwise to its percent. A ring with no
/// reading keeps its track only; an offline machine draws no arcs at all. New readings ease in over
/// 0.3 s unless Reduce Motion is on.
private struct TripleRing: View {
    let host: FleetHostReading
    let theme: FleetTheme
    /// Reduce Motion turns the arcs' easing off: they then jump straight to the new reading.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Spec: Identifiable {
        let kind: FleetRingKind
        let radius: CGFloat
        var id: FleetRingKind { kind }
    }

    private static let ringWidth: CGFloat = 3
    private static let specs = [Spec(kind: .cpu, radius: 15), Spec(kind: .gpu, radius: 11), Spec(kind: .ram, radius: 7)]

    var body: some View {
        ZStack {
            ForEach(Self.specs) { spec in
                Circle()
                    .stroke(theme.ringTrack, style: StrokeStyle(lineWidth: Self.ringWidth))
                    .frame(width: spec.radius * 2, height: spec.radius * 2)
                if let fraction = host.arcFraction(spec.kind),
                   let level = FleetFormat.ringLevel(host.value(spec.kind)) {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(theme.ringArcColor(level, kind: spec.kind),
                                style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                        .frame(width: spec.radius * 2, height: spec.radius * 2)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
                }
            }
        }
        .rotationEffect(.degrees(-90))
    }
}
