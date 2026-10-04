//
//  FleetMapModel.swift
//  boringNotch
//
//  Faithful Swift port of fleet-dashboard/lib/fleet/map-model.ts (`buildMapModel`).
//  Depends only on Foundation and the model types (FleetSnapshot, FleetMachine,
//  ActivitySnapshot, DeviceActivity, ActivityItem, SlotState) declared in the same target.
//

import Foundation

// MARK: - Map types

enum FleetNodeState {
    case working
    case idle
    case offline
}

struct FleetJob: Equatable {
    var key: String
    var label: String
    var step: String?
    var elapsedSec: Int?
}

struct FleetMapNode: Identifiable, Equatable {
    var id: String
    var label: String
    var state: FleetNodeState
    var busy: Bool
    var dots: Int
    var jobs: [FleetJob]
}

struct FleetMapModel {
    var nodes: [FleetMapNode]
    var origin: FleetMapNode
    var sentOut: Int

    /// Busy node count, plus the case origin when it runs jobs of its own (cloud-model
    /// runs not sent out to frank/claire/dali/nova), since there is no separate cloud node.
    var activeCount: Int {
        let delegated = sentOut + (nodes.first { $0.id == "nova" }?.jobs.count ?? 0)
        let originLocal = origin.jobs.count > delegated ? 1 : 0
        return nodes.filter(\.busy).count + originLocal
    }
    var isBusy: Bool { activeCount > 0 }
}

// MARK: - Builder

enum FleetMapBuilder {

    private static let MAX_MAP_DOTS = 4

    // MARK: cloudProvider

    /// "openrouter" | "qwencloud" | "other" (nil model -> "other").
    static func cloudProvider(_ model: String?) -> String {
        guard let model = model else { return "other" }
        if model.hasPrefix("openrouter") { return "openrouter" }
        if model.hasPrefix("qwencloud") { return "qwencloud" }
        return "other"
    }

    // MARK: build

    static func build(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetMapModel {
        let frankDevice = device(in: activity, named: "frank")
        let claireDevice = device(in: activity, named: "claire")
        let daliDevice = device(in: activity, named: "dali")
        let caseDevice = device(in: activity, named: "case")

        let frankMachine = machine(in: fleet, id: "frank")
        let claireMachine = machine(in: fleet, id: "claire")
        let daliMachine = machine(in: fleet, id: "dali")
        let macbookMachine = machine(in: fleet, id: "macbook")
        let caseMachine = machine(in: fleet, id: "case")

        let frankItems = frankDevice?.items ?? []
        let claireItems = claireDevice?.items ?? []
        let daliItems = daliDevice?.items ?? []
        let caseItems = caseDevice?.items ?? []

        let frankBusy = isBusy(items: frankItems, device: frankDevice)
        let claireBusy = isBusy(items: claireItems, device: claireDevice)
        let daliBusy = isBusy(items: daliItems, device: daliDevice)

        // A missing device or `slots` falls back to the device's default layout
        // (frank/claire 4 slots, dali 3 slots); defaults report zero used, so dots
        // collapse onto the item-count / busy fallback below.
        let frankSlotsUsed = frankDevice?.slots?.used ?? 0
        let claireSlotsUsed = claireDevice?.slots?.used ?? 0
        let daliSlotsUsed = daliDevice?.slots?.used ?? 0

        let frank = FleetMapNode(
            id: "frank",
            label: "frank",
            state: machineState(frankMachine, busy: frankBusy),
            busy: frankBusy,
            dots: dotCount(itemsCount: frankItems.count, slotsUsed: frankSlotsUsed, busy: frankBusy),
            jobs: toJobs(frankItems)
        )

        let claire = FleetMapNode(
            id: "claire",
            label: "claire",
            state: machineState(claireMachine, busy: claireBusy),
            busy: claireBusy,
            dots: dotCount(itemsCount: claireItems.count, slotsUsed: claireSlotsUsed, busy: claireBusy),
            jobs: toJobs(claireItems)
        )

        let dali = FleetMapNode(
            id: "dali",
            label: "dali",
            state: machineState(daliMachine, busy: daliBusy),
            busy: daliBusy,
            dots: dotCount(itemsCount: daliItems.count, slotsUsed: daliSlotsUsed, busy: daliBusy),
            jobs: toJobs(daliItems)
        )

        // case hosts no model, so qwencloud runs stay on the case origin (no
        // separate cloud node, matching the dashboard). openrouter runs go to "nova".
        let novaItems = caseItems.filter {
            $0.device == "cloud" && cloudProvider($0.model) == "openrouter"
        }

        let novaBusy = !novaItems.isEmpty
        let nova = FleetMapNode(
            id: "nova",
            label: "nova",
            state: fleet == nil ? .offline : (novaBusy ? .working : .idle),
            busy: novaBusy,
            dots: dotCount(itemsCount: novaItems.count, slotsUsed: 0, busy: novaBusy),
            jobs: toJobs(novaItems)
        )

        let macbook = FleetMapNode(
            id: "macbook",
            label: "MacBook",
            state: machineState(macbookMachine, busy: false),
            busy: false,
            dots: 0,
            jobs: []
        )

        let caseBusy = !caseItems.isEmpty
        let origin = FleetMapNode(
            id: "case",
            label: "case",
            state: machineState(caseMachine, busy: caseBusy),
            busy: caseBusy,
            dots: 0,
            jobs: toJobs(caseItems)
        )

        let sentOut = caseItems.filter { ["frank", "claire", "dali"].contains($0.device) }.count

        return FleetMapModel(nodes: [frank, claire, dali, nova, macbook], origin: origin, sentOut: sentOut)
    }

    // MARK: - Helpers

    private static func machine(in fleet: FleetSnapshot?, id: String) -> FleetMachine? {
        fleet?.machines.first { $0.id == id }
    }

    private static func device(in activity: ActivitySnapshot?, named id: String) -> DeviceActivity? {
        activity?.devices.first { $0.device == id }
    }

    /// busy = items > 0 || device.busy == true || slots.used > 0
    private static func isBusy(items: [ActivityItem], device: DeviceActivity?) -> Bool {
        items.count > 0 || device?.busy == true || (device?.slots?.used ?? 0) > 0
    }

    private static func machineState(_ machine: FleetMachine?, busy: Bool) -> FleetNodeState {
        guard let machine = machine, machine.state == "online" else { return .offline }
        return busy ? .working : .idle
    }

    private static func dotCount(itemsCount: Int, slotsUsed: Int, busy: Bool) -> Int {
        let raw = itemsCount > 0 ? itemsCount : (slotsUsed > 0 ? slotsUsed : (busy ? 1 : 0))
        return min(MAX_MAP_DOTS, max(0, raw))
    }

    /// Newest-first by `since` (ISO strings compare lexicographically); items without a
    /// start time sort last; original order preserved on ties.
    private static func toJobs(_ items: [ActivityItem]) -> [FleetJob] {
        items.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.since, rhs.element.since) {
                case (nil, nil):
                    return lhs.offset < rhs.offset
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case let (a?, b?):
                    if a == b { return lhs.offset < rhs.offset }
                    return a > b
                }
            }
            .map { FleetJob(key: $0.element.id, label: $0.element.label,
                            step: $0.element.lastStep, elapsedSec: $0.element.elapsedSec) }
    }
}
