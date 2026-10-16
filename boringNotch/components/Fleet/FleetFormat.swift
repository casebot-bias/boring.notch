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

    /// The unit a fleet speed readout prints. The API's `speed.current` is the sum of the devices'
    /// rates, so a number that came from a payload's speed block is labelled as a total; the notch's
    /// own median stand-in - used only when neither feed reports a block - is one writer's rate, and a
    /// dash is not a total either.
    static func tokenRateUnit(total: Bool) -> String {
        total ? " tok/s total" : " tok/s"
    }

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

    /// The collapsed notch row's right side: a speed reading (number and unit) or a job count (number and
    /// noun). The speed reading goes through three states, in this order: the live sum bright while a model
    /// writes; the last measured value dimmed with " · idle" while the feed's clock says the writing just
    /// stopped (`speedIdleGraceSec`); then a dimmed zero with no idle marker of its own. The sparkline the
    /// row draws left of the number carries the "when did anything last write" story (see `closedRightReading`).
    /// The unit ladder has no "total" suffix - the open panel's header keeps the fuller
    /// "tok/s total" (`tokenRateUnit(total:)`) where there is room.
    struct FleetClosedRightReading: Equatable {
        var number: String
        var unit: String
        var dim: Bool
    }

    /// The row's speed side, in three states. While the feed reports a current reading the live sum shows
    /// bright, with the rate unit that fits. Once it stops, the last value it measured stays dimmed WITH
    /// " · idle" for `speedIdleGraceSec` after `speed.lastAt` (`now` defaults to the clock, so callers
    /// without one still get the honest reading): the kept number is announced as a remembered one. Past
    /// that window the side is a dimmed "0" with no idle marker - the zero needs none. A stale number is
    /// worse than an honest zero. Only when no speed was ever measured do running jobs stand in, bright,
    /// and never as a total; no speed and no jobs leaves the side empty.
    static func closedRightReading(speed: FleetSpeed?, jobs: Int, now: Date = Date()) -> FleetClosedRightReading? {
        if let speed, speed.current != nil || speedLastValue(speed) != nil {
            let number: String
            let idle: Bool
            if let current = speed.current {
                number = "\(Int(current.rounded()))"
                idle = false
            } else if speedKeepsLastValue(speed, now: now), let last = speedLastValue(speed) {
                number = "\(Int(last.rounded()))"
                idle = true
            } else {
                number = "0"
                idle = false
            }
            return FleetClosedRightReading(number: number,
                                           unit: closedSpeedUnit(number: number, idle: idle),
                                           dim: speedIsIdle(speed))
        }
        if jobs > 0 {
            return FleetClosedRightReading(number: "\(jobs)",
                                           unit: jobs == 1 ? " job" : " jobs",
                                           dim: false)
        }
        return nil
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

    // MARK: - case box

    /// The case box's state line: "Working" while the origin runs model work, "Offline" when it is
    /// unreachable. An idle origin whose dashboard is waiting on a long test or build says what it is
    /// waiting on - the oldest run's "Testing"/"Building"/"Running" - because the machine is doing
    /// something the owner cares about even with no model writing. Otherwise the idle box is plain
    /// "Online". Model work outranks a run: busy is busy whatever the run list says.
    static func caseBoxState(_ lane: FleetLane) -> String {
        switch lane.state {
        case .busy: return "Working"
        case .idle:
            guard let oldest = oldestToolRun(lane.toolRuns) else { return "Online" }
            return capitalized(toolRunVerb(oldest))
        case .offline: return "Offline"
        }
    }

    /// True while the state line earns the accent: the origin is busy, or idle with its own tool runs
    /// (an idle box merely "Online" is a status, not activity, and stays in the plain colour).
    static func caseBoxStateIsActive(_ lane: FleetLane) -> Bool {
        switch lane.state {
        case .busy: return true
        case .idle: return !lane.toolRuns.isEmpty
        case .offline: return false
        }
    }

    /// The age line under an idle box's "Testing": the oldest run's age, nil for anything else - the
    /// age only reads under a run word, so busy/offline/idle-without-runs boxes show none.
    static func caseBoxToolRunAge(_ lane: FleetLane) -> String? {
        guard lane.state == .idle, let oldest = oldestToolRun(lane.toolRuns) else { return nil }
        return toolRunAge(oldest)
    }

    /// "testing" -> "Testing": the box's state line starts a sentence, the verbs inside the row don't.
    private static func capitalized(_ word: String) -> String {
        word.isEmpty ? word : word.prefix(1).uppercased() + word.dropFirst()
    }

    /// The case box's job-count line: "1 job" / "2 jobs" while the origin is busy with reported jobs,
    /// nil otherwise - an idle or offline box shows no count, and a busy box with no reported jobs keeps
    /// "Working" alone.
    static func caseBoxJobs(_ lane: FleetLane) -> String? {
        guard lane.state == .busy else { return nil }
        let count = lane.jobs.count
        return count > 0 ? jobs(count) : nil
    }

    // MARK: - tool runs

    /// A run's elapsed seconds as the few characters the box and the closed row have: 45 -> "45s",
    /// 600 -> "10m", 5400 -> "1h30m"; nil when the dashboard reports no elapsed time at all - a run
    /// that never reported its clock has no age to show, and guessing one would be a lie.
    static func toolRunAge(_ run: ToolRun) -> String? {
        guard let elapsed = run.elapsedSec else { return nil }
        let s = max(0, elapsed)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h" + String(format: "%02d", (s % 3600) / 60) + "m"
    }

    /// The run that has been going longest: the one the box names, because it is what the machine is
    /// actually waiting on. A run that reports no elapsed time sorts after every run that does; ties
    /// keep the feed's order. An empty list has none.
    static func oldestToolRun(_ runs: [ToolRun]) -> ToolRun? {
        var oldest: ToolRun?
        for run in runs {
            guard let best = oldest else { oldest = run; continue }
            if (run.elapsedSec ?? Int.min) > (best.elapsedSec ?? Int.min) { oldest = run }
        }
        return oldest
    }

    /// The run's kind as the word the closed row and the case box print: "test" -> "testing",
    /// "build" -> "building"; a kind the dashboard invented still reads honestly as "running".
    static func toolRunVerb(_ run: ToolRun) -> String {
        switch run.kind {
        case "test": return "testing"
        case "build": return "building"
        default: return "running"
        }
    }

    /// One run as the current-work list prints it: "monitor-platform-split · smoke.cjs · 10m". A part
    /// the API leaves out leaves its segment out too; a run with nothing to say is the unknown dash.
    static func toolRunLine(_ run: ToolRun) -> String {
        var parts: [String] = []
        if let job = run.job?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty {
            parts.append(job)
        }
        if let label = run.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            parts.append(label)
        }
        if let age = toolRunAge(run) { parts.append(age) }
        guard !parts.isEmpty else { return unknown }
        return parts.joined(separator: " · ")
    }

    /// The closed row's left side while nobody works: a count (nil when one run speaks for itself),
    /// the verb and the age that carry it.
    struct FleetClosedToolRun: Equatable {
        var number: String?
        var word: String
        var age: String?
    }

    /// The row's words for the runs Case is waiting on: ONE run names itself ("testing · 10m", no
    /// number to prefix); SEVERAL cannot be named by one, so they count ("2 running"); none is nil,
    /// which is what keeps a bare "0 working" out of the row.
    static func closedToolRun(_ runs: [ToolRun]) -> FleetClosedToolRun? {
        if runs.count == 1, let run = runs.first {
            return FleetClosedToolRun(number: nil, word: toolRunVerb(run), age: toolRunAge(run))
        }
        guard !runs.isEmpty else { return nil }
        return FleetClosedToolRun(number: "\(runs.count)", word: "running", age: nil)
    }

    /// The closed row's sparkline feed: exactly `count` readings, oldest first, the trend's nils read
    /// as 0. A young trend gets front zeros, so the line keeps its right-aligned "now" and a flat
    /// stretch means nobody wrote, not that the feed was short.
    static func sparklineSeries(_ trend: [Double?], count: Int = 60) -> [Double] {
        let width = max(0, count)
        let values = trend.suffix(width).map { $0 ?? 0 }
        guard values.count < width else { return values }
        return Array(repeating: 0, count: width - values.count) + values
    }

    /// Seconds between the speed feed's last writing moment (`speed.lastAt`, ISO8601 with or without
    /// fractional seconds) and `now`; nil when the feed names no time or the stamp does not parse -
    /// the grace window must stay honest, so an unparsable clock is "no clock", not "long idle".
    static func speedIdleSec(_ speed: FleetSpeed?, now: Date) -> Double? {
        guard let lastAt = speed?.lastAt, let written = fleetDate(lastAt) else { return nil }
        return now.timeIntervalSince(written)
    }

    /// How long after the last writing moment the closed row still prints the last measured number:
    /// long enough that a paused answer or a poll gap does not blink the row through zero.
    static let speedIdleGraceSec: Double = 30

    /// True while the row may keep its last measured speed: with no clock to judge by (`speedIdleSec`
    /// nil, and the feed stays trusted) or inside `speedIdleGraceSec` of the last writing moment.
    static func speedKeepsLastValue(_ speed: FleetSpeed?, now: Date) -> Bool {
        guard let idleSec = speedIdleSec(speed, now: now) else { return true }
        return idleSec <= speedIdleGraceSec
    }

    /// The fleet feed's ISO8601 timestamps: the API stamps them with milliseconds
    /// ("2026-10-13T23:41:59.737Z"), so that form parses first and the plain one follows.
    private static let fleetFractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fleetPlainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func fleetDate(_ stamp: String) -> Date? {
        let trimmed = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return fleetFractionalDateFormatter.date(from: trimmed) ?? fleetPlainDateFormatter.date(from: trimmed)
    }

    // MARK: - speed

    /// The last speed anyone measured: the speed block's own `lastValue` when the API kept one (the
    /// activity feed keeps it while nothing writes), else the newest non-nil trend reading. What an
    /// idle header shows dimmed; nil when neither exists.
    static func speedLastValue(_ speed: FleetSpeed?) -> Double? {
        if let lastValue = speed?.lastValue { return lastValue }
        return speed?.trend.compactMap { $0 }.last
    }

    /// The header's number: the current decode speed, else the last trend value, else `unknown` ("—").
    /// Whole numbers only, so the header never reflows on a decimal.
    static func speedNumberText(_ speed: FleetSpeed?) -> String {
        guard let value = speed?.current ?? speedLastValue(speed) else { return unknown }
        return "\(Int(value.rounded()))"
    }

    /// True when the number and unit together stay inside the closed row's text budget: the row also
    /// draws the speed sparkline left of the number, so its width plus the gap to the number comes out
    /// of the same budget. The number measures at `FleetPanelMetrics.closedSpeedNumberSize` (medium),
    /// never narrower than the three-digit reserve (`closedNumberMinWidth`), so the fit check measures
    /// the same box the layout reserves. The unit measures at its `minTextSize`, joined by
    /// `closedSpeedSpacing`.
    static func closedSpeedFits(number: String, unit: String) -> Bool {
        FleetPanelMetrics.closedSparklineWidth + FleetPanelMetrics.closedSpeedSpacing
            + max(FleetPanelMetrics.closedNumberMinWidth,
                  FleetType.monoWidth(text: number, size: FleetPanelMetrics.closedSpeedNumberSize, weight: .medium))
            + FleetPanelMetrics.closedSpeedSpacing
            + FleetType.monoWidth(text: unit, size: FleetPanelMetrics.minTextSize)
            <= FleetPanelMetrics.closedRowTextWidth
    }

    /// The closed row's speed unit: the first candidate that fits the reading by `closedSpeedFits`,
    /// else the shortest. The row reads "tok/s" for a number short enough to fit the budget, and falls
    /// back to " t/s" when the number is too long; the open panel's header keeps the fuller "tok/s
    /// total" (`tokenRateUnit(total:)`). While `idle` every candidate carries " · idle", so the
    /// remembered value announces that the fleet stopped writing: the sparkline shows when, but the
    /// unit has to say the number is a kept one, not a live one. The idle suffix rides on every
    /// candidate, so the row's own budget only ever trims the rate words in front of it. The reading
    /// must stay inside the closed row's text budget so it neither truncates nor widens the notch.
    static func closedSpeedUnit(number: String, idle: Bool = false) -> String {
        let rates = [" tok/s", " t/s"]
        let units = idle ? rates.map { $0 + " · idle" } : rates
        return units.first { closedSpeedFits(number: number, unit: $0) } ?? units[units.count - 1]
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
    /// The closed fleet bar's height where the display has no camera cutout, as a share of the closed
    /// notch's own height. That closed notch is as tall as the display's menu bar (30 pt on the job
    /// machine's screen), which left the fleet row hanging well below it; there the bar draws in 70 %
    /// of it (30 pt -> 21 pt). A display with a hardware notch draws the bar at the notch's own height
    /// instead - see `closedBarHeight(_:hasHardwareNotch:)`.
    static let closedBarHeightScale: CGFloat = 0.7
    /// The closed fleet bar's height for a closed notch of `closedNotchHeight` pt. Beside a hardware
    /// notch the bar is that height whole - the hardware cutout's own (38 pt on the owner's MacBook,
    /// whose `notchHeightMode` is `.matchRealNotchSize`, i.e. `safeAreaInsets.top`) - so the bar's
    /// bottom edge lines up with the notch's below and the black cutout never sticks out past the bar.
    /// A display without a cutout keeps the shorter `closedBarHeightScale` bar. The open notch and the
    /// other closed faces keep their height either way.
    static func closedBarHeight(_ closedNotchHeight: CGFloat, hasHardwareNotch: Bool) -> CGFloat {
        hasHardwareNotch ? closedNotchHeight : closedNotchHeight * closedBarHeightScale
    }
    /// The closed-notch row: one line per side ("2 working" or "2 working · 1 down" / the speed).
    /// Both sides are as wide as the wider text, so the camera gap stays centred and the notch is
    /// only as wide as it needs to be. This cap holds the longest left line in 11 pt monospaced
    /// width (a safe upper bound for the 11 pt proportional "working").
    static let closedRowTextWidth: CGFloat = 160
    /// The padding each wing gives its content (owner: 12 pt), so the text never sits on the bar's edge.
    static let closedRowSidePadding: CGFloat = 12
    /// The padding a wing gives its content on a display with a hardware notch: 6 pt, so the text
    /// sits close to the camera cutout. The camera gap carries the clearance; the wings only need to
    /// look padded, and every point of wing width is a point of bar.
    static let closedRowNotchedSidePadding: CGFloat = 6
    /// The padding a wing gives its content for the geometry it draws in: 6 pt on a notched display,
    /// 12 pt where there is no cutout to hug.
    static func closedRowWingPadding(hasHardwareNotch: Bool) -> CGFloat {
        hasHardwareNotch ? closedRowNotchedSidePadding : closedRowSidePadding
    }
    /// One wing's ceiling: the text budget plus the wider (12 pt) padding. No wing grows past it.
    /// The call site passes `closedRowWingPadding(hasHardwareNotch:)` so the actual padding adapts.
    static var closedRowSideWidth: CGFloat { closedRowTextWidth + closedRowSidePadding }
    /// Seconds the closed row's width takes to follow a content change. The reading's three-digit
    /// reserve absorbs "0" -> "147"; a longer number ("999" -> "1000"), a longer count or alert, the
    /// case's run words or the black hole's slice still move the bar, and this is the animation that
    /// carries them instead of a jump.
    static let closedRowWidthSeconds: Double = 0.3
    /// One wing's width: the wider of the two sides' content plus the padding, never past the cap.
    /// The padding comes from `closedRowWingPadding(hasHardwareNotch:)`.
    static func closedRowSide(left: CGFloat, right: CGFloat, padding: CGFloat) -> CGFloat {
        min(closedRowSideWidth, max(left, right) + padding)
    }
    /// The camera gap. A display with a hardware notch keeps the gap the cutout needs (the notch plus
    /// 5 pt of clearance per side); a display without one has no cutout to clear, so the middle is one
    /// padding wide.
    static func closedRowGap(notchWidth: CGFloat, hasHardwareNotch: Bool) -> CGFloat {
        hasHardwareNotch ? notchWidth + 10 : closedRowSidePadding
    }
    /// The closed row's whole width: two equal wings around the middle.
    static func closedRowWidth(left: CGFloat, right: CGFloat, gap: CGFloat, padding: CGFloat) -> CGFloat {
        2 * closedRowSide(left: left, right: right, padding: padding) + gap
    }
    /// The closed row's speed reading: the number at this size (medium weight), its unit at
    /// `minTextSize` after this spacing. The bar is 70 % of the closed notch only where the display has no
    /// camera cutout, so there the number drops from 20 pt to 14 pt (0.7 x 20, whose line box still fits the
    /// shorter bar) and the row's labels sit on `minTextSize`. Beside a hardware notch the bar is the notch's
    /// own height, which holds this same 14 pt number, the same 11 pt labels and the same 10 pt sparkline.
    /// The closed row draws its speed reading with these and the fit rule (`closedSpeedFits`) measures
    /// with the same numbers.
    static let closedSpeedNumberSize: CGFloat = 14
    static let closedSpeedSpacing: CGFloat = 3
    /// The speed number never draws narrower than three digits, so "0" and "147 tok/s" leave the
    /// wing - and so the whole bar - where they are.
    static let closedNumberMinDigits = 3
    /// The three-digit reserve the speed number is drawn into: `closedNumberMinDigits` zeros at
    /// `closedSpeedNumberSize` (medium mono).
    static var closedNumberMinWidth: CGFloat {
        FleetType.monoWidth(text: String(repeating: "0", count: closedNumberMinDigits),
                            size: closedSpeedNumberSize, weight: .medium)
    }
    /// The closed row's speed sparkline: the last ten minutes of trend readings drawn left of the
    /// speed number, `closedSpeedSpacing` from it. Small on purpose - it only has to show *when* the
    /// line last rose, and `closedSpeedFits` subtracts its width from the row's text budget. The
    /// width cut takes its budget from the sparkline's own width (40 -> 24 pt), the same way the
    /// height cut took its budget from the sparkline's height; 24 pt still shows the ten-minute
    /// trend, and it pays for the number's three-digit reserve (`closedNumberMinWidth`). The row
    /// draws it in every geometry (owner follow-up), and beside a camera cutout its 24 pt plus
    /// its `closedSpeedSpacing` are what keep the notched bar at 85.7 % of main's width rather
    /// than the 75 % bound.
    static let closedSparklineWidth: CGFloat = 24
    /// Short enough to sit inside the speed number's line box without pushing the row taller. Where the
    /// display has no camera cutout the height follows the bar's 70 % (0.7 x 14), so the sparkline stays
    /// inside the shorter bar; beside a hardware notch the bar is the notch's own height and the same
    /// 10 pt sparkline sits inside it.
    static let closedSparklineHeight: CGFloat = 10
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
