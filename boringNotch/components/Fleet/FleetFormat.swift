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

    /// A response-map agent's activity detail line. The alert outranks everything: a lane with an
    /// open decision reads "Needs you" whatever its state. Then a busy lane with its own reading
    /// shows `speedDetail` ("39 tok/s") before the job-count branch. Otherwise busy lanes show their
    /// job count (or "Working" while busy with no reported jobs), idle lanes "Idle", offline lanes
    /// "Offline" (deliberately short: at 11 pt the map's column truncates anything longer).
    static func responseDetail(_ lane: FleetLane) -> String {
        if lane.hasOpenDecision { return "Needs you" }
        if lane.probeFailed && lane.state != .offline { return "Down" }
        if let speed = speedDetail(lane) { return speed }
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

    // MARK: - decision

    /// Odin's reason in plain words: "repeat_finding" -> "same problem came back",
    /// "no_progress" -> "fixes not reducing problems", "round_limit" -> "<round> fix
    /// rounds used" ("round limit reached" when round is nil); nil/unknown ->
    /// "decision needed".
    static func decisionReason(_ reason: String?, round: Int?) -> String {
        switch reason {
        case "repeat_finding": return "same problem came back"
        case "product_choice": return "product choice"
        case "no_progress": return "fixes not reducing problems"
        case "round_limit":
            guard let round else { return "round limit reached" }
            return "\(round) fix rounds used"
        case "no_commit": return "fix round, no new commit"
        case "qa_skipped": return "review could not run"
        case "watchdog_stalled": return "job stuck after restart"
        default: return "decision needed"
        }
    }

    // MARK: - case jobs

    /// A job with no commit for longer than this reads amber.
    static let commitStaleMinutes = 60

    /// The watchdog badge's colour family: amber for a nudge or restart, red for a stuck job.
    enum CaseJobBadgeLevel: Equatable { case amber, red }

    struct CaseJobBadge: Equatable {
        var text: String
        var level: CaseJobBadgeLevel
    }

    /// One running Case job as a single line: the name, `2/5`, `12m` and a badge when the watchdog
    /// is not ok. A field the feed leaves out leaves its part out too.
    struct CaseJobLine: Equatable {
        var name: String
        var items: String?
        var commit: String?
        var commitIsStale: Bool
        var badge: CaseJobBadge?
    }

    /// Minutes since the last commit, short: 12 -> "12m", 65 -> "1h05m", 1500 -> "1d". nil -> nil.
    static func commitAge(minutes: Int?) -> String? {
        guard let minutes else { return nil }
        let m = max(0, minutes)
        if m < 60 { return "\(m)m" }
        if m < 1440 { return "\(m / 60)h" + String(format: "%02d", m % 60) + "m" }
        return "\(m / 1440)d"
    }

    /// The watchdog's badge: nudged -> NUDGED, restarted -> RESTART (amber), escalated -> STUCK (red).
    /// ok, none, missing or an unknown state -> no badge.
    static func caseJobBadge(_ watchdog: CaseJobWatchdog?) -> CaseJobBadge? {
        switch watchdog?.state {
        case "nudged": return CaseJobBadge(text: "NUDGED", level: .amber)
        case "restarted": return CaseJobBadge(text: "RESTART", level: .amber)
        case "escalated": return CaseJobBadge(text: "STUCK", level: .red)
        default: return nil
        }
    }

    static func caseJobLine(_ job: CaseJob) -> CaseJobLine {
        var items: String?
        if let total = job.itemsTotal, total > 0 {
            items = "\(min(max(0, job.itemsPassed ?? 0), total))/\(total)"
        }
        return CaseJobLine(name: job.job,
                           items: items,
                           commit: commitAge(minutes: job.minutesSinceCommit),
                           commitIsStale: (job.minutesSinceCommit ?? 0) > commitStaleMinutes,
                           badge: caseJobBadge(job.watchdog))
    }

    /// The decision detail's proof readout: "proof 2/4", plus "1 blocking" while any item blocks.
    struct CaseJobProofLine: Equatable {
        var text: String
        var blocking: String?
    }

    static func proofLine(_ proof: CaseJobProof?) -> CaseJobProofLine? {
        guard let proof, let total = proof.total, total > 0 else { return nil }
        let blocking = (proof.blocking ?? 0) > 0 ? "\(proof.blocking ?? 0) blocking" : nil
        return CaseJobProofLine(text: "proof \(min(max(0, proof.proven ?? 0), total))/\(total)", blocking: blocking)
    }

    /// The proof line for a decision's job, when the jobs feed knows that job.
    static func decisionProof(_ decision: FleetDecision, jobs: [CaseJob]) -> CaseJobProofLine? {
        guard let name = decision.job, !name.isEmpty else { return nil }
        return proofLine(jobs.first { $0.job == name }?.proof)
    }

    /// Odin's round limit, as the contract's `round r of 4` suffix reads it.
    static let odinRoundLimit = 4

    /// The ODIN tab's chip: nil for none, "1 ACTION NEEDED", "3 ACTIONS NEEDED".
    static func actionNeededLabel(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 ACTION NEEDED" : "\(count) ACTIONS NEEDED"
    }

    /// One open decision's chip: "ciri-skill-trim #9"; job-only or PR-only reads fine, `unknown`
    /// when neither is reported.
    static func decisionChip(_ decision: FleetDecision) -> String {
        var parts: [String] = []
        if let job = decision.job?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty {
            parts.append(job)
        }
        if let pr = decision.pr { parts.append("#\(pr)") }
        return parts.isEmpty ? unknown : parts.joined(separator: " ")
    }

    /// Why Odin stopped, as the ODIN tab's orange line: `decisionReason` plus " · round r of 4"
    /// while a round is reported and the reason is not `round_limit` (which already names it).
    static func decisionWhy(_ decision: FleetDecision) -> String {
        let reason = decisionReason(decision.reason, round: decision.round)
        if let round = decision.round, decision.reason != "round_limit" {
            return "\(reason) · round \(round) of \(odinRoundLimit)"
        }
        return reason
    }

    /// The question the PM asks: `question` (trimmed, non-empty), else
    /// "Odin stopped: <reason in words>. How do we go on?".
    static func decisionQuestion(_ decision: FleetDecision) -> String {
        if let question = decision.question?.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            return question
        }
        return "Odin stopped: \(decisionReason(decision.reason, round: decision.round)). How do we go on?"
    }

    /// The strip's counter: "1 open" for one, otherwise "<index + 1> of <count>" clamped.
    static func decisionProgress(index: Int, count: Int) -> String {
        guard count > 1 else { return "1 open" }
        let current = min(max(index + 1, 1), count)
        return "\(current) of \(count)"
    }

    /// The PR to open from the ODIN tab, or nil while the entry names no repo or no PR:
    /// "https://github.com/<repo>/pull/<pr>".
    static func decisionPullRequestURL(_ decision: FleetDecision) -> URL? {
        guard let repo = decision.repo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repo.isEmpty, let pr = decision.pr else { return nil }
        return URL(string: "https://github.com/\(repo)/pull/\(pr)")
    }

    /// The tab strip's health line: "0 tasks · 7/7 linked · All clear" (reuses `linked(_:of:)` and
    /// `status(_:)`; "1 task" is singular).
    static func healthLine(runningTasks: Int, linked: Int, of total: Int, critical: Int, down: Int = 0) -> String {
        let tasks = runningTasks == 1 ? "1 task" : "\(runningTasks) tasks"
        return "\(tasks) · \(FleetFormat.linked(linked, of: total)) · \(status(critical, down: down))"
    }

    // MARK: - step

    /// nil or blank -> "Not reported"; otherwise the whitespace-trimmed step.
    static func step(_ step: String?) -> String {
        guard let step else { return "Not reported" }
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not reported" : trimmed
    }

    // MARK: - status

    /// 0 -> "All clear"; 1 -> "1 critical"; n -> "n critical". Offline machines (critical) win over
    /// machines that are on but whose model does not answer ("n down").
    static func status(_ criticalCount: Int, down: Int = 0) -> String {
        if criticalCount > 0 { return "\(criticalCount) critical" }
        if down > 0 { return "\(down) down" }
        return "All clear"
    }

    // MARK: - closed alert

    /// The closed row's optional second item: "3 critical" (machines offline) wins, then "2 down"
    /// (machines on, model not answering); nil when all is well, so the row stays "1 working".
    static func closedAlert(critical: Int, down: Int) -> String? {
        critical > 0 || down > 0 ? status(critical, down: down) : nil
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

    // MARK: - rings

    /// The level a footer ring's reading falls in: under 70 % `ok`, 70-89 % `hot`, 90 % and over
    /// `alert`; nil when there is no reading (that ring then keeps its track only).
    static func ringLevel(_ percent: Int?) -> FleetRingLevel? {
        guard let percent else { return nil }
        if percent >= 90 { return .alert }
        if percent >= 70 { return .hot }
        return .ok
    }

    /// A ring's number as its cluster prints it: "88", or `unknown` ("—") when the machine
    /// reports none.
    static func ringValueText(_ percent: Int?) -> String {
        guard let percent else { return unknown }
        return "\(percent)"
    }

    /// The cluster's headline: the highest of the three readings with its type ("RAM 88"), or
    /// `unknown` ("—") when the machine reports nothing. Ties keep ring order (cpu, gpu, ram).
    static func ringHeadline(_ host: FleetHostReading) -> String {
        guard let hottest = host.hottest else { return unknown }
        return "\(hottest.kind.title) \(ringValueText(hottest.value))"
    }

    /// The cluster's one sentence, shared by the hover tooltip and the VoiceOver label:
    /// "frank: CPU 13% · GPU 94% · RAM 86%"; a reading the machine does not report is `unknown`.
    static func ringDetail(_ host: FleetHostReading) -> String {
        let parts = FleetRingKind.allCases.map { kind -> String in
            let value = host.value(kind).map { "\($0)%" } ?? unknown
            return "\(kind.title) \(value)"
        }
        return "\(host.label): " + parts.joined(separator: " · ")
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

    // MARK: - speed

    /// The last non-nil trend reading: what an idle header shows dimmed. nil when the trend has none.
    static func speedLastValue(_ speed: FleetSpeed?) -> Double? {
        speed?.trend.compactMap { $0 }.last
    }

    /// The header's number: the current decode speed, else the last trend value, else `unknown` ("—").
    /// Whole numbers only, so the header never reflows on a decimal.
    static func speedNumberText(_ speed: FleetSpeed?) -> String {
        guard let value = speed?.current ?? speedLastValue(speed) else { return unknown }
        return "\(Int(value.rounded()))"
    }

    /// True while the feed reports no current speed (the header then dims the number and adds "idle").
    static func speedIsIdle(_ speed: FleetSpeed?) -> Bool {
        speed?.current == nil
    }

    /// A busy lane's own writing speed: "39 tok/s". nil unless the lane is busy and carries a reading.
    /// Deliberately short: the map's detail budget is 54 pt at 11 pt with the job badge, and
    /// "Writing · 38 tok/s" measures ~125 pt and would truncate.
    static func speedDetail(_ lane: FleetLane) -> String? {
        guard lane.state == .busy, let speed = lane.speed else { return nil }
        return "\(Int(round(speed))) tok/s"
    }

    /// The contract's fleet speed: the median of the devices that report one - never a sum, so one
    /// writer's own speed is the fleet's. Even counts average the two middle values; nil when nothing
    /// reports (the header then keeps its "—").
    static func medianSpeed(_ speeds: [Double?]) -> Double? {
        let values = speeds.compactMap { $0 }.sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count % 2 == 1 {
            return values[middle]
        }
        return (values[middle - 1] + values[middle]) / 2
    }

    // MARK: - selection

    /// The selection an open list of `count` decisions can hold: `index` clamped into range, and 0 for an
    /// empty list. Answering one decision shrinks the list under the index, so every reader (the current
    /// decision, the chip highlight and the ‹ › steppers) must go through this instead of the raw index.
    static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
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
    /// ("Offline", "2 jobs", a writing lane's "39 tok/s" at 54.4 pt on the system monospaced font).
    /// 92 pt is the mock's lane width; it is also the smallest floor that keeps "39 tok/s" inside the
    /// badged detail budget.
    static let responseMapColumnWidth: CGFloat = 92
    /// The whole response map: two columns, the 60 pt case box and the two wire gaps.
    static let responseMapWidth: CGFloat = 292
    /// One response-map row's two text lines: the 12 pt name line (≈14.3 pt), the 1 pt stack
    /// gap and the 11 pt monospaced status line (≈13.1 pt), so the pair needs ≈28.4 pt; 30 pt
    /// keeps ≈1.6 pt of air. The map also carries `responseMapHeight(rows:)` as its own floor.
    static let responseMapMinRowHeight: CGFloat = 30
    /// The response map's grid for `rows` agent rows (the grid is as tall as its longer column):
    /// the map's floor, which the opened panel is tall enough to hold.
    static func responseMapHeight(rows: Int) -> CGFloat {
        return CGFloat(max(1, rows)) * responseMapMinRowHeight
    }
    /// The opened Fleet column is 300 pt, the height the notch always had: the one-line header and
    /// the tab strip that carries the health text free the room the map's four rows need, so the
    /// notch does not grow.
    static let fleetSectionHeight: CGFloat = 300
    /// The closed-notch row: one line per side ("2 working" or "2 working · 1 down" / the speed).
    /// Both sides are as wide as the wider text, so the camera gap stays centred and the notch is
    /// only as wide as it needs to be. This cap holds the longest left line in 11 pt monospaced
    /// width (a safe upper bound for the 12 pt proportional "working").
    static let closedRowTextWidth: CGFloat = 160
    static var closedRowSideWidth: CGFloat { closedRowTextWidth }
    /// One side's width: the wider of the two texts, never past the cap.
    static func closedRowSide(left: CGFloat, right: CGFloat) -> CGFloat {
        min(closedRowSideWidth, max(left, right))
    }
    /// The current-work column: 604 pt section, less the 18 pt lead and 1 pt rule, the 292 pt map and
    /// the 20 + 1 + 20 pt around the hairline.
    static let workColumnWidth: CGFloat = 252
    /// Running Case jobs get at most this many heartbeat lines; each line is one 12 pt row.
    static let caseJobLineLimit = 2
    static let caseJobLineHeight: CGFloat = 16
    /// The least width the job name keeps; the items, age and badge take the rest.
    static let caseJobMinNameWidth: CGFloat = 90
    /// Gap between the parts of a job line.
    static let caseJobLineSpacing: CGFloat = 6
    /// The height the work column has: the 300 pt panel less header, tabs, top pad, footer and gaps.
    static let workColumnHeight: CGFloat = 186
    /// What the work column stacks: head row, one preview job (3 lines, label up to 2) and the more link.
    static let workHeadHeight: CGFloat = 24
    static let workPreviewHeight: CGFloat = 65
    static let workPreviewGap: CGFloat = 15
    static let workMoreLinkHeight: CGFloat = 15
    /// How many preview jobs sit under the heartbeat lines: two as before, one while lines show.
    static func previewLimit(caseJobLines: Int) -> Int { caseJobLines > 0 ? 1 : 2 }
    /// The column's content height for that many heartbeat lines and the matching previews.
    static func workContentHeight(caseJobLines: Int, previews: Int, moreLink: Bool) -> CGFloat {
        let lines = CGFloat(caseJobLines) * caseJobLineHeight + (caseJobLines > 0 ? 8 : 0)
        let rows = CGFloat(previews) * workPreviewHeight + CGFloat(max(0, previews - 1)) * workPreviewGap
        return workHeadHeight + lines + rows + (moreLink ? workMoreLinkHeight : 0)
    }
    /// A pulsing status dot breathes by size, never by opacity: dimming an alert dot would drop it
    /// under the 3:1 dot floor. The busy cells keep their own dim pulse.
    static let alertPulseScale: CGFloat = 1.35
}
