//
//  FleetOrbitModel.swift
//  boringNotch
//
//  Data model for the fleet orbit: the case origin plus six satellites on one ring
//  (frank, claire, dali, nova, ciri, macbook), matching the approved fleet-notch-v2
//  design. Foundation + CoreGraphics only (no SwiftUI) so it compiles into both the
//  app target and the test target.
//

import Foundation
import CoreGraphics

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

/// One orbit box: the case origin or a satellite, with its bars and jobs.
struct FleetLane: Identifiable, Equatable {
    var id: String
    var label: String
    var kind: FleetNodeKind
    var state: FleetNodeState
    var cpu: Reading
    var ram: Reading
    var temp: Reading
    var right: String      // right-column metric: t/s, °, "live", job count, or "—"
    var jobs: [FleetJob]
    var busy: Bool { state == .busy }
}

struct FleetOrbitModel: Equatable {
    var origin: FleetLane          // id "case"
    var nodes: [FleetLane]         // ring order: frank, claire, dali, nova, ciri, macbook
    var activeCount: Int

    var isBusy: Bool { activeCount > 0 }

    /// case first, then the ring.
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

enum FleetOrbitBuilder {
    static let nodeIds = ["frank", "claire", "dali", "nova", "ciri", "macbook"]
    static let orbitCanvas: CGFloat = 150
    static let ringRadius: CGFloat = 58
    static let orbitCenter = CGPoint(x: 75, y: 75)

    /// "openrouter" | "qwencloud" | "other" (nil/empty/unknown model -> "other").
    static func cloudProvider(_ model: String?) -> String {
        guard let model = model else { return "other" }
        if model.hasPrefix("openrouter") { return "openrouter" }
        if model.hasPrefix("qwencloud") { return "qwencloud" }
        return "other"
    }

    static func build(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetOrbitModel {
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
        return FleetOrbitModel(origin: origin, nodes: nodes, activeCount: activeCount)
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
                         right: rightLabel(kind: kind, state: state, temp: temp,
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
                         right: rightLabel(kind: .cloud, state: state, temp: unavailableReading,
                                           tokPerSec: nil, jobCount: jobs.count),
                         jobs: jobs)
    }

    /// Right-column metric; temperature is the fallback, so idle GPU boxes, case and
    /// mac show degrees. tokPerSec comes from the lane's own device (nil for cloud/ciri).
    private static func rightLabel(kind: FleetNodeKind, state: FleetNodeState, temp: Reading,
                                   tokPerSec: Double?, jobCount: Int) -> String {
        if state == .offline { return FleetFormat.unknown }
        if kind == .gpu, state == .busy, let tokPerSec = tokPerSec, tokPerSec > 0 {
            return FleetFormat.tokensPerSecond(tokPerSec)
        }
        if kind == .cloud { return state == .busy ? "live" : "idle" }
        if kind == .agent { return state == .busy ? FleetFormat.jobs(max(jobCount, 1)) : "idle" }
        if temp.isAvailable { return FleetFormat.degrees(temp) }
        return FleetFormat.unknown
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

    // MARK: - Geometry

    /// Ring point for satellite `index` of `count`; index 0 is the top.
    static func position(index: Int, count: Int) -> CGPoint {
        guard let a = angle(index: index, count: count) else { return orbitCenter }
        return CGPoint(x: orbitCenter.x + ringRadius * cos(a), y: orbitCenter.y + ringRadius * sin(a))
    }

    /// Label point just outside the ring, baseline nudged down 3pt.
    static func labelPosition(index: Int, count: Int) -> CGPoint {
        guard let a = angle(index: index, count: count) else { return orbitCenter }
        return CGPoint(x: orbitCenter.x + 78 * cos(a), y: orbitCenter.y + 74 * sin(a) + 3)
    }

    /// i = 0 sits at the top; index clamped to 0..<count; nil when nothing to place.
    private static func angle(index: Int, count: Int) -> CGFloat? {
        guard count > 0 else { return nil }
        let i = min(max(index, 0), count - 1)
        return -CGFloat.pi / 2 + 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
    }
}
