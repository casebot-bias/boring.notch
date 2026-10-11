//
//  FleetFormat.swift
//  boringNotch
//
//  Pure formatting/normalising helpers for the Fleet panel: response map,
//  signals, peaks and current work.
//  Depends only on Foundation and the model types (FleetLane).
//
import Foundation

enum FleetFormat {

    static let unknown = "—"

    // MARK: - percent

    /// 72 -> "72%"; 86.34 -> "86%" (rounds half away from zero).
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    // MARK: - fleetOutput

    /// Big total token-rate readout: nil -> "—"; 401.4 -> "401" (rounds half away from zero).
    static func fleetOutput(_ value: Double?) -> String {
        guard let value else { return unknown }
        return "\(Int(value.rounded()))"
    }

    // MARK: - jobs

    /// n <= 0 -> "idle"; 1 -> "1 job"; 2 -> "2 jobs"
    static func jobs(_ n: Int) -> String {
        guard n > 0 else { return "idle" }
        return n == 1 ? "1 job" : "\(n) jobs"
    }

    // MARK: - jobBadge

    /// n <= 0 -> nil; 4 -> "04"; 12 -> "12"
    static func jobBadge(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        return String(format: "%02d", n)
    }

    // MARK: - responseDetail

    /// A response-map agent's activity detail line: busy lanes show their job count (or
    /// "Working" while busy with no reported jobs), idle lanes "Idle", offline lanes
    /// "Offline" (deliberately short: at 11 pt the map's column truncates anything longer).
    /// A lane with an open decision shows `decisionDetail` instead.
    static func responseDetail(_ lane: FleetLane) -> String {
        switch lane.state {
        case .busy:
            let count = lane.jobs.count
            return count > 0 ? jobs(count) : "Working"
        case .idle:
            return "Idle"
        case .offline:
            return "Offline"
        }
    }

    /// The detail line of a lane with an open decision: the pull request it wants a call on, or
    /// `"No PR"` when the decision was recorded without one. The map's detail budget is only 54 pt
    /// at `FleetPanelMetrics.minTextSize`, so the fallback has to stay as short as the label it
    /// stands in for ("Needs decision" measured ~95 pt and truncated).
    static func decisionDetail(_ lane: FleetLane) -> String {
        guard let pr = lane.decisions.first?.pr else { return "No PR" }
        return "PR #\(pr)"
    }

    // MARK: - decision

    /// Odin's reason in plain words: "repeat_finding" -> "same problem came back",
    /// "no_progress" -> "fixes not reducing problems", "round_limit" -> "<round> fix
    /// rounds used" ("round limit reached" when round is nil); nil/unknown ->
    /// "decision needed".
    static func decisionReason(_ reason: String?, round: Int?) -> String {
        switch reason {
        case "repeat_finding": return "same problem came back"
        case "no_progress": return "fixes not reducing problems"
        case "round_limit":
            guard let round else { return "round limit reached" }
            return "\(round) fix rounds used"
        default: return "decision needed"
        }
    }

    /// Odin's alert subject: "monitor-landscape-scale · PR #4"; a job-only or
    /// PR-only subject reads fine; `unknown` when neither is reported.
    static func decisionSubject(_ decision: FleetDecision) -> String {
        var parts: [String] = []
        if let job = decision.job?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty {
            parts.append(job)
        }
        if let pr = decision.pr { parts.append("PR #\(pr)") }
        return parts.isEmpty ? unknown : parts.joined(separator: " · ")
    }

    /// "last known" while the fleet feed is unreachable — the decisions on screen come from
    /// the last successful poll — and nil while it is reachable.
    static func decisionStaleness(_ isReachable: Bool) -> String? {
        isReachable ? nil : "last known"
    }

    /// The alert's open-decision count label: nil for none or one, "<count> open" above that.
    static func decisionCountLabel(_ count: Int) -> String? {
        count > 1 ? "\(count) open" : nil
    }

    // MARK: - step

    /// nil or blank -> "Not reported"; otherwise the whitespace-trimmed step.
    static func step(_ step: String?) -> String {
        guard let step else { return "Not reported" }
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not reported" : trimmed
    }

    // MARK: - status

    /// 0 -> "All clear"; 1 -> "1 critical"; n -> "n critical"
    static func status(_ criticalCount: Int) -> String {
        guard criticalCount > 0 else { return "All clear" }
        return "\(criticalCount) critical"
    }

    // MARK: - linked

    /// linked -> "6/6 linked" style counter.
    static func linked(_ linked: Int, of total: Int) -> String {
        "\(linked)/\(total) linked"
    }

    // MARK: - fraction

    /// Clamped 0...1 of percent/100.
    static func fraction(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }

    // MARK: - isHighPressure

    /// >= 95
    static func isHighPressure(_ percent: Double) -> Bool {
        percent >= 95
    }

    // MARK: - fleetBaseURL

    /// Normalises `Defaults[.fleetBaseURL]` into the URL used to reach the fleet:
    /// surrounding whitespace trimmed, every trailing slash dropped, `nil` when
    /// nothing is left. Shared by FleetStore polling and the "Open Fleet" link.
    static func fleetBaseURL(_ raw: String) -> URL? {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        guard !base.isEmpty else { return nil }
        return URL(string: base)
    }
}
/// Widths the fleet panel's fixed blocks must give their text so no label truncates. The response
/// map and the closed-notch row read these; the tests measure the real strings at `minTextSize`
/// against them. Foundation/CoreGraphics only, so it compiles into the app and the test target.
enum FleetPanelMetrics {
    /// The smallest text size any fleet view may use.
    static let minTextSize: CGFloat = 11
    /// The alert heading's size (the strip's "ODIN NEEDS DECISION"). The alert's words draw in
    /// `hot`, an accent colour held to 4.5:1, a floor that only applies at 12 pt or more — so the
    /// heading has to be at least this large for its own colour to be allowed.
    static let alertHeadingTextSize: CGFloat = 12
    /// A response-map row's fixed furniture: signal square, its spacing, the trailing spacer and
    /// the job badge. Everything left in the column is the text budget.
    static let responseMapRowOverhead: CGFloat = 30
    /// Response-map column floor: `responseMapRowOverhead` plus room for the longest detail line
    /// ("Offline", "2 jobs").
    static let responseMapColumnWidth: CGFloat = 84
    /// The whole response map: two columns, the 60 pt case box and the two wire gaps.
    static let responseMapWidth: CGFloat = 292
    /// One response-map row's two text lines: the 12 pt name line, the 1 pt stack gap and the
    /// 11 pt monospaced status line. A 12 pt system line measures ≈14.3 pt and an 11 pt
    /// monospaced line ≈13.1 pt, so the pair needs ≈28.4 pt; 31 pt leaves ≈2.6 pt of air. The map
    /// used to divide whatever height the panel gave it by its rows, which left each of its four
    /// rows ~24 pt and printed every status line over the next agent's name.
    static let responseMapMinRowHeight: CGFloat = 31
    /// The response map's grid for `rows` agent rows (the grid is as tall as its longer column):
    /// the map's floor, which the opened panel is tall enough to hold.
    static func responseMapHeight(rows: Int) -> CGFloat {
        return CGFloat(max(1, rows)) * responseMapMinRowHeight
    }
    /// Everything the opened Fleet column draws outside the map's four rows: the header, its
    /// hairline, the health row, Odin's decision strip, the five 10 pt row gaps, the footer and
    /// the map's own "RESPONSE MAP" label. Measured from the rendered panel.
    static let fleetSectionChromeHeight: CGFloat = 206
    /// The opened Fleet column: its fixed rows plus the map's four rows. The sizing module opens
    /// the notch to exactly this height and the section view frames itself at it, so window and
    /// content can never disagree.
    static let fleetSectionHeight: CGFloat = fleetSectionChromeHeight + responseMapHeight(rows: 4)
    /// The closed-notch row: the mini map's width, the gap after it, and the text budget.
    static let closedRowMapWidth: CGFloat = 46
    static let closedRowTextWidth: CGFloat = 72
    static var closedRowSideWidth: CGFloat { closedRowMapWidth + 10 + closedRowTextWidth }
    /// A pulsing status dot breathes by size, never by opacity: dimming an alert dot would drop it
    /// under the 3:1 dot floor. The busy cells keep their own dim pulse.
    static let alertPulseScale: CGFloat = 1.35
}
