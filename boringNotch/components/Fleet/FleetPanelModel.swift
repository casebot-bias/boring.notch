//
//  FleetPanelModel.swift
//  boringNotch
//
//  Data model for the opened fleet panel: the `case` origin at the centre of a
//  response map, the eight agent signals (frank, claire, ciri, morpheus, dali, nova, pika, odin),
//  the current-work jobs, the fleet-wide output shown in the header and one reading per
//  machine in the footer. Foundation only (no SwiftUI) so it compiles into both the
//  app target and the test target.
//

import Foundation

/// Signal state of a node: busy, idle or offline. Offline beats busy: an offline/absent
/// machine reports .offline even when its activity device claims work. An open decision is
/// a separate dimension (`FleetLane.hasOpenDecision`), never a node state, so a lane that is
/// reviewing still counts as busy work.
enum FleetNodeState: Equatable { case busy, idle, offline }

/// One running piece of work, shown on its signal and in the current-work list.
struct FleetJob: Identifiable, Equatable {
    var key: String        // stable dedup id (ActivityItem.id)
    var pill: String       // "nova" | "case" | the delegating device id
    var label: String      // job title
    var step: String?      // ActivityItem.lastStep
    var elapsedSec: Int?
    var id: String { key }
}

/// One node of the response map: the case origin or an agent signal.
struct FleetLane: Identifiable, Equatable {
    var id: String
    var label: String
    var state: FleetNodeState
    var jobs: [FleetJob]
    /// The device's own decode speed in tokens/s; nil when the device reports none (nova: never).
    var speed: Double?
    var decisions: [FleetDecision] = []
    /// The machine is on but its activity probe failed (the feed's device `state: "error"`, e.g. its
    /// model server is switched off): the same rule the web dashboard uses for "telemetry probe failed".
    var probeFailed: Bool = false

    /// The lane's first open decision, kept for the single-decision call sites.
    var decision: FleetDecision? { decisions.first }

    /// Any decision open on this lane: the alert's own dimension, independent of the lane's
    /// activity state. The map row, the mini map and the collapsed pip read this.
    var hasOpenDecision: Bool { !decisions.isEmpty }

    var isLinked: Bool { state != .offline }
}

/// Odin's open alert: its QA reviewer is waiting on a human decision. Shown in the
/// panel's alert strip and on the collapsed notch's red dot.
struct FleetDecision: Equatable {
    var job: String?
    var repo: String?
    var pr: Int?
    var reason: String?
    var round: Int?
    var found: [String] = []
    var question: String?
    var options: [OdinOption] = OdinOption.defaults
}

extension FleetDecision {
    /// The one place an Odin stop record becomes a decision.
    fileprivate init(_ status: OdinStatus) {
        self.init(job: status.job, repo: status.repo, pr: status.pr, reason: status.reason,
                  round: status.round, found: status.found, question: status.question,
                  options: status.options)
    }
}

/// One of the footer's three rings, outer to inner.
enum FleetRingKind: String, CaseIterable, Hashable {
    case cpu, gpu, ram

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        }
    }
}

/// The colour level of a percent reading: under 70 % `ok`, 70-89 % `hot`, 90 % and over `alert`.
enum FleetRingLevel: Equatable { case ok, hot, alert }

/// One machine's three readings for the footer, in ring order: outer CPU, middle GPU, inner RAM.
/// A reading the machine does not report is nil (that ring keeps its track only). A reading that is
/// not live - the machine reports offline, or the fleet feed has not answered since its last failure -
/// draws no arcs at all, so the footer never shows a machine as healthier than it is.
struct FleetHostReading: Identifiable, Equatable {
    var id: String
    var label: String
    var cpu: Int?
    var gpu: Int?
    var ram: Int?
    /// Whether these readings can be trusted right now: the machine reports online AND the fleet feed
    /// answered its last poll. The store keeps the last snapshot when a poll fails, so a retained
    /// payload must read as stale, not as live.
    var live: Bool

    /// The reading for one ring: whole percent, nil when the machine reports none.
    func value(_ kind: FleetRingKind) -> Int? {
        switch kind {
        case .cpu: return cpu
        case .gpu: return gpu
        case .ram: return ram
        }
    }

    /// The arc's 0…1 sweep, or nil when the reading is not live or missing. A machine that is offline
    /// or whose feed has failed draws no arc; a missing reading leaves its ring with the track only.
    func arcFraction(_ kind: FleetRingKind) -> Double? {
        guard live, let percent = value(kind) else { return nil }
        return FleetFormat.fraction(Double(percent))
    }

    /// The highest of the three readings with its kind, cpu winning a tie; nil when nothing is reported.
    var hottest: (kind: FleetRingKind, value: Int)? {
        FleetRingKind.allCases.compactMap { kind in
            value(kind).map { (kind, $0) }
        }.max { $0.value < $1.value }
    }
}

struct FleetPanelModel: Equatable {
    var origin: FleetLane              // id/label "case"
    var agents: [FleetLane]            // frank, claire, ciri, morpheus, dali, nova, pika, odin
    /// Sum of the agents' reported rates; nil only when no agent reports a rate;
    /// a reported 0 counts as 0.
    var totalTokPerSec: Double?
    /// The fleet-wide decode speed (tokens/s and its trend), from the fleet payload's block with
    /// the activity payload's block as fallback; nil when neither reports one.
    var speed: FleetSpeed?
    /// One reading per footer machine, always in `FleetPanelModelBuilder.footerHosts` order. A reading
    /// is live only while the fleet feed's last poll answered and its own machine reports online.
    var hosts: [FleetHostReading]
    /// The Case jobs' heartbeat (`/api/jobs`), running ones first; empty without that feed.
    var caseJobs: [CaseJob] = []

    /// The Case jobs that are running now, in the feed's order.
    var runningCaseJobs: [CaseJob] { caseJobs.filter(\.running) }

    /// case first, then the agents.
    var lanes: [FleetLane] { [origin] + agents }

    var agentCount: Int { agents.count }
    var workingCount: Int { agents.filter { $0.state == .busy }.count }
    var linkedCount: Int { agents.filter(\.isLinked).count }
    var criticalCount: Int { agents.filter { !$0.isLinked }.count }
    /// Machines that are on but whose model / probe does not answer ("1 down").
    var downCount: Int { agents.filter { $0.isLinked && $0.probeFailed }.count }
    var isBusy: Bool { workingCount > 0 || origin.state == .busy }

    /// Jobs of the busy lanes (case first) in walk order, deduped by key keeping the
    /// first occurrence; an offline lane keeps its last-reported jobs visible in the
    /// map, but they are not running.
    ///
    /// One source of truth for both `runningTaskCount` and `nowJobs`, so the health-row
    /// count and the "+N jobs in Fleet" link always match the preview list. Summing
    /// per-lane counts would double-count: case reports the jobs it delegated (they
    /// appear on frank/claire/dali too) and the OpenRouter runs nova is derived from,
    /// so nova's jobs are a duplicate subset of case's.
    private var runningJobs: [FleetJob] {
        var seen = Set<String>()
        var collected: [FleetJob] = []
        for lane in lanes where lane.state == .busy {
            for job in lane.jobs where seen.insert(job.key).inserted {
                collected.append(job)
            }
        }
        return collected
    }

    /// Unique running jobs across the busy lanes; matches the `nowJobs` preview list.
    var runningTaskCount: Int { runningJobs.count }

    /// The busy lanes' deduped jobs, newest-first.
    var nowJobs: [FleetJob] {
        // Smallest elapsed = newest; nil (unknown start) last; ties keep walk order.
        runningJobs.enumerated().sorted { lhs, rhs in
            switch (lhs.element.elapsedSec, rhs.element.elapsedSec) {
            case (nil, nil): return lhs.offset < rhs.offset
            case (nil, _?): return false
            case (_?, nil): return true
            case let (a?, b?) where a == b: return lhs.offset < rhs.offset
            case let (a?, b?): return a < b
            }
        }.map(\.element)
    }

    /// Odin's open decisions, in order. Walks the agents and returns the first lane
    /// with an open list (only Odin ever sets one).
    var decisions: [FleetDecision] { agents.first { !$0.decisions.isEmpty }?.decisions ?? [] }

    /// The first open decision: the one the panel's alert strip names.
    var decision: FleetDecision? { decisions.first }

    /// Whether any decision is open; drives the collapsed notch's red pip. Deliberately
    /// independent of reachability: a failed poll keeps the last known decision until a
    /// later successful status clears it.
    var hasOpenDecision: Bool { !decisions.isEmpty }

    /// The model with the given jobs' decisions dropped: what the notch shows once the owner has
    /// answered one, until a later fetch stops reporting it.
    func droppingDecisions(jobs: Set<String>) -> FleetPanelModel {
        guard !jobs.isEmpty else { return self }
        var copy = self
        copy.agents = agents.map { lane in
            var lane = lane
            lane.decisions = lane.decisions.filter { decision in
                guard let job = decision.job else { return true }
                return !jobs.contains(job)
            }
            return lane
        }
        return copy
    }
}

/// The notch's two fleet polls, each tracked on its own. One shared flag would let an activity answer
/// declare the machine readings live again while the fleet poll keeps failing, so the footer's rings
/// read `fleetIsLive` and never the shared reachability.
struct FleetFeedFreshness: Equatable {
    /// The two endpoints the store polls.
    enum Source: Equatable { case fleet, activity }

    private(set) var lastFleetSuccessAt: Date?
    private(set) var lastFleetErrorAt: Date?
    private(set) var lastActivitySuccessAt: Date?
    private(set) var lastActivityErrorAt: Date?

    mutating func markSuccess(_ source: Source, at date: Date) {
        switch source {
        case .fleet: lastFleetSuccessAt = date
        case .activity: lastActivitySuccessAt = date
        }
    }

    mutating func markFailure(_ source: Source, at date: Date) {
        switch source {
        case .fleet: lastFleetErrorAt = date
        case .activity: lastActivityErrorAt = date
        }
    }

    /// The fleet payload's own freshness, which is all the footer's rings read: a failed fleet poll
    /// leaves them stale until the fleet answers again, whatever the activity feed does. Deliberately no
    /// grace window - after a failed fleet poll the numbers are simply not current.
    var fleetIsLive: Bool {
        FleetFeedFreshness.answered(lastSuccessAt: lastFleetSuccessAt, lastErrorAt: lastFleetErrorAt)
    }

    /// The store's reachability, its meaning unchanged: either feed answering counts, until a later
    /// failure outranks it. The closed notch's fleet row reads this.
    var isReachable: Bool {
        let success = [lastFleetSuccessAt, lastActivitySuccessAt].compactMap { $0 }.max()
        let error = [lastFleetErrorAt, lastActivityErrorAt].compactMap { $0 }.max()
        return FleetFeedFreshness.answered(lastSuccessAt: success, lastErrorAt: error)
    }

    /// Reachable once something has succeeded and no failure is newer than that success.
    private static func answered(lastSuccessAt: Date?, lastErrorAt: Date?) -> Bool {
        guard let lastSuccessAt else { return false }
        guard let lastErrorAt else { return true }
        return lastSuccessAt >= lastErrorAt
    }
}

enum FleetPanelModelBuilder {
    static let agentIds = ["frank", "claire", "ciri", "morpheus", "dali", "nova", "pika", "odin"]

    /// "openrouter" | "qwencloud" | "other" (nil/empty/unknown model -> "other").
    static func cloudProvider(_ model: String?) -> String {
        guard let model = model else { return "other" }
        if model.hasPrefix("openrouter") { return "openrouter" }
        if model.hasPrefix("qwencloud") { return "qwencloud" }
        return "other"
    }

    /// `fleetLive` is the store's reachability: false once a poll has failed, so a retained snapshot
    /// reads as stale instead of live.
    static func build(fleet: FleetSnapshot?, activity: ActivitySnapshot?, fleetLive: Bool,
                      caseJobs: CaseJobsSnapshot? = nil) -> FleetPanelModel {
        // case runs its own jobs AND the delegated ones routed to frank/claire/dali.
        let origin = machineLane(id: "case", fleet: fleet, activity: activity)
        let agents: [FleetLane] = [
            machineLane(id: "frank", fleet: fleet, activity: activity),
            machineLane(id: "claire", fleet: fleet, activity: activity),
            machineLane(id: "ciri", fleet: fleet, activity: activity),
            // morpheus is the design agent (GPT-6.1 Sol on Codex, 2 slots). Like pika it is a
            // cloud helper: the fleet API reports device "morpheus". A row that says offline is
            // offline, a busy device with no row is busy, and no data at all leaves the lane
            // idle/grey - never a red node for missing data.
            morpheusLane(fleet: fleet, activity: activity),
            machineLane(id: "dali", fleet: fleet, activity: activity),
            // nova is not a fleet machine: it is the pool of openrouter cloud jobs
            // the case runs.
            novaLane(fleet: fleet, activity: activity),
            // pika is the cloud helper (Claude Haiku). The fleet API reports device "pika":
            // a row that says offline is offline, a busy device with no row is busy, and no data
            // at all leaves the lane idle/grey - never a red node for missing data.
            pikaLane(fleet: fleet, activity: activity),
            // Odin is the QA reviewer that runs on case (Codex): activity device
            // "odin", fleet machine "odin". Its open decisions ride on the lane as the
            // alert dimension (see odinLane), independent of its busy/idle state.
            odinLane(fleet: fleet, activity: activity),
        ]
        let rates = agentIds.compactMap { device(id: $0, in: activity)?.tokPerSec }
        let totalTokPerSec = rates.isEmpty ? nil : rates.reduce(0, +)
        let speed = fleet?.speed ?? activity?.speed ?? Self.medianSpeed(from: activity)
        return FleetPanelModel(origin: origin,
                               agents: agents,
                               totalTokPerSec: totalTokPerSec,
                               // The fleet payload's speed block wins; the activity payload's is the fallback.
                               // When neither sends a block, the median of the reporting devices is used, so
                               // the header is never a sum.
                               speed: speed,
                               hosts: hosts(from: fleet, live: fleetLive),
                               caseJobs: caseJobs?.jobs ?? [])
    }

    // MARK: - Lane builders

    /// A lane backed by a fleet machine plus its activity device.
    private static func machineLane(id: String, fleet: FleetSnapshot?,
                                    activity: ActivitySnapshot?) -> FleetLane {
        let machine = machine(id: id, in: fleet)
        let device = device(id: id, in: activity)
        let state: FleetNodeState = machineOnline(machine) ? (deviceBusy(device) ? .busy : .idle) : .offline
        return FleetLane(id: id, label: id, state: state, jobs: toJobs(device?.items ?? []),
                         speed: device?.speed, probeFailed: probeFailed(device))
    }

    /// nova's state comes from the fleet snapshot's presence and its own cloud jobs,
    /// never from a machine row.
    private static func novaLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let openrouterItems = caseCloudItems(activity).filter { cloudProvider($0.model) == "openrouter" }
        let state: FleetNodeState = fleet == nil ? .offline : (openrouterItems.isEmpty ? .idle : .busy)
        // nova is a pool of cloud runs, not a machine, so it has no device speed.
        return FleetLane(id: "nova", label: "nova", state: state, jobs: toJobs(openrouterItems),
                         speed: nil)
    }

    /// pika's state: a fleet row that exists but is not online means offline; with no fleet row at
    /// all the activity device decides - a busy device is busy, otherwise idle/grey. Its jobs always
    /// come from the activity device, so a run with no machine record still counts in the working
    /// total and the current-work list. Missing data must never crash.
    private static func pikaLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let device = device(id: "pika", in: activity)
        let state: FleetNodeState = machine(id: "pika", in: fleet)
            .map { machineOnline($0) ? (deviceBusy(device) ? .busy : .idle) : .offline }
            ?? (deviceBusy(device) ? .busy : .idle)
        return FleetLane(id: "pika", label: "pika", state: state, jobs: toJobs(device?.items ?? []),
                         speed: device?.speed, probeFailed: probeFailed(device))
    }

    /// morpheus's state, pika's rule exactly: a fleet row that exists but is not online means
    /// offline; with no fleet row at all the activity device decides - a busy device is busy,
    /// otherwise idle/grey. Its jobs always come from the activity device, so a design run with
    /// no machine record still counts in the working total and the current-work list.
    private static func morpheusLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let device = device(id: "morpheus", in: activity)
        let state: FleetNodeState = machine(id: "morpheus", in: fleet)
            .map { machineOnline($0) ? (deviceBusy(device) ? .busy : .idle) : .offline }
            ?? (deviceBusy(device) ? .busy : .idle)
        return FleetLane(id: "morpheus", label: "morpheus", state: state, jobs: toJobs(device?.items ?? []),
                         speed: device?.speed, probeFailed: probeFailed(device))
    }

    /// Odin's lane: its state is the plain machine/device rule — busy while a review runs, so
    /// that review still counts as work — and its open decisions ride along as the alert's own
    /// dimension. A failed fleet probe cannot hide the alert, and an idle status cannot veto a
    /// non-empty open list.
    private static func odinLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let machine = machine(id: "odin", in: fleet)
        let device = device(id: "odin", in: activity)
        let state: FleetNodeState = machineOnline(machine) ? (deviceBusy(device) ? .busy : .idle) : .offline
        return FleetLane(id: "odin", label: "odin", state: state, jobs: toJobs(device?.items ?? []),
                         speed: device?.speed, decisions: decisions(from: device?.odin),
                         probeFailed: probeFailed(device))
    }

    /// The open decisions of an Odin report, in file order. The feed's open-decisions
    /// list wins whenever it is present (`[]` means nothing is open, even with a
    /// needs-decision status); without it, the single needs-decision status.
    static func decisions(from report: OdinReport?) -> [FleetDecision] {
        if let open = report?.open { return open.map { FleetDecision($0) } }
        guard let status = report?.status, status.needsDecision else { return [] }
        return [FleetDecision(status)]
    }

    // MARK: - Footer hosts

    /// The footer's five machines in the owner's order; macbook shows as "mac", like the panel's
    /// other lowercase names.
    static let footerHosts: [(id: String, label: String)] = [
        ("case", "case"), ("frank", "frank"), ("claire", "claire"), ("dali", "dali"), ("macbook", "mac"),
    ]

    /// One reading per footer machine, always in `footerHosts` order: a machine the payload never
    /// mentions keeps its slot with no readings and no arcs, so the strip never changes width.
    /// A reading is live only while the feed answered its last poll AND the machine reports online.
    private static func hosts(from fleet: FleetSnapshot?, live: Bool) -> [FleetHostReading] {
        footerHosts.map { entry in
            let machine = machine(id: entry.id, in: fleet)
            return FleetHostReading(id: entry.id,
                                    label: entry.label,
                                    cpu: percent(machine?.cpuLoadPct),
                                    gpu: percent(machine?.gpuUtilPct),
                                    ram: percent(machine?.ramUsedPct),
                                    live: live && machineOnline(machine))
        }
    }

    /// A reading as the footer's whole percent, nil when it is unavailable or carries no value.
    private static func percent(_ reading: Reading?) -> Int? {
        guard let reading, reading.isAvailable, let value = reading.value else { return nil }
        return Int(value.rounded())
    }

    // MARK: - Lookup helpers

    private static func machine(id: String, in fleet: FleetSnapshot?) -> FleetMachine? {
        fleet?.machines.first { $0.id == id }
    }

    private static func device(id: String, in activity: ActivitySnapshot?) -> DeviceActivity? {
        activity?.devices.first { $0.device == id }
    }

    /// The contract's fleet speed when neither payload carries a block: the median of the devices that
    /// report one. nil when no device does, so the header keeps its "—".
    private static func medianSpeed(from activity: ActivitySnapshot?) -> FleetSpeed? {
        guard let current = FleetFormat.medianSpeed((activity?.devices ?? []).map(\.speed)) else {
            return nil
        }
        return FleetSpeed(current: current, lastAt: nil)
    }

    /// The cloud-routed items the case runs (nova's raw feed before provider split).
    private static func caseCloudItems(_ activity: ActivitySnapshot?) -> [ActivityItem] {
        (device(id: "case", in: activity)?.items ?? []).filter { $0.device == "cloud" }
    }

    /// The activity probe of this device failed (`state: "error"`).
    private static func probeFailed(_ device: DeviceActivity?) -> Bool {
        device?.state == "error"
    }

    private static func machineOnline(_ machine: FleetMachine?) -> Bool {
        machine?.state == "online"
    }

    /// busy = items > 0 || device.busy == true || slots.used > 0
    private static func deviceBusy(_ device: DeviceActivity?) -> Bool {
        (device?.items.count ?? 0) > 0 || device?.busy == true || (device?.slots?.used ?? 0) > 0
    }

    // MARK: - Jobs

    /// Newest-first by `since` (ISO strings compare lexicographically); nil-since last;
    /// ties keep original order.
    private static func toJobs(_ items: [ActivityItem]) -> [FleetJob] {
        items.enumerated().sorted { lhs, rhs in
            switch (lhs.element.since, rhs.element.since) {
            case (nil, nil): return lhs.offset < rhs.offset
            case (nil, _?): return false
            case (_?, nil): return true
            case let (a?, b?) where a == b: return lhs.offset < rhs.offset
            case let (a?, b?): return a > b
            }
        }.map { entry in
            FleetJob(key: entry.element.id, pill: pill(for: entry.element),
                     label: entry.element.label, step: entry.element.lastStep,
                     elapsedSec: entry.element.elapsedSec)
        }
    }

    /// Cloud-model runs are branded by provider; delegated work shows its device.
    private static func pill(for item: ActivityItem) -> String {
        guard item.device == "cloud" else { return item.device }
        return cloudProvider(item.model) == "openrouter" ? "nova" : "case"
    }
}
