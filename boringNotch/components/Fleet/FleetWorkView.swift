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

    // MARK: - Body

    var body: some View {
        let plan = FleetPanelMetrics.workPlan(caseJobs: caseJobs, toolRuns: toolRuns, jobs: jobs,
                                              runningTaskCount: runningTaskCount)
        return VStack(alignment: .leading, spacing: 0) {
            head

            if caseJobs.isEmpty && toolRuns.isEmpty && jobs.isEmpty {
                emptyState
            } else {
                if !plan.heartbeats.isEmpty {
                    Color.clear.frame(height: 8)
                    ForEach(plan.heartbeats.indices, id: \.self) { index in
                        heartbeatRow(plan.heartbeats[index].line)
                        if let subline = plan.heartbeats[index].subline {
                            sublineRow(subline)
                        }
                    }
                }

                if !plan.orphanLines.isEmpty {
                    Color.clear.frame(height: 8)
                    FleetToolRunLines(lines: plan.orphanLines, theme: theme)
                }

                if !plan.previews.isEmpty {
                    Color.clear.frame(height: 8)
                    previews(plan.previews)
                }
            }

            Spacer(minLength: 0)

            if plan.hidden > 0 {
                moreLink(plan.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Head

    private var head: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CURRENT WORK")
                .font(FleetType.size(11, weight: .semibold))
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
        .font(FleetType.size(12.5))
        .foregroundColor(theme.muted)
        .padding(.top, 20)
    }

    // MARK: - Heartbeat

    /// A tool group's sub-line under its heartbeat row: the same mono and dim as the orphan tool
    /// lines, indented because the row above already names the job.
    private func sublineRow(_ text: String) -> some View {
        Text(text)
            .font(FleetType.mono(size: 11))
            .foregroundColor(theme.dim)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 10)
            .frame(height: FleetPanelMetrics.caseJobLineHeight, alignment: .leading)
    }

    /// One Case job on one line: name, `2/5`, `12m` (amber after an hour), watchdog badge.
    private func heartbeatRow(_ line: FleetFormat.CaseJobLine) -> some View {
        HStack(spacing: FleetPanelMetrics.caseJobLineSpacing) {
            Text(line.name)
                .font(FleetType.size(12))
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

    private func previews(_ jobs: [FleetJob]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(jobs.indices, id: \.self) { index in
                jobRow(jobs[index])
                if index < jobs.count - 1 {
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
                .font(FleetType.size(12.5))
                .foregroundColor(theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(FleetFormat.step(job.step))
                .font(FleetType.size(12.5))
                .foregroundColor(theme.muted)
                .lineLimit(1)
        }
    }

    // MARK: - More link

    private func moreLink(_ hidden: Int) -> some View {
        Button(action: openFleet) {
            Text("+\(hidden) jobs in Fleet →")
                .font(FleetType.size(12, weight: .medium))
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
