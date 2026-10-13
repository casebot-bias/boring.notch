//
//  FleetCaseBoxView.swift
//  boringNotch
//
//  The response map's centred origin node — while the origin runs work
//  the box says "Working" with its job count, and falls back to
//  "Online" / "Offline" while idle or unreachable.
//

import SwiftUI

struct FleetCaseBoxView: View {
    /// The map's origin lane ("case").
    let lane: FleetLane

    /// The current Fleet theme colours.
    let theme: FleetTheme

    /// The box size; the map always uses 60 pt.
    var size: CGFloat = 60

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(theme.line, lineWidth: 1)
            .frame(width: size, height: size)
            .overlay {
                VStack(spacing: 1) {
                    Text(lane.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.text)
                    Text(FleetFormat.caseBoxState(lane))
                        .font(FleetType.mono(size: 11))
                        .foregroundColor(lane.state == .busy ? theme.accent : theme.dim)
                    if let jobs = FleetFormat.caseBoxJobs(lane) {
                        Text(jobs)
                            .font(FleetType.mono(size: 11))
                            .foregroundColor(theme.dim)
                    }
                    if let speed = FleetFormat.speedDetail(lane) {
                        Text(speed)
                            .font(FleetType.mono(size: 11))
                            .foregroundColor(theme.dim)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 3)
            }
    }
}
