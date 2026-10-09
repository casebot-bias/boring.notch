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
                    .tracking(1.4)
                    .foregroundColor(theme.muted)
                Text("SIX AGENTS. ONE CASE.")
                    .font(.system(size: 6, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(theme.dim)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("FLEET OUTPUT")
                    .font(.system(size: 6.5, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let output = FleetFormat.fleetOutput(store.panelModel.totalTokPerSec)
                    Text(output)
                        .font(.system(size: 24, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(output == FleetFormat.unknown ? theme.dim : theme.accent)
                    Text("tok/s")
                        .font(.system(size: 8, design: .monospaced))
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
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(FleetFormat.linked(store.panelModel.linkedCount, of: store.panelModel.agentCount))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.dim)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(FleetFormat.status(store.panelModel.criticalCount))
                .font(.system(size: 9))
                .foregroundColor(store.panelModel.criticalCount == 0 ? theme.accent : theme.hot)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 14)
    }

    // MARK: - Main

    /// Response map and current work share the column evenly, split by a 1 px
    /// hairline; this row absorbs whatever height the fixed rows leave.
    private var main: some View {
        HStack(alignment: .top, spacing: 20) {
            FleetResponseMapView(lanes: store.panelModel.agents, origin: store.panelModel.origin)
                .frame(maxWidth: .infinity)
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
