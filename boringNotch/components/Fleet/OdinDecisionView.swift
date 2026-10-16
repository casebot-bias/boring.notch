//
//  OdinDecisionView.swift
//  boringNotch
//
//  The ODIN tab: one chip per open decision, the reason with an "Open PR ↗"
//  link, a QUESTION / ODIN FOUND switch over the findings box, and the
//  option list with the "Send decision" button. The findings box is a real
//  ScrollView, not an offset-and-clip drag: only a scroll container gives
//  trackpad and wheel scrolling and a scroll indicator, and it can be exactly
//  as tall as its text up to 96 pt. Only the chip strip still drags open
//  (offset + clip), since it is a single row that never scrolls; that keeps
//  its text rendering everywhere, offscreen PNGs included. Labels and
//  sentences draw in SF Pro, data in JetBrains Mono, nothing below 11 pt.
//

import AppKit
import Defaults
import SwiftUI

/// The findings box: ceiling, fade height and the two rules the box obeys.
enum OdinDecisionPaneMetrics {
    /// The tallest the findings box draws; longer text scrolls inside it.
    static let maxHeight: CGFloat = 96
    /// Height of the bottom fade shown while more text is below the box.
    static let fadeHeight: CGFloat = 12
    /// The content's own height, never past `maxHeight`; 0 (not measured yet) draws the ceiling.
    static func boxHeight(contentHeight: CGFloat) -> CGFloat {
        contentHeight > 0 ? min(maxHeight, contentHeight) : maxHeight
    }
    /// True while text is cut off below the box's lower edge.
    static func moreBelow(offset: CGFloat, boxHeight: CGFloat, contentHeight: CGFloat) -> Bool {
        contentHeight > 0 && offset + boxHeight < contentHeight - 0.5
    }
}

/// What the box measures about itself: how far it is scrolled, how tall its content is.
struct OdinPaneScroll: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    static let top = OdinPaneScroll()
}

/// One measurement per layout pass from the box's own GeometryReader.
struct OdinPaneScrollKey: PreferenceKey {
    static var defaultValue = OdinPaneScroll.top
    static func reduce(value: inout OdinPaneScroll, nextValue: () -> OdinPaneScroll) {
        let next = nextValue()
        if next.contentHeight > 0 { value = next }
    }
}

struct OdinDecisionView: View {
    let decisions: [FleetDecision]
    let sendingJob: String?
    let sentJob: String?
    let error: String?
    /// The Case jobs' heartbeat, for the proof readout; empty without that feed.
    var caseJobs: [CaseJob] = []
    let onSend: (FleetDecision, OdinOption) -> Void

    /// Fixture entry: the proof harness renders ODIN FOUND without a click, since a synthesized
    /// click never reaches a SwiftUI button in-process. The tab itself always starts on QUESTION.
    init(decisions: [FleetDecision],
         sendingJob: String?,
         sentJob: String?,
         error: String?,
         caseJobs: [CaseJob] = [],
         startsOnFound: Bool = false,
         onSend: @escaping (FleetDecision, OdinOption) -> Void) {
        self.decisions = decisions
        self.sendingJob = sendingJob
        self.sentJob = sentJob
        self.error = error
        self.caseJobs = caseJobs
        self.onSend = onSend
        _pane = State(initialValue: startsOnFound ? .found : .question)
    }

    @Default(.fleetSkin) private var fleetSkin
    @State private var index = 0
    @State private var pane: Pane = .question
    @State private var picked: [String: String] = [:]
    @State private var chipOffset: CGFloat = 0
    @State private var chipDragStart: CGFloat?
    @State private var paneScroll = OdinPaneScroll.top
    private static let paneScrollSpace = "odinPaneScroll"

    private enum Pane { case question, found }
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    // MARK: - Helpers

    /// The pick map's key for a decision: its job, falling back to its chip text.
    private func key(_ d: FleetDecision) -> String {
        return d.job ?? FleetFormat.decisionChip(d)
    }

    /// The selected decision. `index` is clamped on read and pulled back on shrink, so it never reads out of range.
    private var current: FleetDecision? {
        guard !decisions.isEmpty else { return nil }
        return decisions[FleetFormat.clampedIndex(index, count: decisions.count)]
    }

    /// Moves the selection by `k` from the clamped base, wrapping around the list.
    private func step(_ k: Int) {
        guard !decisions.isEmpty else { return }
        let base = FleetFormat.clampedIndex(index, count: decisions.count)
        index = (base + k + decisions.count) % decisions.count
    }

    // MARK: - Body

    var body: some View {
        Group {
            if decisions.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    chipsRow
                    if sentJob != nil {
                        sentNote
                    }
                    if let d = current {
                        decisionBody(d)
                    }
                }
            }
        }
        .onChange(of: decisions.count) { _, count in
            index = FleetFormat.clampedIndex(index, count: count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text(sentJob != nil
             ? "Decision sent. Case goes on with the job. Odin reviews it again when it is done."
             : "No decisions waiting. Odin is idle.")
            .font(.system(size: 12.5))
            .foregroundColor(sentJob != nil ? theme.accent : theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    /// "Decision sent" until the next fetch. Shown even while other decisions are still open:
    /// the answered job leaves the list at once, so only `sentJob` remembers that it was answered.
    private var sentNote: some View {
        Text("Decision sent")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(theme.accent)
            .lineLimit(1)
    }

    // MARK: - Chips row

    /// The chip strip: a `GeometryReader` viewport measures the space left after
    /// the ‹ › steppers and the counter, and the chips drag sideways inside it
    /// (offset + clip, clamped so they never pass the left edge). The viewport
    /// contributes no ideal width, so the strip never sizes the tab.
    private var chipsRow: some View {
        HStack(spacing: 6) {
            chipsViewport
            if decisions.count > 1 {
                arrowButton("‹") { step(-1) }
                arrowButton("›") { step(1) }
            }
            Text(FleetFormat.decisionProgress(index: index, count: decisions.count))
                .font(FleetType.mono(size: 11))
                .foregroundColor(theme.dim)
                .lineLimit(1)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { value in
                let start = chipDragStart ?? chipOffset
                chipDragStart = start
                chipOffset = min(0, start + value.translation.width)
            }
            .onEnded { _ in chipDragStart = nil })
    }

    /// The chip content at its natural width; the viewport clips and offsets it.
    private var chipStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(decisions.enumerated()), id: \.offset) { offset, d in
                chip(d, selected: offset == FleetFormat.clampedIndex(index, count: decisions.count)) { index = offset }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The measured viewport: the strip sits at its natural width, offset by the
    /// drag, and is clipped to the width the row offers it.
    private var chipsViewport: some View {
        GeometryReader { geo in
            chipStrip
                .offset(x: chipOffset)
                .frame(width: max(0, geo.size.width), alignment: .leading)
                .clipped()
        }
        .frame(height: 22)
    }

    /// One open decision: "<job> #<pr>" with a red pip; the selected chip carries the orange frame.
    private func chip(_ d: FleetDecision, selected: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.alert)
                    .frame(width: 6, height: 6)
                Text(FleetFormat.decisionChip(d))
                    .font(selected ? FleetType.mono(size: 11, weight: .medium) : FleetType.mono(size: 11))
                    .foregroundColor(selected ? theme.text : theme.dim)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? theme.hot.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? theme.hot : theme.pillBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// A ‹ / › stepper square beside the chips.
    private func arrowButton(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 12))
                .foregroundColor(theme.text)
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.pillBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Decision body

    private func decisionBody(_ d: FleetDecision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            whyRow(d)
            HStack(alignment: .top, spacing: 14) {
                questionPane(d)
                optionsPane(d)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Why row

    /// The reason in hotText mono over a hairline, with the PR link on the right.
    private func whyRow(_ d: FleetDecision) -> some View {
        let url = FleetFormat.decisionPullRequestURL(d)
        return HStack(spacing: 8) {
            Text(FleetFormat.decisionWhy(d))
                .font(FleetType.mono(size: 11))
                .foregroundColor(theme.hotText)
                .lineLimit(1)
            if let proof = FleetFormat.decisionProof(d, jobs: caseJobs) {
                Text(proof.text)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
                if let blocking = proof.blocking {
                    Text(blocking)
                        .font(FleetType.mono(size: 11))
                        .foregroundColor(theme.alertChipText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                if let url {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open PR ↗")
                    .font(.system(size: 12))
                    .foregroundColor(url == nil ? theme.dim : theme.text)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.pillBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(url == nil)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            theme.line.frame(height: 1)
        }
    }

    // MARK: - Question pane

    /// QUESTION / ODIN FOUND switch over the findings box. The box is a real
    /// ScrollView: as tall as its text up to `OdinDecisionPaneMetrics.maxHeight`,
    /// scrollable by trackpad and wheel, with a fade while text is cut off below.
    /// A fresh scroll view (new decision or pane) starts at the top.
    private func questionPane(_ d: FleetDecision) -> some View {
        let boxHeight = OdinDecisionPaneMetrics.boxHeight(contentHeight: paneScroll.contentHeight)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                paneButton("QUESTION", active: pane == .question) { pane = .question }
                paneButton("ODIN FOUND \(d.found.count)", active: pane == .found) { pane = .found }
            }
            ScrollView(.vertical) {
                paneContent(d)
            }
            .scrollIndicators(.visible)
            .coordinateSpace(name: Self.paneScrollSpace)
            .frame(height: boxHeight, alignment: .top)
            .mask(paneFade(boxHeight: boxHeight))
            .onPreferenceChange(OdinPaneScrollKey.self) { paneScroll = $0 }
            // A fresh scroll view starts at the top: the old drag offset reset on both changes.
            .id("\(key(d))-\(pane)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The findings box's text: the question, or the ODIN FOUND lines.
    private func paneContent(_ d: FleetDecision) -> some View {
        Group {
            switch pane {
            case .question:
                Text(FleetFormat.decisionQuestion(d))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            case .found:
                if d.found.isEmpty {
                    Text("Odin found nothing to report.")
                        .font(.system(size: 11))
                        .foregroundColor(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(d.found.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 6) {
                                Rectangle()
                                    .fill(theme.hot)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 4)
                                Text(line)
                                    .font(FleetType.mono(size: 11))
                                    .foregroundColor(theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geo in
            Color.clear.preference(key: OdinPaneScrollKey.self, value: OdinPaneScroll(
                offset: -geo.frame(in: .named(Self.paneScrollSpace)).minY,
                contentHeight: geo.size.height))
        })
    }

    /// Bottom fade of the findings box: a gradient mask while text is cut off below, a plain mask otherwise.
    @ViewBuilder
    private func paneFade(boxHeight: CGFloat) -> some View {
        if OdinDecisionPaneMetrics.moreBelow(offset: paneScroll.offset, boxHeight: boxHeight, contentHeight: paneScroll.contentHeight) {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 1 - OdinDecisionPaneMetrics.fadeHeight / boxHeight),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        } else {
            Color.black
        }
    }

    /// One underline-tab of the QUESTION / ODIN FOUND switch.
    private func paneButton(_ title: String, active: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundColor(theme.muted)
                .padding(.bottom, 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(active ? theme.accent : Color.clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Options pane

    /// The 262 pt column: one radio row per option, then the send button and the store's error line.
    private func optionsPane(_ d: FleetDecision) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(d.options, id: \.id) { option in
                optionRow(d, option)
            }
            sendButton(d)
        }
        .frame(width: 262, alignment: .leading)
    }

    /// One answer choice with its radio and Odin's own `MY PICK` tag.
    private func optionRow(_ d: FleetDecision, _ option: OdinOption) -> some View {
        let selected = picked[key(d)] == option.id
        return Button {
            picked[key(d)] = option.id
        } label: {
            HStack(spacing: 8) {
                if selected {
                    ZStack {
                        Circle()
                            .strokeBorder(theme.accent, lineWidth: 1.5)
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 4.5, height: 4.5)
                    }
                    .frame(width: 11, height: 11)
                } else {
                    Circle()
                        .strokeBorder(theme.dim, lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                }
                Text(option.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if option.pick {
                    Text("MY PICK")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(theme.accent)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? theme.accent.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selected ? theme.accent : theme.pillBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The full-width send button plus the store's error line under it.
    private func sendButton(_ d: FleetDecision) -> some View {
        let sending = sendingJob == d.job
        let on = picked[key(d)] != nil && !sending
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                guard let pickedID = picked[key(d)],
                      let option = d.options.first(where: { $0.id == pickedID }) else { return }
                onSend(d, option)
            } label: {
                Text(sending ? "Sending…" : "Send decision")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundColor(on ? theme.panelTop : theme.off)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? theme.accent : theme.barTrack)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!on)

            if let error {
                Text(error)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.hotText)
                    .lineLimit(2)
                    .padding(.top, 6)
            }
        }
    }
}
