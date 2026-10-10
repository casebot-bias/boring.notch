//
//  FleetSectionView.swift
//  boringNotch
//
//  Right-hand Fleet column of the opened notch: 1 px divider, header readout
//  (wordmark + subtitle beside the fleet output total), hairline, health row,
//  the response map next to current work, and a footer of hardware peaks with
//  an Open Fleet button.
//  Colours are driven by FleetTheme (skin: FleetSkin).
//

import AppKit
import SwiftUI
import Defaults


// MARK: - Section View

struct FleetSectionView: View {
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    @State private var openHovered = false
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            theme.line
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                header
                theme.line
                    .frame(height: 1)
                healthRow
                if !store.panelModel.decisions.isEmpty { decisionStrip(store.panelModel.decisions) }
                main
                footer
            }
            .padding(.leading, 18)
        }
        .frame(height: fleetSectionHeight, alignment: .topLeading)
    }

    // MARK: - Header

    /// "FLEET" wordmark + subtitle on the left, the FLEET OUTPUT tok/s total
    /// baseline-aligned on the right; the total dims to `dim` when unreported.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FLEET")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(theme.muted)
                Text("SEVEN AGENTS. ONE CASE.")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(theme.dim)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("FLEET OUTPUT")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let output = FleetFormat.fleetOutput(store.panelModel.totalTokPerSec)
                    Text(output)
                        .font(.system(size: 24, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(output == FleetFormat.unknown ? theme.dim : theme.accent)
                    Text("tok/s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.dim)
                }
            }
        }
    }

    // MARK: - Health row

    /// Three equal thirds: working-tasks count with a busy pip, the linked
    /// tally, and the All-clear/critical status word.
    private var healthRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Rectangle()
                    .fill(store.panelModel.workingCount > 0 ? theme.accent : theme.off)
                    .frame(width: 4, height: 4)
                (Text("\(store.panelModel.runningTaskCount)")
                    .foregroundColor(theme.text)
                 + Text(" tasks")
                    .foregroundColor(theme.dim))
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(FleetFormat.linked(store.panelModel.linkedCount, of: store.panelModel.agentCount))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.dim)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(FleetFormat.status(store.panelModel.criticalCount))
                .font(.system(size: 12))
                .foregroundColor(store.panelModel.criticalCount == 0 ? theme.accent : theme.hot)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 14)
    }

    // MARK: - Decision rows

    /// Odin's open needs-decision alerts under the health row: a red pip and the words
    /// "ODIN NEEDS DECISION", the open count and a "last known" marker while the feed is
    /// unreachable, then one row per open decision — its job and pull request on the left,
    /// the reason in plain words on the right. Absent (the ordinary case) it takes no room.
    /// The strip uses the skin's text colours and the alert red only for its pip. The heading
    /// draws in `hot`, whose 4.5:1 accent floor only applies from 12 pt up, so its size is
    /// pinned to `FleetPanelMetrics.alertHeadingTextSize` rather than the 11 pt minimum.
    private func decisionStrip(_ decisions: [FleetDecision]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Rectangle()
                    .fill(theme.alert)
                    .frame(width: 4, height: 4)
                Text("ODIN NEEDS DECISION")
                    .font(.system(size: FleetPanelMetrics.alertHeadingTextSize, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.hot)
                Spacer(minLength: 8)
                if let count = FleetFormat.decisionCountLabel(decisions.count) {
                    Text(count)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                }
                if let staleness = FleetFormat.decisionStaleness(store.isReachable) {
                    Text(staleness)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.dim)
                        .lineLimit(1)
                }
            }
            ForEach(decisions.indices, id: \.self) { index in
                decisionRow(decisions[index])
            }
        }
    }

    private func decisionRow(_ decision: FleetDecision) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(FleetFormat.decisionSubject(decision))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.muted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(FleetFormat.decisionReason(decision.reason, round: decision.round))
                .font(.system(size: 11))
                .foregroundColor(theme.text)
                .lineLimit(1)
        }
    }

    // MARK: - Main

    /// Response map and current work split the row with a 1 px hairline; the
    /// map takes at least `responseMapWidth` and the work column takes the
    /// remainder. This row absorbs whatever height the fixed rows leave.
    private var main: some View {
        HStack(alignment: .top, spacing: 20) {
            FleetResponseMapView(lanes: store.panelModel.agents, origin: store.panelModel.origin)
                .frame(minWidth: FleetPanelMetrics.responseMapWidth, maxWidth: .infinity)
            theme.line
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            FleetWorkView(jobs: store.panelModel.nowJobs,
                          runningTaskCount: store.panelModel.runningTaskCount)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    /// CPU/GPU/RAM peak rings on the left, the bordered Open Fleet button on
    /// the right.
    private var footer: some View {
        HStack(alignment: .center, spacing: 0) {
            FleetPressureView(peaks: store.panelModel.peaks)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openFleet) {
                Text("Open Fleet →")
                    .font(.system(size: 11))
                    .foregroundColor(openHovered ? theme.accent : theme.text)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(openHovered ? theme.accent : theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { openHovered = $0 }
        }
        .frame(height: 40)
    }

    private func openFleet() {
        guard let url = FleetFormat.fleetBaseURL(Defaults[.fleetBaseURL]) else { return }
        NSWorkspace.shared.open(url)
    }
}
