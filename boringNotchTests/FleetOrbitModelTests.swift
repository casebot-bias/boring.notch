//
//  FleetOrbitModelTests.swift
//  boringNotchTests
//
//  Behaviour tests for FleetOrbitBuilder.build: lane states, metrics, job order/dedup, geometry.
//
import XCTest

final class FleetOrbitModelTests: XCTestCase {

    private func machineJSON(_ id: String, state: String = "online", cpu: Double? = nil,
                             ram: Double? = nil, temp: Double? = nil) -> String {
        var p = ["\"id\":\"\(id)\"", "\"title\":\"\(id)\"", "\"state\":\"\(state)\""]
        if let cpu = cpu { p.append("\"cpuLoadPct\":{\"value\":\(cpu),\"state\":\"ok\"}") }
        if let ram = ram { p.append("\"ramUsedPct\":{\"value\":\(ram),\"state\":\"ok\"}") }
        if let temp = temp { p.append("\"cpuTempC\":{\"value\":\(temp),\"state\":\"ok\"}") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func fleetJSON(_ machines: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"machines\":[\(machines.joined(separator: ","))]}"
    }

    private func itemJSON(_ label: String, device: String, model: String? = nil,
                          since: String? = nil, elapsedSec: Int? = nil, file: String? = nil) -> String {
        var p = ["\"label\":\"\(label)\"", "\"device\":\"\(device)\""]
        if let model = model { p.append("\"model\":\"\(model)\"") }
        if let since = since { p.append("\"since\":\"\(since)\"") }
        if let elapsedSec = elapsedSec { p.append("\"elapsedSec\":\(elapsedSec)") }
        if let file = file { p.append("\"file\":\"\(file)\"") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func deviceJSON(_ device: String, busy: Bool? = nil, items: [String] = [],
                            slotsUsed: Int? = nil, tokPerSec: Double? = nil) -> String {
        var p = ["\"device\":\"\(device)\"", "\"items\":[\(items.joined(separator: ","))]"]
        if let busy = busy { p.append("\"busy\":\(busy ? "true" : "false")") }
        if let slotsUsed = slotsUsed { p.append("\"slots\":{\"used\":\(slotsUsed),\"total\":4,\"busy\":[]}") }
        if let tokPerSec = tokPerSec { p.append("\"tokPerSec\":\(tokPerSec)") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func activityJSON(_ devices: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"devices\":[\(devices.joined(separator: ","))]}"
    }

    /// case, frank (37.5°, 85% RAM), claire, dali (51°), macbook (68.3°), ciri (no readings); all online.
    private func onlineFleetJSON() -> String {
        return fleetJSON([machineJSON("case"), machineJSON("frank", ram: 85, temp: 37.5), machineJSON("claire"),
                          machineJSON("dali", temp: 51), machineJSON("macbook", temp: 68.3), machineJSON("ciri")])
    }

    private func fleet(_ json: String, file: StaticString = #file, line: UInt = #line) -> FleetSnapshot? {
        do { return try FleetSnapshot.decode(Data(json.utf8)) }
        catch { XCTFail("fleet JSON failed to decode: \(error)\n\(json)", file: file, line: line); return nil }
    }

    private func activity(_ json: String, file: StaticString = #file, line: UInt = #line) -> ActivitySnapshot? {
        do { return try ActivitySnapshot.decode(Data(json.utf8)) }
        catch { XCTFail("activity JSON failed to decode: \(error)\n\(json)", file: file, line: line); return nil }
    }

    private func lane(_ model: FleetOrbitModel, _ id: String,
                      file: StaticString = #file, line: UInt = #line) -> FleetLane? {
        guard let lane = model.lanes.first(where: { $0.id == id }) else {
            XCTFail("no lane \"\(id)\"; lanes are \(model.lanes.map(\.id))", file: file, line: line)
            return nil
        }
        return lane
    }

    func testNilSnapshotsGiveOfflineRingAndCaseOrigin() {
        let model = FleetOrbitBuilder.build(fleet: nil, activity: nil)
        XCTAssertEqual(model.nodes.map(\.id), ["frank", "claire", "dali", "nova", "ciri", "macbook"])
        XCTAssertEqual(model.nodes.map(\.label), ["frank", "claire", "dali", "nova", "ciri", "mac"])
        XCTAssertEqual(model.nodes.map(\.kind), [.gpu, .gpu, .gpu, .cloud, .agent, .mac])
        XCTAssertEqual(model.nodes.map(\.state), [.offline, .offline, .offline, .offline, .offline, .offline])
        XCTAssertEqual(model.origin.id, "case")
        XCTAssertEqual(model.origin.label, "case")
        XCTAssertEqual(model.origin.kind, .host)
        XCTAssertEqual(model.origin.state, .offline)
        XCTAssertEqual(model.lanes.map(\.id), ["case", "frank", "claire", "dali", "nova", "ciri", "macbook"])
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.nowJobs.isEmpty)
    }

    func testBusyFrankLaneJobsAreNewestFirstWithTokens() {
        let items = [itemJSON("frank-a", device: "frank", since: "2026-10-02T06:00:00.000Z", elapsedSec: 600),
                     itemJSON("frank-b", device: "frank", since: "2026-10-02T06:30:00.000Z", elapsedSec: 120)]
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("frank", busy: true, items: items, tokPerSec: 42)])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        guard let frank = lane(model, "frank") else { return }
        XCTAssertEqual(frank.state, .busy)
        XCTAssertTrue(frank.busy)
        XCTAssertEqual(frank.jobs.map(\.label), ["frank-b", "frank-a"])
        XCTAssertEqual(frank.jobs.first?.key, "frank-b-2026-10-02T06:30:00.000Z")
        XCTAssertEqual(frank.jobs.first?.pill, "frank")
        XCTAssertEqual(frank.right, "42 t/s")
        XCTAssertEqual(model.activeCount, 1)
    }

    func testIdleGpuShowsTemperatureAndZeroTokensFallBackToTemperature() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([
                  deviceJSON("frank", busy: false, tokPerSec: 0),
                  deviceJSON("dali", busy: true, items: [itemJSON("dali-x", device: "dali")], tokPerSec: 0),
              ])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        guard let frank = lane(model, "frank"), let dali = lane(model, "dali") else { return }
        XCTAssertEqual(frank.state, .idle)
        XCTAssertEqual(frank.right, "38°")                       // 37.5 rounds up
        XCTAssertEqual(dali.state, .busy)
        XCTAssertEqual(dali.right, "51°")                         // never "0 t/s"
    }

    func testCiriLaneJobCountsAndEmptyBars() {
        func ciriLane(_ items: [String], _ busy: Bool, _ json: String) -> FleetLane? {
            guard let f = fleet(json), let a = activity(activityJSON([deviceJSON("ciri", busy: busy, items: items)])) else { return nil }
            return lane(FleetOrbitBuilder.build(fleet: f, activity: a), "ciri")
        }
        let of = onlineFleetJSON()
        let three = (1...3).map { itemJSON("ciri-\($0)", device: "ciri", file: "/tmp/c\($0).jsonl") }
        guard let ciri = ciriLane(three, true, of), let one = ciriLane([three[0]], true, of),
              let empty = ciriLane([], true, of), let idle = ciriLane([], false, of) else { return }
        XCTAssertEqual(ciri.kind, .agent)
        XCTAssertEqual(ciri.state, .busy)
        XCTAssertEqual(ciri.right, "3 jobs")
        XCTAssertEqual(FleetFormat.barFraction(ciri.cpu), 0)      // ciri reports no readings
        XCTAssertEqual(FleetFormat.barFraction(ciri.ram), 0)
        XCTAssertEqual(one.right, "1 job")
        XCTAssertEqual(empty.right, "1 job")                      // busy with no items is max(count, 1)
        XCTAssertEqual(idle.state, .idle)
        XCTAssertEqual(idle.right, "idle")
        let noCiri = fleetJSON(["case", "frank", "claire", "dali", "macbook"].map { machineJSON($0) })
        guard let off = ciriLane([], true, noCiri) else { return }
        XCTAssertEqual(off.state, .offline)
        XCTAssertEqual(off.right, "—")
    }

    func testOfflineMachineBeatsBusyDevice() {
        let json = fleetJSON([machineJSON("case"), machineJSON("frank"), machineJSON("claire"),
                              machineJSON("dali", state: "offline"), machineJSON("macbook"), machineJSON("ciri")])
        let dali = deviceJSON("dali", busy: true, items: [itemJSON("dali-x", device: "dali")])
        guard let f = fleet(json), let a = activity(activityJSON([dali])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        guard let daliLane = lane(model, "dali") else { return }
        XCTAssertEqual(daliLane.state, .offline)
        XCTAssertFalse(daliLane.busy)
        XCTAssertEqual(daliLane.right, "—")
        XCTAssertEqual(model.activeCount, 0)
    }

    func testNovaFollowsOpenrouterJobs() {
        let qwen = itemJSON("qwen-job", device: "cloud", model: "qwencloud/x", since: "2026-10-02T06:00:00.000Z")
        let openrouter = itemJSON("or-job", device: "cloud", model: "openrouter/y", since: "2026-10-02T06:10:00.000Z")
        let items = [qwen, openrouter, itemJSON("to-frank", device: "frank")]
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: items)])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        guard let nova = lane(model, "nova") else { return }
        XCTAssertEqual(nova.state, .busy)
        XCTAssertEqual(nova.right, "live")
        XCTAssertEqual(nova.jobs.map(\.label), ["or-job"])        // qwen job excluded
        XCTAssertEqual(model.activeCount, 2)                      // case + nova
        guard let a2 = activity(activityJSON([deviceJSON("case", busy: true, items: [qwen])])) else { return }
        guard let nova2 = lane(FleetOrbitBuilder.build(fleet: f, activity: a2), "nova") else { return }
        XCTAssertEqual(nova2.state, .idle)
        XCTAssertEqual(nova2.right, "idle")
    }

    func testNovaIsOfflineWithoutFleet() {
        let orItem = itemJSON("or-job", device: "cloud", model: "openrouter/y", since: "2026-10-02T06:10:00.000Z")
        guard let a = activity(activityJSON([deviceJSON("case", busy: true, items: [orItem])])) else { return }
        guard let nova = lane(FleetOrbitBuilder.build(fleet: nil, activity: a), "nova") else { return }
        XCTAssertEqual(nova.state, .offline)
        XCTAssertEqual(nova.right, "—")
    }

    func testCaseOriginCountsOnceAndShowsTemperature() {
        let json = fleetJSON([machineJSON("case", temp: 38.37), machineJSON("frank"), machineJSON("claire"),
                              machineJSON("dali"), machineJSON("macbook"), machineJSON("ciri")])
        guard let f = fleet(json),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: [
                  itemJSON("case-a", device: "case", since: "2026-10-02T06:00:00.000Z", elapsedSec: 120),
                  itemJSON("case-b", device: "case", since: "2026-10-02T06:20:00.000Z", elapsedSec: 60),
              ])])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        XCTAssertEqual(model.origin.state, .busy)
        XCTAssertEqual(model.origin.kind, .host)
        XCTAssertEqual(model.origin.jobs.count, 2)
        XCTAssertEqual(model.origin.right, "38°")
        XCTAssertEqual(model.activeCount, 1)                      // case counts once only
        XCTAssertEqual(model.nodes.map(\.state), [.idle, .idle, .idle, .idle, .idle, .idle])
    }

    func testNowJobsDedupAndNewestFirst() {
        let caseItems = [itemJSON("to-frank", device: "frank", elapsedSec: 600, file: "/tmp/a.jsonl"),
                         itemJSON("own", device: "case", elapsedSec: 30, file: "/tmp/b.jsonl")]
        let frankItems = [itemJSON("to-frank", device: "frank", elapsedSec: 610, file: "/tmp/a.jsonl")]
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: caseItems),
                                             deviceJSON("frank", busy: true, items: frankItems)])) else { return }
        let model = FleetOrbitBuilder.build(fleet: f, activity: a)
        // Deduped by key keeping the first lane walked (case); smaller elapsed = newer first.
        XCTAssertEqual(model.nowJobs.map(\.key), ["/tmp/b.jsonl", "/tmp/a.jsonl"])
        let shared = model.nowJobs.first { $0.key == "/tmp/a.jsonl" }
        XCTAssertEqual(shared?.pill, "frank")
        XCTAssertEqual(shared?.elapsedSec, 600)
    }

    func testMacbookAndSlotsFallback() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("macbook", busy: true,
                                                        items: [itemJSON("mb-x", device: "macbook")])])) else { return }
        guard let mac = lane(FleetOrbitBuilder.build(fleet: f, activity: a), "macbook") else { return }
        XCTAssertEqual(mac.label, "mac")
        XCTAssertEqual(mac.state, .busy)
        XCTAssertEqual(mac.right, "68°")
        guard let a2 = activity(activityJSON([deviceJSON("frank", busy: false, slotsUsed: 2)])) else { return }
        let model2 = FleetOrbitBuilder.build(fleet: f, activity: a2)
        guard let frank = lane(model2, "frank") else { return }
        XCTAssertEqual(frank.state, .busy)                        // slots.used > 0 counts as busy
        XCTAssertEqual(model2.activeCount, 1)
    }

    func testRingGeometryFollowsNodeCount() {
        // angle = -pi/2 + 2pi*i/count; radius 58 about (75, 75); labels at 78cos, 74sin + 3.
        let ring: [(Int, Int, CGFloat, CGFloat)] = [(0, 6, 75, 17), (3, 6, 75, 133), (1, 4, 133, 75), (0, 0, 75, 75)]
        for (index, count, x, y) in ring {
            let p = FleetOrbitBuilder.position(index: index, count: count)
            XCTAssertEqual(p.x, x, accuracy: 0.001)
            XCTAssertEqual(p.y, y, accuracy: 0.001)
        }
        let label = FleetOrbitBuilder.labelPosition(index: 0, count: 6)
        XCTAssertEqual(label.x, 75, accuracy: 0.001)
        XCTAssertEqual(label.y, 4, accuracy: 0.001)
    }
}
