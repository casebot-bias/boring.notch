//
//  FleetToolRunLines.swift
//  boringNotch
//
//  The CURRENT WORK column's tool-run lines, split out of the work view so the render tests can
//  draw them without the app.
//

import SwiftUI

/// The CURRENT WORK column's tool-run lines: one line per test, build or other command a Case job is
/// waiting on, in the feed's order. A leaf view - no store, no defaults, no state - so the render
/// tests can draw it without the app, which the work column itself cannot (it reads the app's
/// defaults for its Open Fleet link).
struct FleetToolRunLines: View {
    let runs: [ToolRun]
    let theme: FleetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(runs) { run in
                Text(FleetFormat.toolRunLine(run))
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
                    // A real job name plus its command overruns the 252 pt column, and the age is the
                    // part the owner reads: middle truncation keeps the tail ("… · 10m") in view.
                    .truncationMode(.middle)
                    .frame(height: FleetPanelMetrics.caseJobLineHeight, alignment: .leading)
            }
        }
    }
}
