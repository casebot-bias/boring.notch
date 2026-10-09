//
//  FleetPanelModelTests.swift
//  boringNotchTests
//
//  Behaviour tests for FleetPanelModelBuilder.build: response-map lane order and
//  states, current-work job order/dedup, the unique-key runningTaskCount, nova's
//  cloud routing, the fleet-wide tok/s sum (a reported 0 stays 0) and the
//  cpu/gpu/ram peaks.
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

    // MARK: - Empty snapshots

    func testNilSnapshotsGiveOfflineLanesAndUnknownPeaks() {
        let model = FleetPanelModelBuilder.build(fleet: nil, activity: nil)
        XCTAssertEqual(model.origin.id, "case")
        XCTAssertEqual(model.origin.label, "case")
        XCTAssertEqual(model.origin.state, .offline)
        XCTAssertFalse(model.origin.isLinked)
        XCTAssertTrue(model.origin.jobs.isEmpty)
        XCTAssertEqual(model.agents.map(\.id), ["frank", "claire", "ciri", "dali", "nova", "odin"])
        XCTAssertEqual(model.agents.map(\.label), ["frank", "claire", "ciri", "dali", "nova", "odin"])
        XCTAssertEqual(model.agents.map(\.state), Array(repeating: .offline, count: 6))
        XCTAssertEqual(model.agents.map(\.isLinked), Array(repeating: false, count: 6))
        XCTAssertEqual(model.agentCount, 6)
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 0)
        XCTAssertEqual(model.criticalCount, 6)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.totalTokPerSec)
        XCTAssertEqual(model.runningTaskCount, 0)
        XCTAssertTrue(model.nowJobs.isEmpty)
        // Peaks keep their slots even when nobody reports.
        XCTAssertEqual(model.peaks.map(\.kind), [.cpu, .gpu, .ram])
        XCTAssertEqual(model.peaks.map(\.id), ["cpu", "gpu", "ram"])
        for peak in model.peaks {
            XCTAssertNil(peak.value, "\(peak.kind.rawValue) must report no value")
            XCTAssertNil(peak.host, "\(peak.kind.rawValue) must report no host")
        }
    }

    func testAgentOrderIsFixedAndLanesStartWithCase() {
        let model = FleetPanelModelBuilder.build(fleet: nil, activity: nil)
        XCTAssertEqual(FleetPanelModelBuilder.agentIds, ["frank", "claire", "ciri", "dali", "nova", "odin"])
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        XCTAssertEqual(model.linkedCount, 6)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
        guard let dali = lane(model, "dali") else { return }
        XCTAssertEqual(dali.state, .offline)                                // offline wins over the busy device
        XCTAssertFalse(dali.isLinked)
        XCTAssertEqual(model.workingCount, 0)
        XCTAssertEqual(model.linkedCount, 5)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        XCTAssertEqual(model.linkedCount, 6)
        XCTAssertEqual(model.criticalCount, 0)
        // Qwen-only activity leaves nova idle (case keeps working via its items).
        guard let a2 = activity(activityJSON([deviceJSON("case", busy: true, items: [qwen])])) else { return }
        guard let nova2 = lane(FleetPanelModelBuilder.build(fleet: f, activity: a2), "nova") else { return }
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
        let model = FleetPanelModelBuilder.build(fleet: nil, activity: a)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
        XCTAssertEqual(model.workingCount, 2)                                  // frank + dali
        XCTAssertEqual(model.totalTokPerSec ?? 0, 52.4, accuracy: 0.001)       // case's 999 excluded
        // No agent reports a rate: nil, not 0.
        let silent = [deviceJSON("case", busy: true), deviceJSON("frank", busy: false), deviceJSON("dali", busy: false)]
        guard let a2 = activity(activityJSON(silent)) else { return }
        let silentModel = FleetPanelModelBuilder.build(fleet: f, activity: a2)
        XCTAssertNil(silentModel.totalTokPerSec)                    // nil only when no agent reports a rate at all
        XCTAssertEqual(FleetFormat.fleetOutput(silentModel.totalTokPerSec), FleetFormat.unknown)
        // One reporting agent: its rate alone is the total.
        guard let a3 = activity(activityJSON([deviceJSON("frank", busy: true, tokPerSec: 7)])) else { return }
        XCTAssertEqual(FleetPanelModelBuilder.build(fleet: f, activity: a3).totalTokPerSec ?? 0, 7, accuracy: 0.001)
    }

    func testAgentReportingZeroThroughputShowsZeroNotDash() {
        let devices = [deviceJSON("case", busy: false),                        // origin: silent here
                       deviceJSON("frank", busy: false, tokPerSec: 0),         // idle frank reports a real 0
                       deviceJSON("dali", busy: false)]                         // no other agent reports a rate
        guard let f = fleet(onlineFleetJSON()), let a = activity(activityJSON(devices)) else { return }
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.totalTokPerSec, 0)                                  // 0, not nil
        XCTAssertEqual(FleetFormat.fleetOutput(model.totalTokPerSec), "0")       // renders "0", not "—"
        // Reported zeros don't mask a real rate.
        let mixed = [deviceJSON("frank", busy: false, tokPerSec: 0),
                     deviceJSON("dali", busy: true, tokPerSec: 12.4)]
        guard let a2 = activity(activityJSON(mixed)) else { return }
        let mixedModel = FleetPanelModelBuilder.build(fleet: f, activity: a2)
        XCTAssertEqual(mixedModel.totalTokPerSec ?? 0, 12.4, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.fleetOutput(mixedModel.totalTokPerSec), "12")
    }

    // MARK: - Peaks

    func testPeaksTakeHighestValuePerKindWithHostTitleIncludingMacbook() {
        let json = fleetJSON([machineJSON("case"),                                   // origin reports nothing
                              machineJSON("frank", cpu: 10),
                              machineJSON("claire"), machineJSON("ciri"), machineJSON("odin"),
                              machineJSON("dali", title: "Dali Studio", cpu: 71, gpu: 96),
                              machineJSON("macbook", title: "MacBook", cpu: 68.3, gpu: 12, ram: 90)])
        guard let f = fleet(json) else { return }
        let peaks = FleetPanelModelBuilder.build(fleet: f, activity: nil).peaks
        XCTAssertEqual(peaks.map(\.kind), [.cpu, .gpu, .ram])
        XCTAssertEqual(peaks.map(\.id), ["cpu", "gpu", "ram"])
        XCTAssertEqual(peaks[0].value ?? 0, 71, accuracy: 0.001)
        XCTAssertEqual(peaks[0].host, "Dali Studio")                             // host is the machine title
        XCTAssertEqual(peaks[1].value ?? 0, 96, accuracy: 0.001)
        XCTAssertEqual(peaks[1].host, "Dali Studio")
        XCTAssertEqual(peaks[2].value ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(peaks[2].host, "MacBook")                                  // macbook is not an agent but still peaks
        XCTAssertEqual(FleetPeak.Kind.allCases.map(\.title), ["CPU", "GPU", "RAM"])
        // A fleet where nobody reports anything keeps every peak empty.
        guard let bare = fleet(onlineFleetJSON()) else { return }
        for peak in FleetPanelModelBuilder.build(fleet: bare, activity: nil).peaks {
            XCTAssertNil(peak.value, "\(peak.kind.rawValue) must report no value")
            XCTAssertNil(peak.host, "\(peak.kind.rawValue) must report no host")
        }
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
        let model = FleetPanelModelBuilder.build(fleet: f, activity: a)
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
}
