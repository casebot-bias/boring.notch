//
//  FleetPanelModel.swift
//  boringNotch
//
//  Data model for the opened fleet panel: the `case` origin at the centre of a
//  response map, the seven agent signals (frank, claire, ciri, dali, nova, pika, odin),
//  the current-work jobs, and the fleet-wide output / peak readings shown in the
//  header and footer. Foundation only (no SwiftUI) so it compiles into both the
//  app target and the test target.
//

import Foundation

/// Signal state of a node. Offline beats busy: an offline/absent machine reports
/// .offline even when its activity device claims work.
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
    var isLinked: Bool { state != .offline }
}

/// Fleet-wide peak for one hardware kind, shown in the panel footer.
struct FleetPeak: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case cpu, gpu, ram

        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .ram: return "RAM"
            }
        }
    }

    var kind: Kind
    var value: Double?   // percent 0…100; nil when no host reported it
    var host: String?    // machine title that reported the value
    var id: String { kind.rawValue }
}

struct FleetPanelModel: Equatable {
    var origin: FleetLane              // id/label "case"
    var agents: [FleetLane]            // frank, claire, ciri, dali, nova, pika, odin
    /// Sum of the agents' reported rates; nil only when no agent reports a rate;
    /// a reported 0 counts as 0.
    var totalTokPerSec: Double?
    var peaks: [FleetPeak]             // always cpu, gpu, ram in this order

    /// case first, then the agents.
    var lanes: [FleetLane] { [origin] + agents }

    var agentCount: Int { agents.count }
    var workingCount: Int { agents.filter { $0.state == .busy }.count }
    var linkedCount: Int { agents.filter(\.isLinked).count }
    var criticalCount: Int { agents.filter { !$0.isLinked }.count }
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
}

enum FleetPanelModelBuilder {
    static let agentIds = ["frank", "claire", "ciri", "dali", "nova", "pika", "odin"]

    /// "openrouter" | "qwencloud" | "other" (nil/empty/unknown model -> "other").
    static func cloudProvider(_ model: String?) -> String {
        guard let model = model else { return "other" }
        if model.hasPrefix("openrouter") { return "openrouter" }
        if model.hasPrefix("qwencloud") { return "qwencloud" }
        return "other"
    }

    static func build(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetPanelModel {
        // case runs its own jobs AND the delegated ones routed to frank/claire/dali.
        let origin = machineLane(id: "case", fleet: fleet, activity: activity)
        let agents: [FleetLane] = [
            machineLane(id: "frank", fleet: fleet, activity: activity),
            machineLane(id: "claire", fleet: fleet, activity: activity),
            machineLane(id: "ciri", fleet: fleet, activity: activity),
            machineLane(id: "dali", fleet: fleet, activity: activity),
            // nova is not a fleet machine: it is the pool of openrouter cloud jobs
            // the case runs.
            novaLane(fleet: fleet, activity: activity),
            // pika is the cloud helper (Claude Haiku). The fleet API reports device "pika":
            // a row that says offline is offline, a busy device with no row is busy, and no data
            // at all leaves the lane idle/grey - never a red node for missing data.
            pikaLane(fleet: fleet, activity: activity),
            // Odin is the QA reviewer that runs on case (Codex): activity device
            // "odin", fleet machine "odin".
            machineLane(id: "odin", fleet: fleet, activity: activity),
        ]
        let rates = agentIds.compactMap { device(id: $0, in: activity)?.tokPerSec }
        let totalTokPerSec = rates.isEmpty ? nil : rates.reduce(0, +)
        return FleetPanelModel(origin: origin,
                               agents: agents,
                               totalTokPerSec: totalTokPerSec,
                               peaks: peaks(from: fleet))
    }

    // MARK: - Lane builders

    /// A lane backed by a fleet machine plus its activity device.
    private static func machineLane(id: String, fleet: FleetSnapshot?,
                                    activity: ActivitySnapshot?) -> FleetLane {
        let machine = machine(id: id, in: fleet)
        let device = device(id: id, in: activity)
        let state: FleetNodeState = machineOnline(machine) ? (deviceBusy(device) ? .busy : .idle) : .offline
        return FleetLane(id: id, label: id, state: state, jobs: toJobs(device?.items ?? []))
    }

    /// nova's state comes from the fleet snapshot's presence and its own cloud jobs,
    /// never from a machine row.
    private static func novaLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let openrouterItems = caseCloudItems(activity).filter { cloudProvider($0.model) == "openrouter" }
        let state: FleetNodeState = fleet == nil ? .offline : (openrouterItems.isEmpty ? .idle : .busy)
        return FleetLane(id: "nova", label: "nova", state: state, jobs: toJobs(openrouterItems))
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
        return FleetLane(id: "pika", label: "pika", state: state, jobs: toJobs(device?.items ?? []))
    }

    // MARK: - Peaks

    /// Highest available cpu/gpu/ram reading across every fleet machine, always in
    /// cpu, gpu, ram order; nil value/host when nothing reported.
    private static func peaks(from fleet: FleetSnapshot?) -> [FleetPeak] {
        FleetPeak.Kind.allCases.map { kind in
            var best: (value: Double, host: String)?
            for machine in fleet?.machines ?? [] {
                let reading: Reading
                switch kind {
                case .cpu: reading = machine.cpuLoadPct
                case .gpu: reading = machine.gpuUtilPct
                case .ram: reading = machine.ramUsedPct
                }
                guard reading.isAvailable, let value = reading.value,
                      best == nil || value > best!.value else { continue }
                best = (value, machine.title.isEmpty ? machine.id : machine.title)
            }
            return FleetPeak(kind: kind, value: best?.value, host: best?.host)
        }
    }

    // MARK: - Lookup helpers

    private static func machine(id: String, in fleet: FleetSnapshot?) -> FleetMachine? {
        fleet?.machines.first { $0.id == id }
    }

    private static func device(id: String, in activity: ActivitySnapshot?) -> DeviceActivity? {
        activity?.devices.first { $0.device == id }
    }

    /// The cloud-routed items the case runs (nova's raw feed before provider split).
    private static func caseCloudItems(_ activity: ActivitySnapshot?) -> [ActivityItem] {
        (device(id: "case", in: activity)?.items ?? []).filter { $0.device == "cloud" }
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
