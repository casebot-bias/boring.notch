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

    /// A response-map agent's detail line: busy lanes show their job count (or
    /// "Working" while busy with no reported jobs), idle lanes "Idle", offline
    /// lanes "Offline". Offline is deliberately short: at 11 pt the map's column
    /// truncates anything longer.
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
    /// A response-map row's fixed furniture: signal square, its spacing, the trailing spacer and
    /// the job badge. Everything left in the column is the text budget.
    static let responseMapRowOverhead: CGFloat = 30
    /// Response-map column floor: `responseMapRowOverhead` plus room for the longest detail line
    /// ("Offline", "2 jobs").
    static let responseMapColumnWidth: CGFloat = 84
    /// The whole response map: two columns, the 60 pt case box and the two wire gaps.
    static let responseMapWidth: CGFloat = 292
    /// The closed-notch row: the mini map's width, the gap after it, and the text budget.
    static let closedRowMapWidth: CGFloat = 46
    static let closedRowTextWidth: CGFloat = 72
    static var closedRowSideWidth: CGFloat { closedRowMapWidth + 10 + closedRowTextWidth }
}
