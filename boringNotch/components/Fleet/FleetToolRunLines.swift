//
//  FleetToolRunLines.swift
//  boringNotch
//
//  The CURRENT WORK column's grouped tool lines of jobs without a heartbeat row,
//  split out of the work view so the render tests can draw them without the app.
//

import SwiftUI

/// The CURRENT WORK column's grouped tool lines of jobs without a heartbeat row:
/// one 16 pt line per job, in the feed's order. A leaf view - no store, no defaults,
/// no state - so the render tests can draw it without the app, which the work column
/// itself cannot (it reads the app's defaults for its Open Fleet link).
struct FleetToolRunLines: View {
    let lines: [String]
    let theme: FleetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: FleetPanelMetrics.caseJobLineHeight, alignment: .leading)
            }
        }
    }
}
