//
//  FleetSectionView.swift
//  boringNotch
//
//  Right-hand Fleet column of the opened notch: 1 px divider, a one-line header,
//  the FLEET / DECISIONS tab strip carrying the health line, then the FLEET tab (map
//  next to current work, footer of per-machine rings and Open Fleet) or the DECISIONS tab.
//  Colours are driven by FleetTheme (skin: FleetSkin).
//

import AppKit
import SwiftUI
import Defaults


// MARK: - Panel Tabs

/// The Fleet panel's two tabs.
enum FleetPanelTab: Equatable { case fleet, odin }

// MARK: - Section View

struct FleetSectionView: View {
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    @State private var openHovered = false
    /// The tab the panel opens on: the panel starts on FLEET; the render harness picks one.
    let initialTab: FleetPanelTab
    @State private var tab: FleetPanelTab

    init(initialTab: FleetPanelTab = .fleet) {
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            theme.line.frame(width: 1).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 8)
                tabsRow
                Group {
                    switch tab {
                    case .fleet:
                        fleetTab
                    case .odin:
                        OdinDecisionView(
                            decisions: store.panelModel.decisions,
                            sendingJob: store.sendingDecisionJob,
                            sentJob: store.sentDecisionJob,
                            error: store.decisionError,
                            onSend: { decision, option in
                                Task { await store.sendDecision(decision, option: option) }
                            }
                        )
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, 18)
        }
        .frame(height: fleetSectionHeight, alignment: .topLeading)
    }

    // MARK: - Header

    /// "FLEET" wordmark on the left; on the right, the speed trend sparkline then
    /// the speed on one line: the number is L1 data, the unit and "idle" are L3.
    private var header: some View {
        let model = store.panelModel
        let idle = FleetFormat.speedIsIdle(model.speed)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("FLEET")
                .font(.system(size: 15, weight: .bold))
                .tracking(0.3)
                .foregroundColor(theme.text)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                FleetSpeedTrend(speed: model.speed, theme: theme)
                Text(FleetFormat.speedNumberText(model.speed))
                    .font(FleetType.mono(size: 13, weight: .medium))
                    .foregroundColor(idle ? theme.dim : theme.text)
                Text(" tok/s")
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                if idle {
                    Text("idle")
                        .font(FleetType.mono(size: 11))
                        .foregroundColor(theme.dim)
                }
            }
        }
    }

    // MARK: - Tabs

    /// FLEET / DECISIONS tabs with the health line on the same line, over the strip's hairline.
    private var tabsRow: some View {
        let model = store.panelModel
        return HStack(alignment: .center, spacing: 20) {
            tabButton("FLEET", .fleet)
            tabButton("DECISIONS", .odin, chip: FleetFormat.actionNeededLabel(model.decisions.count))
            Spacer(minLength: 8)
            Text(FleetFormat.healthLine(runningTasks: model.runningTaskCount,
                                        linked: model.linkedCount,
                                        of: model.agentCount,
                                        critical: model.criticalCount))
                .font(FleetType.mono(size: 11))
                .foregroundColor(model.criticalCount > 0 ? theme.hotText : theme.dim)
                .lineLimit(1)
        }
        .frame(height: 26)
        .overlay(alignment: .bottom) { theme.line.frame(height: 1) }
    }

    /// One tab: L2 label (active: `text` semibold; inactive: `dim` medium), an
    /// action-needed chip on DECISIONS while a decision is open, and a 2 pt accent
    /// underline over the strip's hairline when active.
    private func tabButton(_ title: String, _ value: FleetPanelTab, chip: String? = nil) -> some View {
        let current = tab == value
        return HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: current ? .semibold : .medium))
                .tracking(0.7)
                .foregroundColor(current ? theme.text : theme.dim)
            if let chip = chip {
                ActionNeededChip(label: chip, theme: theme)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(current ? theme.accent : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { tab = value }
    }

    // MARK: - Fleet Tab

    /// The FLEET tab: response map next to current work, then the peaks and Open Fleet.
    private var fleetTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.top, 12)
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

    /// One triple ring per fleet machine on the left, the bordered Open Fleet
    /// button on the right.
    /// 10 pt keeps the last machine's reading clear of the button, a 100 % reading included.
    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            FleetPressureView(hosts: store.panelModel.hosts)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openFleet) {
                Text("Open Fleet →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(openHovered ? theme.accent : theme.muted)
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

// MARK: - Action-Needed Chip

/// The ODIN tab's action-needed chip; its dot breathes by size, never by
/// opacity, because an alert dot must keep its 3:1 floor.
private struct ActionNeededChip: View {
    let label: String
    let theme: FleetTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(theme.alert)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion ? 1 : (pulsing ? FleetPanelMetrics.alertPulseScale : 1))
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(theme.alertChipText)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.alert.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.alert.opacity(0.55), lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Speed Trend

/// The header's 64 × 14 pt speed sparkline: one 1 pt polyline through the
/// trend's non-nil readings, scaled to the box with the series' own min/max
/// (a flat series draws a mid-height line). Nulls break the line into separate
/// segments; a trend with no reading leaves an empty canvas. The stroke is
/// `accent` while the speed is live and `dim` while idle.
private struct FleetSpeedTrend: View {
    let speed: FleetSpeed?
    let theme: FleetTheme

    private static let boxWidth: CGFloat = 64
    private static let boxHeight: CGFloat = 14
    private static let lineWidth: CGFloat = 1

    var body: some View {
        let values = speed?.trend ?? []
        let idle = FleetFormat.speedIsIdle(speed)
        return Canvas { context, size in
            let readings = values.compactMap { $0 }
            guard let lo = readings.min(), let hi = readings.max() else { return }
            let inset = Self.lineWidth / 2
            let count = values.count
            func point(_ index: Int, _ value: Double) -> CGPoint {
                let x = count > 1
                    ? CGFloat(index) / CGFloat(count - 1) * size.width
                    : size.width / 2
                // A flat series (min == max) has no range to scale into: draw mid-height.
                let y = hi == lo
                    ? size.height / 2
                    : inset + (1 - CGFloat((value - lo) / (hi - lo))) * (size.height - 2 * inset)
                return CGPoint(x: x, y: y)
            }
            // Split on nulls into contiguous runs, then trace them all as one path.
            var runs: [[CGPoint]] = []
            var run: [CGPoint] = []
            for (index, value) in values.enumerated() {
                if let value = value {
                    run.append(point(index, value))
                } else if !run.isEmpty {
                    runs.append(run)
                    run = []
                }
            }
            if !run.isEmpty { runs.append(run) }
            var path = Path()
            for run in runs {
                // A run of one point draws as a round dot.
                path.addLines(run.count >= 2 ? run : [run[0], run[0]])
            }
            context.stroke(
                path,
                with: .color(idle ? theme.dim : theme.accent),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: Self.boxWidth, height: Self.boxHeight)
    }
}
