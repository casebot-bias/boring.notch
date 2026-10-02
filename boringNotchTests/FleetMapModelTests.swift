//
//  FleetMapModelTests.swift
//  boringNotchTests
//
//  Unit tests for `FleetMapBuilder`, the Swift port of
//  fleet-dashboard/lib/fleet/map-model.ts (`buildMapModel`).
//  `FleetModels.swift` and `FleetMapModel.swift` are compiled directly into this
//  test module, so no `@testable import` is needed. All snapshots are built by
//  decoding inline JSON literals — no network access, no bundled fixture files.
//

import XCTest

final class FleetMapModelTests: XCTestCase {

    // MARK: - Helpers

    /// Decodes a `FleetSnapshot` from an inline JSON literal; fails (without crashing) on error.
    private func decodedFleet(_ json: String, file: StaticString = #file, line: UInt = #line) -> FleetSnapshot? {
        do {
            return try FleetSnapshot.decode(Data(json.utf8))
        } catch {
            XCTFail("FleetSnapshot.decode failed: \(error)", file: file, line: line)
            return nil
        }
    }

    /// Decodes an `ActivitySnapshot` from an inline JSON literal; fails (without crashing) on error.
    private func decodedActivity(_ json: String, file: StaticString = #file, line: UInt = #line) -> ActivitySnapshot? {
        do {
            return try ActivitySnapshot.decode(Data(json.utf8))
        } catch {
            XCTFail("ActivitySnapshot.decode failed: \(error)", file: file, line: line)
            return nil
        }
    }

    /// Looks up a map node by id, failing the test (instead of force-unwrapping) when absent.
    private func mapNode(_ model: FleetMapModel, _ id: String,
                         file: StaticString = #file, line: UInt = #line) -> FleetMapNode? {
        guard let node = model.nodes.first(where: { $0.id == id }) else {
            XCTFail("map node \"\(id)\" missing from \(model.nodes.map(\.id))", file: file, line: line)
            return nil
        }
        return node
    }

    // MARK: - JSON literal builders (the models only expose `init(from:)`)

    private func machineJSON(_ id: String, state: String = "online") -> String {
        return "{\"id\":\"\(id)\",\"title\":\"\(id)\",\"state\":\"\(state)\"}"
    }

    private func fleetJSON(_ machines: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"machines\":[\(machines.joined(separator: ","))]}"
    }

    private func itemJSON(_ label: String, device: String, model: String? = nil, since: String? = nil,
                          lastStep: String? = nil, elapsedSec: Int? = nil) -> String {
        var fields = ["\"label\":\"\(label)\"", "\"device\":\"\(device)\""]
        if let model = model { fields.append("\"model\":\"\(model)\"") }
        if let since = since { fields.append("\"since\":\"\(since)\"") }
        if let lastStep = lastStep { fields.append("\"lastStep\":\"\(lastStep)\"") }
        if let elapsedSec = elapsedSec { fields.append("\"elapsedSec\":\(elapsedSec)") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func deviceJSON(_ device: String, busy: Bool? = nil, items: [String] = [], slotsUsed: Int? = nil) -> String {
        var fields = ["\"device\":\"\(device)\""]
        if let busy = busy { fields.append("\"busy\":\(busy ? "true" : "false")") }
        fields.append("\"items\":[\(items.joined(separator: ","))]")
        if let slotsUsed = slotsUsed {
            fields.append("\"slots\":{\"used\":\(slotsUsed),\"total\":4,\"busy\":[]}")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func activityJSON(_ devices: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"devices\":[\(devices.joined(separator: ","))]}"
    }

    /// Fleet snapshot with all four machines reporting `state == "online"`.
    private func onlineFleetJSON() -> String {
        return fleetJSON([machineJSON("case"), machineJSON("frank"), machineJSON("dali"), machineJSON("macbook")])
    }

    // MARK: - 1. Cold start: both feeds nil

    /// Rule: with no fleet and no activity, the map is the fixed five-node layout
    /// [frank, dali, cloud, nova, macbook] plus the `case` origin — every node and the
    /// origin offline, nothing busy, zero active, nothing sent out.
    func testNilFleetAndActivityProduceFiveOfflineNodesAndEmptyModel() {
        let model = FleetMapBuilder.build(fleet: nil, activity: nil)

        XCTAssertEqual(model.nodes.map(\.id), ["frank", "dali", "cloud", "nova", "macbook"])
        XCTAssertEqual(model.nodes.map(\.label), ["frank", "dali", "cloud", "nova", "MacBook"])
        XCTAssertEqual(model.origin.id, "case")
        XCTAssertEqual(model.origin.label, "case")
        XCTAssertTrue(model.nodes.allSatisfy { $0.state == .offline })
        XCTAssertEqual(model.origin.state, .offline)
        XCTAssertTrue(model.nodes.allSatisfy { !$0.busy })
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.sentOut, 0)
    }

    // MARK: - 2. Frank busy from the activity feed only

    /// Rule: an online frank machine whose device reports `busy == true` with two items
    /// yields a working, busy frank node with dots == item count and jobs sorted
    /// newest-first by `since`; the only busy node makes activeCount 1 while the idle
    /// origin's busy flag/state is tracked separately (and excluded from the count).
    func testFrankBusyFromActivityFeedDrivesNodeAndActiveCount() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("frank", busy: true, items: [
                      itemJSON("frank-a", device: "frank", since: "2026-10-02T06:00:00.000Z",
                               lastStep: "Indexing repo", elapsedSec: 600),
                      itemJSON("frank-b", device: "frank", since: "2026-10-02T06:30:00.000Z",
                               lastStep: "Running tests", elapsedSec: 120)
                  ])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let frank = mapNode(model, "frank") else { return }

        XCTAssertEqual(frank.state, .working)
        XCTAssertTrue(frank.busy)
        XCTAssertEqual(frank.dots, 2)
        // Newest-first: frank-b (06:30) must precede frank-a (06:00), reversing feed order.
        XCTAssertEqual(frank.jobs.map(\.label), ["frank-b", "frank-a"])
        // `file` absent -> ActivityItem.id is "label-since", which becomes the job key.
        XCTAssertEqual(frank.jobs.first?.key, "frank-b-2026-10-02T06:30:00.000Z")
        XCTAssertEqual(frank.jobs.first?.step, "Running tests")
        XCTAssertEqual(frank.jobs.first?.elapsedSec, 120)

        XCTAssertEqual(model.activeCount, 1)
        XCTAssertTrue(model.isBusy)
        // Origin busy is a separate signal: case has no items -> idle, not busy, and
        // origin would never enter activeCount anyway.
        XCTAssertEqual(model.origin.state, .idle)
        XCTAssertFalse(model.origin.busy)
    }

    /// Rule: dots = min(MAX_MAP_DOTS == 4, item count) — five items still show four dots.
    func testFrankItemDotsAreCappedAtFour() {
        let items = (1...5).map { itemJSON("job-\($0)", device: "frank") }
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("frank", busy: true, items: items)
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let frank = mapNode(model, "frank") else { return }

        XCTAssertTrue(frank.busy)
        XCTAssertEqual(frank.dots, 4)
        XCTAssertEqual(frank.jobs.count, 5)
    }

    // MARK: - 3. Slot-count fallback

    /// Rule: busy = items>0 || device.busy==true || slots.used>0 — a device with no
    /// items and `busy == false` is still busy (and working) when slots.used == 1,
    /// and its dots fall back to the slot count.
    func testSlotsUsedMarksDeviceBusyWithoutItems() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("frank", busy: false, items: [], slotsUsed: 1)
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let frank = mapNode(model, "frank") else { return }

        XCTAssertTrue(frank.busy)
        XCTAssertEqual(frank.state, .working)
        XCTAssertEqual(frank.dots, 1)
        XCTAssertEqual(model.activeCount, 1)
    }

    /// Rule: with `slots` missing entirely, busy == false and no items, the node is
    /// idle with zero dots (the frank default of 4 slots reports zero used).
    func testMissingSlotsWithNoBusyFlagAndNoItemsMeansIdle() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("frank", busy: false, items: [])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let frank = mapNode(model, "frank") else { return }

        XCTAssertFalse(frank.busy)
        XCTAssertEqual(frank.state, .idle)
        XCTAssertEqual(frank.dots, 0)
        XCTAssertTrue(frank.jobs.isEmpty)
        XCTAssertEqual(model.activeCount, 0)
    }

    // MARK: - 4. Origin (case) excluded from activeCount

    /// Rule: origin-local jobs (items on the case device feed with `device == "case"`)
    /// make the origin working and busy, yet every machine/cloud/nova node stays idle,
    /// so activeCount must remain 0 — a busy origin is never counted as active.
    func testBusyOriginIsNeverCountedInActiveCount() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("case", busy: true, items: [
                      itemJSON("origin-a", device: "case"),
                      itemJSON("origin-b", device: "case")
                  ])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)

        XCTAssertEqual(model.origin.state, .working)
        XCTAssertTrue(model.origin.busy)
        XCTAssertEqual(model.origin.jobs.count, 2)
        XCTAssertTrue(model.nodes.allSatisfy { !$0.busy })
        XCTAssertTrue(model.nodes.allSatisfy { $0.state == .idle })
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.sentOut, 0)
    }

    // MARK: - 5. Routing of the case device feed

    /// Rule: case items with `device == "cloud"` go to the cloud node, except models
    /// prefixed `openrouter` which go to nova; case items with `device == "frank"` or
    /// `"dali"` count toward sentOut and belong to the frank/dali nodes only (never to
    /// cloud/nova), and all case items remain visible on the origin.
    func testCaseFeedRoutesItemsToCloudNovaAndCountsSentOut() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("case", busy: true, items: [
                      itemJSON("qwen-job", device: "cloud", model: "qwencloud/x",
                               since: "2026-10-02T06:00:00.000Z"),
                      itemJSON("or-job", device: "cloud", model: "openrouter/y",
                               since: "2026-10-02T06:10:00.000Z"),
                      itemJSON("to-frank", device: "frank"),
                      itemJSON("to-dali", device: "dali")
                  ]),
                  // The same work as seen from the executing machines' own feeds.
                  deviceJSON("frank", busy: true, items: [itemJSON("to-frank", device: "frank")]),
                  deviceJSON("dali", busy: true, items: [itemJSON("to-dali", device: "dali")])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let cloud = mapNode(model, "cloud"), let nova = mapNode(model, "nova"),
              let frank = mapNode(model, "frank"), let dali = mapNode(model, "dali") else { return }

        // device == "cloud" with a qwencloud model -> cloud node only.
        XCTAssertTrue(cloud.busy)
        XCTAssertEqual(cloud.state, .working)
        XCTAssertEqual(cloud.jobs.map(\.label), ["qwen-job"])
        XCTAssertEqual(cloud.dots, 1)
        // device == "cloud" with an openrouter model -> nova node only.
        XCTAssertTrue(nova.busy)
        XCTAssertEqual(nova.state, .working)
        XCTAssertEqual(nova.jobs.map(\.label), ["or-job"])
        // device == "frank" / "dali" -> those machine nodes only, counted as sent out.
        XCTAssertEqual(model.sentOut, 2)
        XCTAssertTrue(frank.busy)
        XCTAssertEqual(frank.jobs.map(\.label), ["to-frank"])
        XCTAssertTrue(dali.busy)
        XCTAssertEqual(dali.jobs.map(\.label), ["to-dali"])
        // Origin keeps the full case feed.
        XCTAssertEqual(model.origin.jobs.count, 4)
        XCTAssertEqual(model.activeCount, 4)
    }

    // MARK: - 6. Offline machines and the inert MacBook

    /// Rule: node state is offline whenever the fleet machine is missing or not
    /// "online", regardless of what the device activity feed claims is busy.
    func testOfflineMachineNodeStaysOfflineEvenWhenDeviceReportsBusy() {
        guard let fleet = decodedFleet(fleetJSON([
                machineJSON("case"), machineJSON("frank"),
                machineJSON("dali", state: "offline"), machineJSON("macbook")
              ])),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("dali", busy: true, items: [itemJSON("dali-job", device: "dali")])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let dali = mapNode(model, "dali") else { return }

        XCTAssertEqual(dali.state, .offline)
        // Busy still reflects the device feed; state is governed by the machine.
        XCTAssertTrue(dali.busy)
        // A busy-but-offline node still counts toward active (faithful to the TS port).
        XCTAssertEqual(model.activeCount, 1)
    }

    /// Rule: the MacBook node is inert by construction — never busy, zero dots, no
    /// jobs — even when its activity device reports busy work.
    func testMacbookIsNeverBusyAndHasNoJobs() {
        guard let fleet = decodedFleet(onlineFleetJSON()),
              let activity = decodedActivity(activityJSON([
                  deviceJSON("macbook", busy: true, items: [itemJSON("macbook-job", device: "macbook")])
              ])) else { return }

        let model = FleetMapBuilder.build(fleet: fleet, activity: activity)
        guard let macbook = mapNode(model, "macbook") else { return }

        XCTAssertFalse(macbook.busy)
        XCTAssertEqual(macbook.dots, 0)
        XCTAssertTrue(macbook.jobs.isEmpty)
        // Online machine but never working: the busy input is hard-wired to false.
        XCTAssertEqual(macbook.state, .idle)
        XCTAssertEqual(model.activeCount, 0)
    }

    // MARK: - 7. cloudProvider classification

    /// Rule: model prefix "openrouter" -> "openrouter", prefix "qwencloud" ->
    /// "qwencloud", everything else (nil, empty, local models) -> "other".
    func testCloudProviderClassification() {
        XCTAssertEqual(FleetMapBuilder.cloudProvider("openrouter-jev"), "openrouter")
        XCTAssertEqual(FleetMapBuilder.cloudProvider("qwencloud/deepseek"), "qwencloud")
        XCTAssertEqual(FleetMapBuilder.cloudProvider(nil), "other")
        XCTAssertEqual(FleetMapBuilder.cloudProvider(""), "other")
        XCTAssertEqual(FleetMapBuilder.cloudProvider("frank"), "other")
    }
}
