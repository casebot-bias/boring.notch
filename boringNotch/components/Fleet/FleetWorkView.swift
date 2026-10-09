//
//  FleetWorkView.swift
//  boringNotch
//
//  The CURRENT WORK column of the expanded Fleet panel: up to two running
//  jobs in preview, a "+N jobs in Fleet" link to the full view, or an
//  idle prompt when nothing is running. Reads only the model it is given.
//

import AppKit
import Defaults
import SwiftUI

struct FleetWorkView: View {
    let jobs: [FleetJob]
    let runningTaskCount: Int

    @Default(.fleetSkin) private var fleetSkin
    @State private var linkHovered = false
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    private let previewLimit = 2

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
                .padding(.bottom, 8)

            if jobs.isEmpty {
                emptyState
            } else {
                previews
            }

            Spacer(minLength: 0)

            if runningTaskCount > previewLimit {
                moreLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Head

    private var head: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CURRENT WORK")
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(theme.dim)
            Spacer(minLength: 0)
            Text("\(runningTaskCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.muted)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No tasks running.")
            Text("Ready for the next assignment.")
        }
        .font(.system(size: 12))
        .foregroundColor(theme.dim)
        .padding(.top, 20)
    }

    // MARK: - Previews

    private var previews: some View {
        let rows = Array(jobs.prefix(previewLimit))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                jobRow(rows[index])
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.vertical, 7)
                }
            }
        }
    }

    private func jobRow(_ job: FleetJob) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 4, height: 4)
                Text(job.pill)
                    .font(.system(size: 12))
                    .foregroundColor(theme.nameText)
                Spacer(minLength: 0)
                Text("RUNNING")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.dim)
            }
            Text(job.label)
                .font(.system(size: 12.5))
                .foregroundColor(theme.jobText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(FleetFormat.step(job.step))
                .font(.system(size: 12))
                .foregroundColor(theme.dim)
                .lineLimit(1)
        }
    }

    // MARK: - More link

    private var moreLink: some View {
        Button(action: openFleet) {
            Text("+\(runningTaskCount - previewLimit) jobs in Fleet →")
                .font(.system(size: 12))
                .foregroundColor(linkHovered ? theme.accent : theme.dim)
        }
        .buttonStyle(.plain)
        .onHover { linkHovered = $0 }
    }

    private func openFleet() {
        guard let url = FleetFormat.fleetBaseURL(Defaults[.fleetBaseURL]) else { return }
        NSWorkspace.shared.open(url)
    }
}
