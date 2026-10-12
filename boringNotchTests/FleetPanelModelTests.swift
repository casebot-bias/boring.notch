//
//  FleetPanelModelTests.swift
//  boringNotchTests
//
//  Behaviour tests for FleetPanelModelBuilder.build: response-map lane order and
//  states, current-work job order/dedup, the unique-key runningTaskCount, nova's
//  cloud routing, the fleet-wide tok/s sum (a reported 0 stays 0) and the
//  per-machine cpu/gpu/ram footer readings.
//
import XCTest

final class FleetPanelModelTests: XCTestCase {

    private func machineJSON(_ id: String, title: String? = nil, state: String = "online",
                             cpu: Double? = nil, gpu: Double? = nil, ram: Double? = nil) -> String {
        var p = ["\"id\":\"\(id)\"", "\"title\":\"\(title ?? id)\"", "\"state\":\"\(state)\""]
        if let cpu = cpu { p.append("\"cpuLoadPct\":{\"value\":\(cpu),\"state\":\"ok\"}") }
        if let gpu = gpu { p.append("\"gpuUtilPct\":{\"value\":\(gpu),\"state\":\"ok\"}") }
        if let ram = ram { p.append("\"ramUsedPct\":{\"value\":\(ram),\"state\":\"ok\"}") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func fleetJSON(_ machines: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"machines\":[\(machines.joined(separator: ","))]}"
    }

    private func itemJSON(_ label: String, device: String, model: String? = nil,
                          since: String? = nil, lastStep: String? = nil,
                          elapsedSec: Int? = nil, file: String? = nil) -> String {
        var p = ["\"label\":\"\(label)\"", "\"device\":\"\(device)\""]
        if let model = model { p.append("\"model\":\"\(model)\"") }
        if let since = since { p.append("\"since\":\"\(since)\"") }
        if let lastStep = lastStep { p.append("\"lastStep\":\"\(lastStep)\"") }
        if let elapsedSec = elapsedSec { p.append("\"elapsedSec\":\(elapsedSec)") }
        if let file = file { p.append("\"file\":\"\(file)\"") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func deviceJSON(_ device: String, busy: Bool? = nil, items: [String] = [],
                            slotsUsed: Int? = nil, tokPerSec: Double? = nil,
                            odinStatus: String? = nil, odinOpen: String? = nil) -> String {
        var p = ["\"device\":\"\(device)\"", "\"items\":[\(items.joined(separator: ","))]"]
        if let busy = busy { p.append("\"busy\":\(busy ? "true" : "false")") }
        if let slotsUsed = slotsUsed { p.append("\"slots\":{\"used\":\(slotsUsed),\"total\":4,\"busy\":[]}") }
        if let tokPerSec = tokPerSec { p.append("\"tokPerSec\":\(tokPerSec)") }
        var odin: [String] = []
        if let odinStatus = odinStatus { odin.append("\"status\":\(odinStatus)") }
        if let odinOpen = odinOpen { odin.append("\"open\":\(odinOpen)") }
        if !odin.isEmpty { p.append("\"odin\":{" + odin.joined(separator: ",") + "}") }
        return "{" + p.joined(separator: ",") + "}"
    }

    private func activityJSON(_ devices: [String]) -> String {
        return "{\"generatedAt\":\"2026-10-02T07:00:00.000Z\",\"devices\":[\(devices.joined(separator: ","))]}"
    }

    /// case, frank, claire, ciri, dali, macbook, odin; all online, no readings.
    /// There is no "nova" machine: the nova lane is the pool of openrouter cloud
    /// jobs the case runs, so it deliberately has no fleet machine here.
    private func onlineFleetJSON() -> String {
        return fleetJSON(["case", "frank", "claire", "ciri", "dali", "macbook", "odin"].map { machineJSON($0) })
    }

    private func fleet(_ json: String, file: StaticString = #file, line: UInt = #line) -> FleetSnapshot? {
        do { return try FleetSnapshot.decode(Data(json.utf8)) }
        catch { XCTFail("fleet JSON failed to decode: \(error)\n\(json)", file: file, line: line); return nil }
    }

    private func activity(_ json: String, file: StaticString = #file, line: UInt = #line) -> ActivitySnapshot? {
        do { return try ActivitySnapshot.decode(Data(json.utf8)) }
        catch { XCTFail("activity JSON failed to decode: \(error)\n\(json)", file: file, line: line); return nil }
    }

    private func lane(_ model: FleetPanelModel, _ id: String,
                      file: StaticString = #file, line: UInt = #line) -> FleetLane? {
        guard let lane = model.lanes.first(where: { $0.id == id }) else {
            XCTFail("no lane \"\(id)\"; lanes are \(model.lanes.map(\.id))", file: file, line: line)
            return nil
        }
        return lane
    }

    /// The panel model for a feed whose last poll answered: every test but the stale ones reads fresh data.
    private func panel(fleet: FleetSnapshot?, activity: ActivitySnapshot?) -> FleetPanelModel {
        FleetPanelModelBuilder.build(fleet: fleet, activity: activity, fleetLive: true)
    }

    // MARK: - Empty snapshots

    func testNilSnapshotsGiveOfflineLanesAndUnknownFooterReadings() {
        let model = panel(fleet: nil, activity: nil)
        XCTAssertEqual(model.origin.id, "case")
        XCTAssertEqual(model.origin.label, "case")
        XCTAssertEqual(model.origin.state, .offline)
        XCTAssertFalse(model.origin.isLinked)
        XCTAssertTrue(model.origin.jobs.isEmpty)
        XCTAssertEqual(model.agents.map(\.id), ["frank", "claire", "ciri", "dali", "nova", "pika", "odin"])
        XCTAssertEqual(model.agents.map(\.label), ["frank", "claire", "ciri", "dali", "nova", "pika", "odin"])
        XCTAssertEqual(model.agents.map(\.state),
                       [.offline, .offline, .offline, .offline, .offline, .idle, .offline])
        XCTAssertEqual(model.agents.map(\.isLinked),
                       [false, false, false, false, false, true, false])
        XCTAssertEqual(model.agentCount, 7)
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 1)
        XCTAssertEqual(model.criticalCount, 6)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.totalTokPerSec)
        XCTAssertEqual(model.runningTaskCount, 0)
        XCTAssertTrue(model.nowJobs.isEmpty)
        // The footer keeps its five slots even when the fleet never answers: no readings, no arcs.
        XCTAssertEqual(model.hosts.map(\.label), ["case", "frank", "claire", "dali", "mac"])
        for host in model.hosts {
            XCTAssertFalse(host.live, "\(host.id) must be offline")
            for kind in FleetRingKind.allCases {
                XCTAssertNil(host.value(kind), "\(host.id) \(kind.rawValue) must report no value")
                XCTAssertNil(host.arcFraction(kind), "\(host.id) \(kind.rawValue) must draw no arc")
            }
            XCTAssertEqual(FleetFormat.ringHeadline(host), "—")
        }
    }

    func testAgentOrderIsFixedAndLanesStartWithCase() {
        let model = panel(fleet: nil, activity: nil)
        XCTAssertEqual(FleetPanelModelBuilder.agentIds, ["frank", "claire", "ciri", "dali", "nova", "pika", "odin"])
        XCTAssertEqual(model.agents.map(\.id), FleetPanelModelBuilder.agentIds)
        XCTAssertEqual(model.lanes.first?.id, "case")
        XCTAssertEqual(model.lanes, [model.origin] + model.agents)
        XCTAssertEqual(model.lanes.count, model.agentCount + 1)
    }

    // MARK: - Busy lanes and jobs

    func testBusyFrankLaneJobsAreNewestFirstWithKeysPillsAndSteps() {
        let items = [itemJSON("frank-a", device: "frank", since: "2026-10-02T06:00:00.000Z",
                              lastStep: "building the parser", elapsedSec: 600, file: "/tmp/frank-a.jsonl"),
                     itemJSON("frank-b", device: "frank", since: "2026-10-02T06:30:00.000Z",
                              lastStep: "reviewing the diff", elapsedSec: 120)]
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("frank", busy: true, items: items, tokPerSec: 42.4)])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let frank = lane(model, "frank") else { return }
        XCTAssertEqual(frank.state, .busy)
        XCTAssertTrue(frank.isLinked)
        XCTAssertEqual(frank.jobs.map(\.label), ["frank-b", "frank-a"])   // newest `since` first
        XCTAssertEqual(frank.jobs.map(\.key), ["frank-b-2026-10-02T06:30:00.000Z", "/tmp/frank-a.jsonl"])
        XCTAssertEqual(frank.jobs.map(\.id), frank.jobs.map(\.key))       // key from file, else label-since
        XCTAssertEqual(frank.jobs.map(\.pill), ["frank", "frank"])
        XCTAssertEqual(frank.jobs.map(\.step), ["reviewing the diff", "building the parser"])
        XCTAssertEqual(frank.jobs.map(\.elapsedSec), [120, 600])
        XCTAssertEqual(model.origin.state, .idle)
        XCTAssertTrue(model.origin.isLinked)
        XCTAssertEqual(model.workingCount, 1)
        XCTAssertEqual(model.linkedCount, 7)
        XCTAssertEqual(model.criticalCount, 0)
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.runningTaskCount, 2)                          // frank's two jobs, nothing else
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)            // unique keys, not a per-lane sum
        XCTAssertEqual(model.totalTokPerSec ?? 0, 42.4, accuracy: 0.001)
        XCTAssertEqual(model.nowJobs.map(\.key), ["frank-b-2026-10-02T06:30:00.000Z", "/tmp/frank-a.jsonl"])
    }

    func testBusyFlagAndSlotsFallback() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("frank", busy: false, slotsUsed: 2),        // slots carry it
                                             deviceJSON("dali", busy: true, items: []),             // busy flag alone
                                             deviceJSON("ciri", busy: false, slotsUsed: 0)])) else { return } // neither
        let model = panel(fleet: f, activity: a)
        guard let frank = lane(model, "frank"), let dali = lane(model, "dali"), let ciri = lane(model, "ciri") else { return }
        XCTAssertEqual(frank.state, .busy)                                 // slots.used > 0 counts as busy
        XCTAssertTrue(frank.jobs.isEmpty)
        XCTAssertEqual(dali.state, .busy)                                  // busy == true with no items
        XCTAssertEqual(ciri.state, .idle)                                  // nothing claims work
        XCTAssertEqual(model.workingCount, 2)
        XCTAssertTrue(model.isBusy)
        XCTAssertTrue(model.nowJobs.isEmpty)                                // busy lanes with no jobs
    }

    // MARK: - Offline precedence

    func testOfflineMachineBeatsBusyDevice() {
        let json = fleetJSON([machineJSON("case"), machineJSON("frank"), machineJSON("claire"),
                              machineJSON("ciri"), machineJSON("dali", state: "unreachable"),
                              machineJSON("macbook"), machineJSON("odin")])
        let daliDevice = deviceJSON("dali", busy: true, items: [itemJSON("dali-x", device: "dali")])
        guard let f = fleet(json), let a = activity(activityJSON([daliDevice])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let dali = lane(model, "dali") else { return }
        XCTAssertEqual(dali.state, .offline)                                // offline wins over the busy device
        XCTAssertFalse(dali.isLinked)
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 6)
        XCTAssertEqual(model.criticalCount, 1)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.totalTokPerSec)
        XCTAssertEqual(model.runningTaskCount, 0)                               // the offline lane's job adds nothing
    }

    // MARK: - Nova (openrouter cloud pool, not a machine)

    func testNovaLaneFollowsOpenrouterJobsOnly() {
        let qwen = itemJSON("qwen-job", device: "cloud", model: "qwencloud/qwq",
                            since: "2026-10-02T06:00:00.000Z", lastStep: "compiling", elapsedSec: 300)
        let openrouter = itemJSON("or-job", device: "cloud", model: "openrouter/deepseek",
                                 since: "2026-10-02T06:10:00.000Z", lastStep: "summarising the findings", elapsedSec: 60)
        let plain = itemJSON("plain-job", device: "cloud", since: "2026-10-02T06:05:00.000Z")   // no model -> other
        let delegated = itemJSON("to-frank", device: "frank", since: "2026-10-02T06:20:00.000Z")
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("case", busy: true,
                                                        items: [qwen, openrouter, plain, delegated])])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let nova = lane(model, "nova") else { return }
        XCTAssertEqual(nova.id, "nova")
        XCTAssertEqual(nova.label, "nova")
        XCTAssertEqual(nova.state, .busy)
        XCTAssertTrue(nova.isLinked)
        XCTAssertEqual(nova.jobs.map(\.label), ["or-job"])                  // qwen + modelless cloud jobs excluded
        XCTAssertEqual(nova.jobs.map(\.key), ["or-job-2026-10-02T06:10:00.000Z"])
        XCTAssertEqual(nova.jobs.map(\.pill), ["nova"])
        XCTAssertEqual(nova.jobs.first?.step, "summarising the findings")
        XCTAssertEqual(nova.jobs.first?.elapsedSec, 60)
        // The case origin still owns every delegated item, branded by provider.
        XCTAssertEqual(model.origin.jobs.map(\.label), ["to-frank", "or-job", "plain-job", "qwen-job"])
        XCTAssertEqual(model.origin.jobs.map(\.pill), ["frank", "nova", "case", "case"])
        XCTAssertEqual(model.workingCount, 1)                                // nova (agents only; case is origin)
        XCTAssertEqual(model.runningTaskCount, 4)     // case's 4 items; nova's openrouter run is one of them, counted once
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)            // same keys as the deduped walk
        XCTAssertEqual(model.linkedCount, 7)
        XCTAssertEqual(model.criticalCount, 0)
        // Qwen-only activity leaves nova idle (case keeps working via its items).
        guard let a2 = activity(activityJSON([deviceJSON("case", busy: true, items: [qwen])])) else { return }
        guard let nova2 = lane(panel(fleet: f, activity: a2), "nova") else { return }
        XCTAssertEqual(nova2.state, .idle)
        XCTAssertTrue(nova2.isLinked)
        XCTAssertTrue(nova2.jobs.isEmpty)
        XCTAssertEqual(FleetPanelModelBuilder.cloudProvider("openrouter/deepseek-r1"), "openrouter")
        XCTAssertEqual(FleetPanelModelBuilder.cloudProvider("qwencloud/qwq"), "qwencloud")
        XCTAssertEqual(FleetPanelModelBuilder.cloudProvider("gpt-5"), "other")
        XCTAssertEqual(FleetPanelModelBuilder.cloudProvider(nil), "other")
        XCTAssertEqual(FleetPanelModelBuilder.cloudProvider(""), "other")
    }

    func testNovaIsOfflineWithoutFleetAndLeaksNoJobs() {
        let orItem = itemJSON("or-job", device: "cloud", model: "openrouter/deepseek",
                              since: "2026-10-02T06:10:00.000Z", elapsedSec: 60)
        guard let a = activity(activityJSON([deviceJSON("case", busy: true, items: [orItem])])) else { return }
        let model = panel(fleet: nil, activity: a)
        guard let nova = lane(model, "nova") else { return }
        XCTAssertEqual(nova.state, .offline)                                 // no fleet snapshot -> unknown
        XCTAssertFalse(nova.isLinked)
        XCTAssertEqual(model.origin.state, .offline)
        XCTAssertEqual(model.criticalCount, 6)
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.nowJobs.isEmpty)                                 // offline lanes leak no jobs
        XCTAssertEqual(model.runningTaskCount, 0)                               // offline lanes leak no tasks either
    }

    // MARK: - Case origin, dedup, nowJobs

    func testCaseOriginCountsOnceAndNowJobsDedupKeepFirstLane() {
        let shared = itemJSON("delegated", device: "frank", since: "2026-10-02T06:00:00.000Z",
                              lastStep: "wiring the bridge", elapsedSec: 600, file: "/tmp/a.jsonl")
        let own = itemJSON("own", device: "case", since: "2026-10-02T06:20:00.000Z",
                          lastStep: "reading the report", elapsedSec: 30, file: "/tmp/b.jsonl")
        let slow = itemJSON("slow-burn", device: "case", since: "2026-10-02T06:15:00.000Z")  // elapsed unknown -> last
        // The same file is reported by both case and frank, with different elapsedSec.
        let frankCopy = itemJSON("delegated", device: "frank", since: "2026-10-02T06:00:00.000Z",
                                 lastStep: "wiring the bridge", elapsedSec: 610, file: "/tmp/a.jsonl")
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: [shared, own, slow]),
                                             deviceJSON("frank", busy: true, items: [frankCopy])])) else { return }
        let model = panel(fleet: f, activity: a)
        XCTAssertEqual(model.origin.state, .busy)
        XCTAssertEqual(model.origin.jobs.count, 3)
        XCTAssertEqual(model.runningTaskCount, 3)                              // unique keys: frank's copy of /tmp/a.jsonl counted once
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)            // matches the three keys asserted below
        guard let frank = lane(model, "frank") else { return }
        XCTAssertEqual(frank.jobs.first?.elapsedSec, 610)                      // the lane keeps its own copy
        // nowJobs walks case first: the shared key survives with the case lane's numbers;
        // smaller elapsed = newer; the unknown-elapsed job sinks to the end.
        XCTAssertEqual(model.nowJobs.map(\.key), ["/tmp/b.jsonl", "/tmp/a.jsonl", "slow-burn-2026-10-02T06:15:00.000Z"])
        let kept = model.nowJobs.first { $0.key == "/tmp/a.jsonl" }
        XCTAssertEqual(kept?.pill, "frank")
        XCTAssertEqual(kept?.elapsedSec, 600)
        XCTAssertEqual(kept?.step, "wiring the bridge")
    }

    func testCaseOriginBusyAloneMakesModelBusy() {
        let own = itemJSON("own", device: "case", since: "2026-10-02T06:20:00.000Z", elapsedSec: 30, file: "/tmp/b.jsonl")
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: [own])])) else { return }
        let model = panel(fleet: f, activity: a)
        XCTAssertEqual(model.origin.state, .busy)
        XCTAssertEqual(model.workingCount, 0)                                  // no *agent* is working
        XCTAssertTrue(model.isBusy)                                             // origin busy is enough
        XCTAssertEqual(model.runningTaskCount, 1)
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)
        XCTAssertEqual(model.nowJobs.map(\.key), ["/tmp/b.jsonl"])
    }

    func testRunningTaskCountCountsUniqueKeysAcrossBusyLanesAndSkipsOfflineLanes() {
        // Delegated work reported under the same file by case and frank, plus one
        // openrouter item nova derives from case; dali is offline but retains a job.
        let shared = itemJSON("delegated", device: "frank", since: "2026-10-02T06:00:00.000Z",
                              elapsedSec: 300, file: "/tmp/delegated.jsonl")
        let openrouter = itemJSON("or-job", device: "cloud", model: "openrouter/deepseek",
                                  since: "2026-10-02T06:05:00.000Z", elapsedSec: 60, file: "/tmp/or.jsonl")
        let frankOwn = itemJSON("frank-own", device: "frank", since: "2026-10-02T06:10:00.000Z",
                                elapsedSec: 120, file: "/tmp/frank-own.jsonl")
        let retained = itemJSON("dali-job", device: "dali", since: "2026-10-02T05:00:00.000Z",
                                file: "/tmp/dali-retained.jsonl")
        let json = fleetJSON([machineJSON("case"), machineJSON("frank"), machineJSON("claire"),
                              machineJSON("ciri"), machineJSON("dali", state: "unreachable"),
                              machineJSON("macbook"), machineJSON("odin")])
        guard let f = fleet(json),
              let a = activity(activityJSON([deviceJSON("case", busy: true, items: [shared, openrouter]),
                                             deviceJSON("frank", busy: true, items: [shared, frankOwn]),
                                             deviceJSON("dali", busy: true, items: [retained])])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let dali = lane(model, "dali") else { return }
        XCTAssertEqual(dali.state, .offline)
        XCTAssertEqual(dali.jobs.map(\.key), ["/tmp/dali-retained.jsonl"])     // jobs survive on the offline lane…
        XCTAssertEqual(model.runningTaskCount, 3)   // delegated + or-job + frank-own; the offline lane adds nothing
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)
        XCTAssertEqual(model.nowJobs.map(\.key), ["/tmp/or.jsonl", "/tmp/frank-own.jsonl", "/tmp/delegated.jsonl"])
    }

    // MARK: - Fleet output total

    func testTotalTokPerSecSumsAgentRatesOnly() {
        let devices = [deviceJSON("case", busy: true, tokPerSec: 999),        // origin: never summed
                       deviceJSON("frank", busy: true, tokPerSec: 42.4),
                       deviceJSON("dali", busy: true, tokPerSec: 10),
                       deviceJSON("ciri", busy: false)]                        // no rate reported
        guard let f = fleet(onlineFleetJSON()), let a = activity(activityJSON(devices)) else { return }
        let model = panel(fleet: f, activity: a)
        XCTAssertEqual(model.workingCount, 2)                                  // frank + dali
        XCTAssertEqual(model.totalTokPerSec ?? 0, 52.4, accuracy: 0.001)       // case's 999 excluded
        // No agent reports a rate: nil, not 0.
        let silent = [deviceJSON("case", busy: true), deviceJSON("frank", busy: false), deviceJSON("dali", busy: false)]
        guard let a2 = activity(activityJSON(silent)) else { return }
        let silentModel = panel(fleet: f, activity: a2)
        XCTAssertNil(silentModel.totalTokPerSec)                    // nil only when no agent reports a rate at all
        XCTAssertEqual(FleetFormat.fleetOutput(silentModel.totalTokPerSec), FleetFormat.unknown)
        // One reporting agent: its rate alone is the total.
        guard let a3 = activity(activityJSON([deviceJSON("frank", busy: true, tokPerSec: 7)])) else { return }
        XCTAssertEqual(panel(fleet: f, activity: a3).totalTokPerSec ?? 0, 7, accuracy: 0.001)
    }

    func testAgentReportingZeroThroughputShowsZeroNotDash() {
        let devices = [deviceJSON("case", busy: false),                        // origin: silent here
                       deviceJSON("frank", busy: false, tokPerSec: 0),         // idle frank reports a real 0
                       deviceJSON("dali", busy: false)]                         // no other agent reports a rate
        guard let f = fleet(onlineFleetJSON()), let a = activity(activityJSON(devices)) else { return }
        let model = panel(fleet: f, activity: a)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.totalTokPerSec, 0)                                  // 0, not nil
        XCTAssertEqual(FleetFormat.fleetOutput(model.totalTokPerSec), "0")       // renders "0", not "—"
        // Reported zeros don't mask a real rate.
        let mixed = [deviceJSON("frank", busy: false, tokPerSec: 0),
                     deviceJSON("dali", busy: true, tokPerSec: 12.4)]
        guard let a2 = activity(activityJSON(mixed)) else { return }
        let mixedModel = panel(fleet: f, activity: a2)
        XCTAssertEqual(mixedModel.totalTokPerSec ?? 0, 12.4, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.fleetOutput(mixedModel.totalTokPerSec), "12")
    }

    // MARK: - Footer host readings

    func testFooterHostsKeepTheOwnersOrderAndLabels() {
        XCTAssertEqual(FleetPanelModelBuilder.footerHosts.map(\.id), ["case", "frank", "claire", "dali", "macbook"])
        XCTAssertEqual(FleetPanelModelBuilder.footerHosts.map(\.label), ["case", "frank", "claire", "dali", "mac"])
        guard let f = fleet(onlineFleetJSON()) else { return }
        let hosts = panel(fleet: f, activity: nil).hosts
        XCTAssertEqual(hosts.map(\.id), ["case", "frank", "claire", "dali", "macbook"])
        XCTAssertEqual(hosts.map(\.label), ["case", "frank", "claire", "dali", "mac"])
        XCTAssertTrue(hosts.allSatisfy { $0.live }, "every machine in this payload is online")
        // Online machines that report nothing still hold their slot, with no arcs.
        XCTAssertTrue(hosts.allSatisfy { $0.cpu == nil && $0.gpu == nil && $0.ram == nil })
        XCTAssertTrue(hosts.allSatisfy { host in FleetRingKind.allCases.allSatisfy { host.arcFraction($0) == nil } })
    }

    func testFooterReadingsComeFromTheirOwnMachineOnly() {
        let json = fleetJSON([machineJSON("case", cpu: 6, gpu: 33, ram: 50),
                              machineJSON("frank", cpu: 0, gpu: 0, ram: 84),
                              machineJSON("claire", cpu: 0, gpu: 0, ram: 88),
                              machineJSON("dali", title: "Dali Studio", cpu: 3, gpu: 0, ram: 57),
                              machineJSON("macbook", title: "MacBook", cpu: 13, gpu: 13, ram: 75.4)])
        guard let f = fleet(json) else { return }
        let hosts = panel(fleet: f, activity: nil).hosts
        XCTAssertEqual(hosts.map(\.cpu), [6, 0, 0, 3, 13])          // not a fleet-wide peak: each machine keeps its own
        XCTAssertEqual(hosts.map(\.gpu), [33, 0, 0, 0, 13])
        XCTAssertEqual(hosts.map(\.ram), [50, 84, 88, 57, 75])      // 75.4 shows as 75
        XCTAssertEqual(hosts[4].label, "mac")                        // the machine title never leaks into the label
        // A reported 0 % is a reading, not a gap: it keeps its level and a zero sweep.
        XCTAssertEqual(hosts[1].arcFraction(.gpu), 0)
        XCTAssertEqual(FleetFormat.ringLevel(hosts[1].gpu), .ok)
    }

    func testOfflineMachineDrawsNoArcsButKeepsItsLastReadings() {
        let json = fleetJSON([machineJSON("frank", state: "unreachable", cpu: 13, gpu: 94, ram: 86)])
        guard let f = fleet(json) else { return }
        let hosts = panel(fleet: f, activity: nil).hosts
        let frank = hosts[1]
        XCTAssertFalse(frank.live)
        XCTAssertEqual(frank.ram, 86, "the last reported value stays readable as the cluster's text")
        for kind in FleetRingKind.allCases {
            XCTAssertNil(frank.arcFraction(kind), "an offline machine must draw no arc for \(kind.rawValue)")
        }
        let caseHost = hosts[0]
        XCTAssertFalse(caseHost.live, "a machine the payload never mentions is offline")
        XCTAssertNil(caseHost.cpu)
        XCTAssertEqual(FleetFormat.ringHeadline(caseHost), "—")
    }

    func testStaleFeedDrawsNoArcsAndTurnsTheNamesOff() {
        let json = fleetJSON([machineJSON("case"), machineJSON("frank", cpu: 13, gpu: 94, ram: 86),
                              machineJSON("claire"), machineJSON("dali"), machineJSON("macbook")])
        guard let f = fleet(json) else { return }
        // A failed poll leaves the store with its last snapshot: those readings are stale, so they must
        // not be presented as live arcs and names, even though the machines themselves report online.
        let stale = FleetPanelModelBuilder.build(fleet: f, activity: nil, fleetLive: false)
        XCTAssertEqual(stale.hosts.count, 5)
        XCTAssertTrue(stale.hosts.allSatisfy { !$0.live }, "a stale feed leaves every reading not live")
        for host in stale.hosts {
            for kind in FleetRingKind.allCases {
                XCTAssertNil(host.arcFraction(kind), "\(host.id) \(kind.rawValue) must draw no arc while stale")
            }
        }
        // The last known numbers stay readable as text, so the footer still says what the machines said.
        XCTAssertEqual(stale.hosts[1].ram, 86)
        XCTAssertEqual(FleetFormat.ringHeadline(stale.hosts[1]), "GPU 94")
        // The same payload on a live feed is live again.
        let live = FleetPanelModelBuilder.build(fleet: f, activity: nil, fleetLive: true)
        XCTAssertTrue(live.hosts[1].live)
        XCTAssertEqual(live.hosts[1].arcFraction(.ram) ?? 0, 0.86, accuracy: 0.001)
    }

    func testStaleFeedLeavesAMachineThatIsOfflineOffAsWell() {
        let json = fleetJSON([machineJSON("case"), machineJSON("frank", state: "unreachable", cpu: 13, gpu: 94, ram: 86)])
        guard let f = fleet(json) else { return }
        let model = FleetPanelModelBuilder.build(fleet: f, activity: nil, fleetLive: true)
        XCTAssertFalse(model.hosts[1].live, "the machine's own offline state still wins")
        XCTAssertNil(model.hosts[1].arcFraction(.ram))
    }

    // MARK: - Malformed items

    func testJobsMissingStepSinceElapsedStillOrderSanely() {
        // Same `since` twice: input order is kept; the since-less job sinks to the end.
        let items = [itemJSON("timed", device: "odin", since: "2026-10-02T06:00:00.000Z",
                              lastStep: "reviewing", elapsedSec: 42),
                     itemJSON("alpha", device: "odin", since: "2026-10-02T06:00:00.000Z"),
                     itemJSON("beta", device: "odin", since: "2026-10-02T06:00:00.000Z"),
                     itemJSON("bare", device: "odin")]
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false, items: items)])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .busy)                                        // items alone make it busy
        XCTAssertEqual(odin.jobs.map(\.label), ["timed", "alpha", "beta", "bare"])
        XCTAssertEqual(odin.jobs.map(\.key), ["timed-2026-10-02T06:00:00.000Z",
                                               "alpha-2026-10-02T06:00:00.000Z",
                                               "beta-2026-10-02T06:00:00.000Z",
                                               "bare-"])
        XCTAssertEqual(odin.jobs.map(\.pill), ["odin", "odin", "odin", "odin"])
        XCTAssertEqual(odin.jobs.first?.step, "reviewing")
        XCTAssertEqual(odin.jobs.first?.elapsedSec, 42)
        XCTAssertNil(odin.jobs.last?.step)                                       // missing fields stay nil
        XCTAssertNil(odin.jobs.last?.elapsedSec)
        XCTAssertEqual(model.workingCount, 1)
        XCTAssertEqual(model.runningTaskCount, 4)
        XCTAssertEqual(model.runningTaskCount, model.nowJobs.count)
    }

    // MARK: - pika

    /// pika with no data row at all: idle/grey, never a red offline node, never a crash.
    func testPikaDefaultsToIdleWithoutADataRow() {
        let model = panel(fleet: nil, activity: nil)
        guard let pika = model.lanes.first(where: { $0.id == "pika" }) else {
            return XCTFail("no pika lane; lanes are \(model.lanes.map(\.id))")
        }
        XCTAssertEqual(pika.state, .idle)
        XCTAssertTrue(pika.jobs.isEmpty)
        XCTAssertEqual(model.agents.map(\.id), ["frank", "claire", "ciri", "dali", "nova", "pika", "odin"])
    }

    /// A fleet row that exists but is not online is genuine offline; reporting work makes it busy.
    func testPikaOnlineReportsBusyAndOfflineRowStaysOffline() {
        let otherMachines = ["case", "frank", "claire", "ciri", "dali", "macbook", "odin"].map { machineJSON($0) }
        let pikaJob = itemJSON("pika-job", device: "pika", since: "2026-10-02T06:00:00.000Z", elapsedSec: 90)
        guard let onlineFleet = fleet(fleetJSON(otherMachines + [machineJSON("pika", state: "online")])),
              let busyActivity = activity(activityJSON([deviceJSON("pika", busy: true, items: [pikaJob])])),
              let offlineFleet = fleet(fleetJSON(otherMachines + [machineJSON("pika", state: "offline")])) else { return }
        let busy = panel(fleet: onlineFleet, activity: busyActivity)
        XCTAssertEqual(busy.lanes.first { $0.id == "pika" }?.state, .busy)

        let down = panel(fleet: offlineFleet, activity: nil)
        XCTAssertEqual(down.lanes.first { $0.id == "pika" }?.state, .offline)
    }

    /// The API promises a pika *device*: a busy one with no matching fleet machine row must still
    /// be busy, and its run must appear in the working count and in the current-work list.
    func testPikaBusyDeviceWithoutAMachineRowCountsAsWorking() {
        let job = itemJSON("pika-run", device: "pika", since: "2026-10-02T06:00:00.000Z", elapsedSec: 30)
        guard let act = activity(activityJSON([deviceJSON("pika", busy: true, items: [job])])) else { return }
        let model = panel(fleet: nil, activity: act)

        XCTAssertEqual(model.lanes.first { $0.id == "pika" }?.state, .busy,
                       "a busy pika device with no machine row is busy, not idle")
        XCTAssertEqual(model.workingCount, 1, "the busy pika lane counts as working")
        XCTAssertEqual(model.runningTaskCount, 1, "its run is one running task")
        XCTAssertEqual(model.nowJobs.count, 1, "its run is the current work")
        XCTAssertEqual(model.nowJobs.map(\.key), ["pika-run-2026-10-02T06:00:00.000Z"])
    }

    // MARK: - Odin needs decision

    private func needsDecisionStatus() -> String {
        "{\"state\":\"needs_decision\",\"job\":\"monitor-landscape-scale\",\"pr\":4,\"reason\":\"no_progress\",\"round\":4}"
    }

    func testOdinNeedsDecisionTurnsTheLaneRedAndCarriesTheAlert() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false, odinStatus: needsDecisionStatus())])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .idle)
        XCTAssertEqual(odin.label, "odin")                                      // only the view renames it
        XCTAssertTrue(odin.isLinked)
        XCTAssertTrue(odin.jobs.isEmpty)
        XCTAssertEqual(odin.decision, FleetDecision(job: "monitor-landscape-scale", pr: 4, reason: "no_progress", round: 4))
        XCTAssertTrue(odin.hasOpenDecision)
        XCTAssertEqual(model.decision, odin.decision)
        // The alert leaves the tallies alone.
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 7)
        XCTAssertEqual(model.criticalCount, 0)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.runningTaskCount, 0)
        XCTAssertTrue(model.nowJobs.isEmpty)
    }

    func testOdinWithoutAStatusBlockStaysIdle() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false)])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .idle)
        XCTAssertNil(odin.decision)
        XCTAssertNil(model.decision)
    }

    func testOnlyNeedsDecisionRaisesTheAlert() {
        guard let f = fleet(onlineFleetJSON()) else { return }
        for state in ["idle", "reviewing", "done"] {
            guard let a = activity(activityJSON([deviceJSON("odin", busy: false, odinStatus: "{\"state\":\"\(state)\"}")])) else { return }
            let model = panel(fleet: f, activity: a)
            guard let odin = lane(model, "odin") else { return }
            XCTAssertEqual(odin.state, .idle, "\"\(state)\" must not raise the alert")
            XCTAssertNil(model.decision, "\"\(state)\" must not raise the alert")
        }
        // A really running review stays the ordinary busy lane.
        let review = itemJSON("Reviewing boring.notch#13", device: "odin", since: "2026-10-02T06:00:00.000Z")
        guard let a = activity(activityJSON([deviceJSON("odin", busy: true, items: [review], odinStatus: "{\"state\":\"reviewing\"}")])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .busy)
        XCTAssertNil(model.decision)
        XCTAssertEqual(model.workingCount, 1)
    }

    func testNeedsDecisionSurvivesAMissingFleetSnapshot() {
        guard let a = activity(activityJSON([deviceJSON("odin", busy: false, odinStatus: needsDecisionStatus())])) else { return }
        let model = panel(fleet: nil, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .offline)                                    // the *alert* survives a missing probe (the decisions, the strip and the pip), not the node state
        XCTAssertEqual(odin.decision?.pr, 4)
        XCTAssertEqual(model.decision?.pr, 4)
        XCTAssertTrue(model.hasOpenDecision)
    }

    // MARK: - Odin open decisions

    /// Two stopped jobs awaiting a decision, as the writer's open-decisions file
    /// reaches the feed: the second one has no round.
    private func twoOpenDecisions() -> String {
        return "[{\"state\":\"needs_decision\",\"job\":\"monitor-landscape-scale\",\"pr\":4,\"reason\":\"no_progress\",\"round\":4},"
            + "{\"state\":\"needs_decision\",\"job\":\"hue-release\",\"pr\":7,\"reason\":\"repeat_finding\"}]"
    }

    private func twoOpenDecisionList() -> [FleetDecision] {
        return [FleetDecision(job: "monitor-landscape-scale", pr: 4, reason: "no_progress", round: 4),
                FleetDecision(job: "hue-release", pr: 7, reason: "repeat_finding", round: nil)]
    }

    func testTwoOpenDecisionsDriveTheOdinLane() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false,
                                                        odinStatus: "{\"state\":\"idle\"}",
                                                        odinOpen: twoOpenDecisions())])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .idle)                                       // the idle status cannot veto the list
        XCTAssertEqual(odin.decisions, twoOpenDecisionList())                     // every entry, in file order
        XCTAssertEqual(model.decisions, twoOpenDecisionList())
        XCTAssertEqual(model.decision, model.decisions.first)                     // the strip names the first
        XCTAssertTrue(model.hasOpenDecision)
        // The alert leaves the tallies alone.
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 7)
        XCTAssertEqual(model.criticalCount, 0)
        XCTAssertFalse(model.isBusy)
    }

    func testOdinReviewingWithAnOpenDecisionStaysBusyAndCountsAsWork() {
        // An open decision must never hide the review Odin is actually running: the lane
        // stays busy, so its item shows up in current work and in the running-task count.
        let review = itemJSON("Reviewing boring.notch#14", device: "odin", since: "2026-10-02T06:00:00.000Z",
                              lastStep: "sweeping the diff", elapsedSec: 30)
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: true, items: [review],
                                                        odinStatus: "{\"state\":\"reviewing\"}",
                                                        odinOpen: twoOpenDecisions())])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        XCTAssertEqual(odin.state, .busy)
        XCTAssertTrue(odin.hasOpenDecision)
        XCTAssertEqual(odin.decisions.count, 2)
        XCTAssertEqual(model.workingCount, 1)
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.runningTaskCount, 1)
        XCTAssertEqual(model.nowJobs.map(\.label), ["Reviewing boring.notch#14"])
    }

    func testAnEmptyOpenListBeatsAStaleNeedsDecisionStatus() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false,
                                                        odinStatus: "{\"state\":\"needs_decision\",\"job\":\"stale-job\",\"pr\":9}",
                                                        odinOpen: "[]")])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        // The list is the truth, so a stale status cannot resurrect a closed decision.
        XCTAssertEqual(odin.state, .idle, "an open list of [] must beat the stale needs_decision status")
        XCTAssertTrue(odin.decisions.isEmpty, "an open list of [] must beat the stale needs_decision status")
        XCTAssertTrue(model.decisions.isEmpty, "an open list of [] must beat the stale needs_decision status")
        XCTAssertFalse(model.hasOpenDecision, "an open list of [] must beat the stale needs_decision status")
    }

    func testMissingOpenListFallsBackToTheNeedsDecisionStatus() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false, odinStatus: needsDecisionStatus())])) else { return }
        let model = panel(fleet: f, activity: a)
        guard let odin = lane(model, "odin") else { return }
        // No open key at all: an older dashboard, so the single status drives the lane.
        XCTAssertEqual(odin.state, .idle)
        XCTAssertEqual(odin.decisions, [FleetDecision(job: "monitor-landscape-scale", pr: 4, reason: "no_progress", round: 4)])
        XCTAssertEqual(model.decisions.count, 1)
        XCTAssertTrue(model.hasOpenDecision)
        // And with neither an open list nor a needs-decision status, nothing is open.
        guard let a2 = activity(activityJSON([deviceJSON("odin", busy: false, odinStatus: "{\"state\":\"idle\"}")])) else { return }
        let idleModel = panel(fleet: f, activity: a2)
        guard let idleOdin = lane(idleModel, "odin") else { return }
        XCTAssertTrue(idleOdin.decisions.isEmpty)
        XCTAssertTrue(idleModel.decisions.isEmpty)
        XCTAssertFalse(idleModel.hasOpenDecision)
        XCTAssertEqual(idleOdin.state, .idle)
    }

    func testOpenDecisionsSurviveAFailedPollAndClearOnASuccessfulEmptyOne() {
        guard let f = fleet(onlineFleetJSON()),
              let a = activity(activityJSON([deviceJSON("odin", busy: false,
                                                        odinStatus: "{\"state\":\"idle\"}",
                                                        odinOpen: twoOpenDecisions())])) else { return }
        let opened = panel(fleet: f, activity: a)
        XCTAssertTrue(opened.hasOpenDecision, "the successful poll that reported the open list must raise the pip")
        // A failed poll leaves the store's snapshots untouched (it only assigns them
        // on success), so rebuilding from the very same snapshots is what the failed
        // poll leaves behind: the last known decisions must survive it.
        let failedPoll = panel(fleet: f, activity: a)
        XCTAssertTrue(failedPoll.hasOpenDecision, "a failed poll must keep the last known open decisions")
        XCTAssertEqual(failedPoll.decisions.count, 2, "a failed poll must keep every last known decision")
        // A later successful poll whose open list is empty clears the pip.
        guard let clearedActivity = activity(activityJSON([deviceJSON("odin", busy: false,
                                                                       odinStatus: "{\"state\":\"idle\"}",
                                                                       odinOpen: "[]")])) else { return }
        let cleared = panel(fleet: f, activity: clearedActivity)
        XCTAssertFalse(cleared.hasOpenDecision, "a later successful empty open list must clear the pip")
    }

    /// The fleet-wide speed rides on the model; a machine lane carries its device's own reading and the
    /// cloud pool (nova) never does.
    func testSpeedReachesTheModelAndTheMachineLanes() throws {
        let json = """
        {"generatedAt":"2026-10-11T18:00:00.000Z","speed":{"current":154.4,"lastAt":"2026-10-11T17:59:50.000Z","trend":[120.0,null],"stepSec":10},"devices":[{"device":"frank","items":[{"id":"j1","label":"job","device":"frank"}],"state":"ok","speed":38.5},{"device":"ciri","items":[],"state":"ok","speed":12.0},{"device":"case","items":[{"id":"c1","label":"cloud job","device":"cloud","model":"openrouter/deepseek"}],"state":"ok"}]}
        """
        let activity = try ActivitySnapshot.decode(Data(json.utf8))
        let model = panel(fleet: nil, activity: activity)
        XCTAssertEqual(model.speed?.current, 154.4)
        XCTAssertEqual(model.agents.first { $0.id == "frank" }?.speed, 38.5)
        XCTAssertEqual(model.agents.first { $0.id == "ciri" }?.speed, 12.0)
        XCTAssertNil(model.agents.first { $0.id == "nova" }?.speed)
        XCTAssertNil(model.agents.first { $0.id == "odin" }?.speed)
    }

    /// No speed block in either payload: the fleet number is the median of the devices that report one, so a
    /// single writer's own speed becomes the fleet's (never their sum).
    func testFleetSpeedFallsBackToTheDeviceMedian() throws {
        let json = """
        {"generatedAt":"2026-10-11T18:00:00.000Z","devices":[{"device":"frank","items":[{"id":"j1","label":"job","device":"frank"}],"state":"ok","speed":38.5},{"device":"claire","items":[],"state":"ok"},{"device":"dali","items":[],"state":"ok"}]}
        """
        let activity = try ActivitySnapshot.decode(Data(json.utf8))
        let model = panel(fleet: nil, activity: activity)
        XCTAssertEqual(model.speed?.current ?? 0, 38.5, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.speedNumberText(model.speed), "39")
    }

    /// A payload block still wins over the device median, and no readings at all stay nil.
    func testPayloadSpeedBlockWinsAndNoReadingsStayNil() throws {
        let withBlock = """
        {"generatedAt":"2026-10-11T18:00:00.000Z","speed":{"current":154.4,"lastAt":null,"trend":[],"stepSec":10},"devices":[{"device":"frank","items":[{"id":"j1","label":"job","device":"frank"}],"state":"ok","speed":38.5}]}
        """
        let blocked = panel(
            fleet: nil, activity: try ActivitySnapshot.decode(Data(withBlock.utf8)))
        XCTAssertEqual(blocked.speed?.current ?? 0, 154.4, accuracy: 0.001)

        let silent = """
        {"generatedAt":"2026-10-11T18:00:00.000Z","devices":[{"device":"frank","items":[],"state":"ok"}]}
        """
        let quiet = panel(
            fleet: nil, activity: try ActivitySnapshot.decode(Data(silent.utf8)))
        XCTAssertNil(quiet.speed)
    }
}
