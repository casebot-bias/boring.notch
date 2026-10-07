//
//  FleetPanelModel.swift
//  boringNotch
//
//  Data model for the opened fleet panel: the case origin plus the six machines
//  (frank, claire, dali, nova, ciri, macbook) as butterfly rows, plus the "Now" jobs.
//  Foundation only (no SwiftUI) so it compiles into both the app target and the test
//  target.
//

import Foundation

/// What a lane represents; drives palette and the right-hand metric.
enum FleetNodeKind: Equatable { case gpu, cloud, agent, mac, host }

/// Lane state. Offline beats busy: an offline/absent machine reports .offline even
/// when its activity device claims work.
enum FleetNodeState: Equatable { case busy, idle, offline }

/// One running piece of work, shown in a lane and in the fixed "Now" block.
struct FleetJob: Identifiable, Equatable {
    var key: String        // stable dedup id (ActivityItem.id)
    var pill: String       // "nova" | "case" | the delegating device id
    var label: String
    var elapsedSec: Int?
    var id: String { key }
}

/// Right-hand metric of a lane, kept split so the view can colour each part:
/// tok/s is the accent part, the temperature and the label are dim.
struct FleetMeta: Equatable {
    var tokPerSec: Double?   // "42 t/s"; nil or <= 0 -> not shown
    var temp: Reading        // "38°"; unavailable -> not shown
    var label: String?       // dim fallback when there is no value: "live" | "idle" | "2 jobs" | "—"
}

/// One row: the case origin or a machine, with its bars and jobs.
struct FleetLane: Identifiable, Equatable {
    var id: String
    var label: String
    var kind: FleetNodeKind
    var state: FleetNodeState
    var cpu: Reading
    var ram: Reading
    var temp: Reading
    var meta: FleetMeta    // right-column metric: t/s in accent, ° and labels in dim
    var jobs: [FleetJob]
    var busy: Bool { state == .busy }
}

struct FleetPanelModel: Equatable {
    var origin: FleetLane          // id "case"
    var nodes: [FleetLane]         // row order: frank, claire, dali, nova, ciri, macbook
    var activeCount: Int

    var isBusy: Bool { activeCount > 0 }

    /// case first, then the machines.
    var lanes: [FleetLane] { [origin] + nodes }

    /// Jobs of the busy lanes, newest-first, deduped by key keeping the first
    /// occurrence while walking `lanes`.
    var nowJobs: [FleetJob] {
        var seen = Set<String>()
        var collected: [FleetJob] = []
        for lane in lanes where lane.state == .busy {
            for job in lane.jobs where seen.insert(job.key).inserted {
                collected.append(job)
            }
        }
        // Smallest elapsed = newest; nil (unknown start) last; ties keep walk order.
        return collected.enumerated().sorted { lhs, rhs in
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
    static let nodeIds = ["frank", "claire", "dali", "nova", "ciri", "macbook"]

    /// "openrouter" | "qwencloud" | "other" (nil/empty/unknown model -> "other").
    static func cloudProvider(_ model: String?) -> String {
        guard let model = model else { return "other" }
        if model.hasPrefix("openrouter") { return "openrouter" }
        if model.hasPrefix("qwencloud") { return "qwencloud" }
        return "other"
    }

    static func build(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetPanelModel {
        // case runs its own jobs AND the delegated ones routed to frank/claire/dali.
        let origin = machineLane(id: "case", kind: .host, fleet: fleet, activity: activity)
        let nodes: [FleetLane] = [
            machineLane(id: "frank", kind: .gpu, fleet: fleet, activity: activity),
            machineLane(id: "claire", kind: .gpu, fleet: fleet, activity: activity),
            machineLane(id: "dali", kind: .gpu, fleet: fleet, activity: activity),
            novaLane(fleet: fleet, activity: activity),
            machineLane(id: "ciri", kind: .agent, fleet: fleet, activity: activity),
            machineLane(id: "macbook", kind: .mac, fleet: fleet, activity: activity),
        ]
        let activeCount = ([origin] + nodes).filter { $0.state == .busy }.count
        return FleetPanelModel(origin: origin, nodes: nodes, activeCount: activeCount)
    }

    // MARK: - Lane builders

    /// A lane backed by a fleet machine plus its activity device.
    private static func machineLane(id: String, kind: FleetNodeKind, fleet: FleetSnapshot?,
                                    activity: ActivitySnapshot?) -> FleetLane {
        let machine = machine(id: id, in: fleet)
        let device = device(id: id, in: activity)
        let state: FleetNodeState = machineOnline(machine) ? (deviceBusy(device) ? .busy : .idle) : .offline
        let jobs = toJobs(device?.items ?? [])
        let temp = machine?.cpuTempC ?? unavailableReading
        return FleetLane(id: id, label: id == "macbook" ? "mac" : id, kind: kind, state: state,
                         cpu: machine?.cpuLoadPct ?? unavailableReading,
                         ram: machine?.ramUsedPct ?? unavailableReading, temp: temp,
                         meta: laneMeta(kind: kind, state: state, temp: temp,
                                           tokPerSec: device?.tokPerSec, jobCount: jobs.count),
                         jobs: jobs)
    }

    /// nova is not a fleet machine: it is the pool of openrouter cloud jobs the case runs.
    private static func novaLane(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetLane {
        let openrouterItems = (device(id: "case", in: activity)?.items ?? []).filter {
            $0.device == "cloud" && cloudProvider($0.model) == "openrouter"
        }
        let state: FleetNodeState = fleet == nil ? .offline : (openrouterItems.isEmpty ? .idle : .busy)
        let jobs = toJobs(openrouterItems)
        return FleetLane(id: "nova", label: "nova", kind: .cloud, state: state,
                         cpu: unavailableReading, ram: unavailableReading, temp: unavailableReading,
                         meta: laneMeta(kind: .cloud, state: state, temp: unavailableReading,
                                           tokPerSec: nil, jobCount: jobs.count),
                         jobs: jobs)
    }

    /// Right-column metric, split for the two-colour render: tok/s (accent) and the
    /// temperature (dim) show side by side; the label covers the lanes that report
    /// neither. tokPerSec comes from the lane's own device (nil for cloud/ciri), so
    /// case and mac stay temperature-only.
    private static func laneMeta(kind: FleetNodeKind, state: FleetNodeState, temp: Reading,
                                 tokPerSec: Double?, jobCount: Int) -> FleetMeta {
        if state == .offline {
            return FleetMeta(tokPerSec: nil, temp: unavailableReading, label: FleetFormat.unknown)
        }
        if kind == .cloud {
            return FleetMeta(tokPerSec: nil, temp: unavailableReading, label: state == .busy ? "live" : "idle")
        }
        if kind == .agent {
            return FleetMeta(tokPerSec: nil, temp: unavailableReading,
                             label: state == .busy ? FleetFormat.jobs(max(jobCount, 1)) : "idle")
        }
        let tokens = (kind == .gpu && state == .busy) ? tokPerSec : nil
        return FleetMeta(tokPerSec: tokens, temp: temp, label: FleetFormat.unknown)
    }

    // MARK: - Lookup helpers

    private static func machine(id: String, in fleet: FleetSnapshot?) -> FleetMachine? {
        fleet?.machines.first { $0.id == id }
    }

    private static func device(id: String, in activity: ActivitySnapshot?) -> DeviceActivity? {
        activity?.devices.first { $0.device == id }
    }

    private static func machineOnline(_ machine: FleetMachine?) -> Bool {
        machine?.state == "online"
    }

    /// busy = items > 0 || device.busy == true || slots.used > 0
    private static func deviceBusy(_ device: DeviceActivity?) -> Bool {
        (device?.items.count ?? 0) > 0 || device?.busy == true || (device?.slots?.used ?? 0) > 0
    }

    private static let unavailableReading = Reading(value: nil, state: "unavailable", note: nil)

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
                     label: entry.element.label, elapsedSec: entry.element.elapsedSec)
        }
    }

    /// Cloud-model runs are branded by provider; delegated work shows its device.
    private static func pill(for item: ActivityItem) -> String {
        guard item.device == "cloud" else { return item.device }
        return cloudProvider(item.model) == "openrouter" ? "nova" : "case"
    }
}
