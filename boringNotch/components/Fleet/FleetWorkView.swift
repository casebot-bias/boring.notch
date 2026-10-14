//
//  FleetWorkView.swift
//  boringNotch
//
//  The CURRENT WORK column of the expanded Fleet panel: the heartbeat of the
//  running Case jobs, the test and build commands they wait on, up to two
//  running jobs in preview, a "+N jobs in Fleet" link to the full view, or an
//  idle prompt when nothing is running. Reads only the model it is given.
//

import AppKit
import Defaults
import SwiftUI

struct FleetWorkView: View {
    let jobs: [FleetJob]
    let runningTaskCount: Int
    /// The running Case jobs from `/api/jobs`; empty without that feed, and the column reads as before.
    var caseJobs: [CaseJob] = []
    /// The test and build commands the Case jobs wait on, from `/api/activity`. They are work in
    /// progress but not running jobs, so they get their own lines and never move `runningTaskCount`.
    var toolRuns: [ToolRun] = []

    @Default(.fleetSkin) private var fleetSkin
    @State private var linkHovered = false
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    /// The heartbeat lines that fit (the first running jobs), and the previews that share the column.
    private var jobLines: [CaseJob] { Array(caseJobs.prefix(FleetPanelMetrics.caseJobLineLimit)) }
    private var previewLimit: Int { FleetPanelMetrics.previewLimit(caseJobLines: jobLines.count) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
                .padding(.bottom, 8)

            if !jobLines.isEmpty {
                heartbeat
                    .padding(.bottom, (jobs.isEmpty && toolRuns.isEmpty) ? 0 : 8)
            }

            if !toolRuns.isEmpty {
                FleetToolRunLines(runs: toolRuns, theme: theme)
                    .padding(.bottom, jobs.isEmpty ? 0 : 8)
            }

            if jobs.isEmpty {
                if jobLines.isEmpty && toolRuns.isEmpty { emptyState }
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
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundColor(theme.muted)
            Spacer(minLength: 0)
            Text("\(runningTaskCount)")
                .font(FleetType.mono(size: 13, weight: .medium))
                .foregroundColor(theme.text)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No tasks running.")
            Text("Ready for the next assignment.")
        }
        .font(.system(size: 12.5))
        .foregroundColor(theme.muted)
        .padding(.top, 20)
    }

    // MARK: - Heartbeat

    private var heartbeat: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(jobLines) { job in
                heartbeatRow(FleetFormat.caseJobLine(job))
            }
        }
    }

    /// One Case job on one line: name, `2/5`, `12m` (amber after an hour), watchdog badge.
    private func heartbeatRow(_ line: FleetFormat.CaseJobLine) -> some View {
        HStack(spacing: FleetPanelMetrics.caseJobLineSpacing) {
            Text(line.name)
                .font(.system(size: 12))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let items = line.items {
                Text(items)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let commit = line.commit {
                Text(commit)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(line.commitIsStale ? theme.hotText : theme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let badge = line.badge {
                Text(badge.text)
                    .font(FleetType.mono(size: 11, weight: .medium))
                    .foregroundColor(badge.level == .red ? theme.alertChipText : theme.hotText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: FleetPanelMetrics.caseJobLineHeight)
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
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                Spacer(minLength: 0)
                Text("RUNNING")
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
            }
            Text(job.label)
                .font(.system(size: 12.5))
                .foregroundColor(theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(FleetFormat.step(job.step))
                .font(.system(size: 12.5))
                .foregroundColor(theme.muted)
                .lineLimit(1)
        }
    }

    // MARK: - More link

    private var moreLink: some View {
        Button(action: openFleet) {
            Text("+\(runningTaskCount - previewLimit) jobs in Fleet →")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(linkHovered ? theme.accent : theme.muted)
        }
        .buttonStyle(.plain)
        .onHover { linkHovered = $0 }
    }

    private func openFleet() {
        guard let url = FleetFormat.fleetBaseURL(Defaults[.fleetBaseURL]) else { return }
        NSWorkspace.shared.open(url)
    }
}
