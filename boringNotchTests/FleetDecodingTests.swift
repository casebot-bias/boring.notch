import XCTest

/// Decoding tests for the fleet/activity JSON models against real fixtures
/// captured with curl from the live API (`Fixtures/fleet.json`, `Fixtures/activity.json`).
final class FleetDecodingTests: XCTestCase {

    // MARK: - Fixture loading

    /// Loads a bundled fixture, trying the `Fixtures` subdirectory first and the
    /// bundle root second. Fails the test (without crashing) when neither is found.
    private func fixtureData(named name: String, file: StaticString = #file, line: UInt = #line) -> Data? {
        let bundle = Bundle(for: FleetDecodingTests.self)
        let searchedPaths: [String]
        if let sub = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            searchedPaths = [sub.path]
            if let data = try? Data(contentsOf: sub) {
                return data
            }
        } else {
            searchedPaths = []
        }
        var paths = searchedPaths
        if let root = bundle.url(forResource: name, withExtension: "json") {
            paths.append(root.path)
            if let data = try? Data(contentsOf: root) {
                return data
            }
        }
        let base = bundle.bundlePath
        XCTFail("Fixture \(name).json not found. Searched bundle paths: \(paths.isEmpty ? [base + "/Fixtures/\(name).json", base + "/\(name).json"] : paths)",
                file: file, line: line)
        return nil
    }

    private func decodeFleet(_ data: Data, file: StaticString = #file, line: UInt = #line) -> FleetSnapshot? {
        do {
            return try FleetSnapshot.decode(data)
        } catch {
            XCTFail("FleetSnapshot.decode failed: \(error)", file: file, line: line)
            return nil
        }
    }

    private func decodeActivity(_ data: Data, file: StaticString = #file, line: UInt = #line) -> ActivitySnapshot? {
        do {
            return try ActivitySnapshot.decode(data)
        } catch {
            XCTFail("ActivitySnapshot.decode failed: \(error)", file: file, line: line)
            return nil
        }
    }

    /// Unwraps an array element or fails the test naming the field, avoiding force-unwraps.
    private func element<T>(_ array: [T], at index: Int, field: String, file: StaticString = #file, line: UInt = #line) -> T? {
        guard array.indices.contains(index) else {
            XCTFail("\(field) has no element at index \(index) (count \(array.count))", file: file, line: line)
            return nil
        }
        return array[index]
    }

    private func require<T>(_ value: T?, _ field: String, file: StaticString = #file, line: UInt = #line) -> T? {
        guard let value = value else {
            XCTFail("\(field) is nil", file: file, line: line)
            return nil
        }
        return value
    }

    // MARK: - 1. Fleet fixture

    func testFleetFixtureDecodesMachinesInOrder() throws {
        guard let data = fixtureData(named: "fleet") else { return }
        guard let snapshot = decodeFleet(data) else { return }

        XCTAssertFalse(snapshot.generatedAt.isEmpty, "FleetSnapshot.generatedAt must not be empty")
        XCTAssertEqual(snapshot.machines.map(\.id), ["case", "frank", "dali", "macbook"],
                       "FleetSnapshot.machines ids must be in order case, frank, dali, macbook")

        guard let machine = element(snapshot.machines, at: 0, field: "FleetSnapshot.machines[0]") else { return }
        XCTAssertEqual(machine.state, "online", "FleetSnapshot.machines[0].state")

        XCTAssertEqual(machine.ramUsedPct.state, "ok", "machines[0].ramUsedPct.state")
        if let ramUsedPct = require(machine.ramUsedPct.value, "machines[0].ramUsedPct.value") {
            XCTAssertEqual(ramUsedPct, 38.6, accuracy: 1e-9, "machines[0].ramUsedPct.value")
        }

        XCTAssertNil(machine.gpuTempC.value, "machines[0].gpuTempC.value must be nil")
        XCTAssertEqual(machine.gpuTempC.state, "unavailable", "machines[0].gpuTempC.state")
        XCTAssertFalse(machine.gpuTempC.isAvailable, "machines[0].gpuTempC.isAvailable must be false")

        guard let second = element(snapshot.machines, at: 1, field: "FleetSnapshot.machines[1]") else { return }
        guard let model = element(second.models, at: 0, field: "machines[1].models") else { return }
        XCTAssertEqual(model.id, "frank:vllm", "machines[1].models.first.id")
        XCTAssertEqual(model.state, "online", "machines[1].models.first.state")
    }

    // MARK: - 2. Activity fixture

    func testActivityFixtureDecodesDevicesInOrder() throws {
        guard let data = fixtureData(named: "activity") else { return }
        guard let snapshot = decodeActivity(data) else { return }

        XCTAssertEqual(snapshot.devices.map(\.device), ["case", "frank", "dali", "macbook"],
                       "ActivitySnapshot.devices names must be in order case, frank, dali, macbook")

        guard let caseDevice = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0]") else { return }
        XCTAssertEqual(caseDevice.busy, true, "devices[0].busy (case)")
        XCTAssertGreaterThanOrEqual(caseDevice.items.count, 1, "devices[0].items.count must be >= 1")
        guard let firstItem = element(caseDevice.items, at: 0, field: "devices[0].items") else { return }
        XCTAssertEqual(firstItem.device, "cloud", "devices[0].items[0].device")
        XCTAssertNotNil(firstItem.elapsedSec, "devices[0].items[0].elapsedSec must be non-nil")
        XCTAssertNil(caseDevice.tokPerSec, "devices[0].tokPerSec (case) must be nil")

        guard let frankDevice = element(snapshot.devices, at: 1, field: "ActivitySnapshot.devices[1]") else { return }
        if let frankSlots = require(frankDevice.slots, "devices[1].slots (frank)") {
            XCTAssertEqual(frankSlots.total, 4, "devices[1].slots.total (frank)")
        }

        guard let daliDevice = element(snapshot.devices, at: 2, field: "ActivitySnapshot.devices[2]") else { return }
        if let daliSlots = require(daliDevice.slots, "devices[2].slots (dali)") {
            XCTAssertEqual(daliSlots.total, 3, "devices[2].slots.total (dali)")
        }

        guard let macbookDevice = element(snapshot.devices, at: 3, field: "ActivitySnapshot.devices[3]") else { return }
        XCTAssertNil(macbookDevice.busy, "devices[3].busy (macbook) must be nil")
    }

    // MARK: - 3. Unknown/null never decodes to 0

    func testUnknownReadingsNeverBecomeZero() throws {
        guard let data = fixtureData(named: "fleet") else { return }
        guard let snapshot = decodeFleet(data) else { return }
        XCTAssertFalse(snapshot.machines.isEmpty, "FleetSnapshot.machines must not be empty")

        for machine in snapshot.machines {
            let readings: [(String, Reading)] = [
                ("ramUsedPct", machine.ramUsedPct),
                ("cpuLoadPct", machine.cpuLoadPct),
                ("cpuTempC", machine.cpuTempC),
                ("gpuUtilPct", machine.gpuUtilPct),
                ("gpuTempC", machine.gpuTempC)
            ]
            for (name, reading) in readings where reading.state != "ok" {
                XCTAssertTrue(reading.value == nil || reading.isAvailable == false,
                              "machines[\(machine.id)].\(name): state != \"ok\" must keep value == nil or isAvailable == false, got value=\(String(describing: reading.value)) isAvailable=\(reading.isAvailable)")
            }
        }
    }

    // MARK: - 4. Missing keys are tolerated

    func testMissingKeysAreTolerated() throws {
        guard let emptyFleet = decodeFleet(Data("{}".utf8)) else { return }
        XCTAssertTrue(emptyFleet.machines.isEmpty, "FleetSnapshot.machines must be empty for {} payload")

        guard let emptyActivity = decodeActivity(Data("{\"devices\":[]}".utf8)) else { return }
        XCTAssertTrue(emptyActivity.devices.isEmpty, "ActivitySnapshot.devices must be empty for {\"devices\":[]} payload")

        let minimalMachineJSON = Data("{\"machines\":[{\"id\":\"x\",\"title\":\"x\",\"state\":\"online\"}]}".utf8)
        guard let minimal = decodeFleet(minimalMachineJSON) else { return }
        guard let machine = element(minimal.machines, at: 0, field: "FleetSnapshot.machines") else { return }
        XCTAssertEqual(machine.id, "x", "minimal machine id")

        let readings: [(String, Reading)] = [
            ("ramUsedPct", machine.ramUsedPct),
            ("cpuLoadPct", machine.cpuLoadPct),
            ("cpuTempC", machine.cpuTempC),
            ("gpuUtilPct", machine.gpuUtilPct),
            ("gpuTempC", machine.gpuTempC)
        ]
        for (name, reading) in readings {
            XCTAssertFalse(reading.isAvailable, "minimal machine \(name).isAvailable must be false when key is absent")
        }
    }

    // MARK: - 5. Odin needs-decision status

    /// One odin activity device; `odin` is the raw body of the device's `odin` key, nil to omit it.
    private func odinActivityJSON(_ odin: String?) -> Data {
        let block = odin.map { ",\"odin\":\($0)" } ?? ""
        let json = "{\"generatedAt\":\"2026-10-10T01:00:00.000Z\",\"devices\":[{\"device\":\"odin\",\"busy\":false,\"items\":[],\"state\":\"ok\"\(block)}]}"
        return Data(json.utf8)
    }

    func testOdinNeedsDecisionStatusDecodesEveryField() throws {
        let body = "{\"status\":{\"state\":\"needs_decision\",\"job\":\"monitor-landscape-scale\",\"repo\":\"biaslabs-ai/monitor-improvements\",\"pr\":4,\"sha\":\"376cd9d\",\"round\":4,\"reason\":\"no_progress\",\"findings\":2,\"verdict\":\"fail\",\"updated\":\"2026-10-10T01:00:00Z\"},\"counts\":{\"pass\":11,\"fail\":39}}"
        guard let snapshot = decodeActivity(odinActivityJSON(body)) else { return }
        guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin)") else { return }
        XCTAssertEqual(device.device, "odin", "devices[0].device (odin)")
        XCTAssertEqual(device.state, "ok", "devices[0].state (odin) must not be disturbed by the counts block")
        XCTAssertEqual(device.busy, false, "devices[0].busy (odin) must not be disturbed by the counts block")
        XCTAssertTrue(device.items.isEmpty, "devices[0].items (odin) must stay empty despite the counts block")
        guard let report = require(device.odin, "devices[0].odin (odin)") else { return }
        guard let status = require(report.status, "devices[0].odin.status") else { return }
        XCTAssertEqual(status.state, "needs_decision", "devices[0].odin.status.state")
        XCTAssertTrue(status.needsDecision, "devices[0].odin.status.needsDecision")
        XCTAssertEqual(status.job, "monitor-landscape-scale", "devices[0].odin.status.job")
        XCTAssertEqual(status.repo, "biaslabs-ai/monitor-improvements", "devices[0].odin.status.repo")
        XCTAssertEqual(status.pr, 4, "devices[0].odin.status.pr")
        XCTAssertEqual(status.sha, "376cd9d", "devices[0].odin.status.sha")
        XCTAssertEqual(status.round, 4, "devices[0].odin.status.round")
        XCTAssertEqual(status.reason, "no_progress", "devices[0].odin.status.reason")
        XCTAssertEqual(status.findings, 2, "devices[0].odin.status.findings")
        XCTAssertEqual(status.verdict, "fail", "devices[0].odin.status.verdict")
        XCTAssertEqual(status.updated, "2026-10-10T01:00:00Z", "devices[0].odin.status.updated")
    }

    func testOdinNeedsDecisionWithoutOtherFieldsStaysUnknown() throws {
        guard let snapshot = decodeActivity(odinActivityJSON("{\"status\":{\"state\":\"needs_decision\"}}")) else { return }
        guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin)") else { return }
        guard let report = require(device.odin, "devices[0].odin (odin)") else { return }
        guard let status = require(report.status, "devices[0].odin.status") else { return }
        XCTAssertEqual(status.state, "needs_decision", "devices[0].odin.status.state")
        XCTAssertTrue(status.needsDecision, "devices[0].odin.status.needsDecision")
        XCTAssertNil(status.job, "devices[0].odin.status.job must be nil when absent")
        XCTAssertNil(status.repo, "devices[0].odin.status.repo must be nil when absent")
        XCTAssertNil(status.pr, "devices[0].odin.status.pr must be nil when absent")
        XCTAssertNil(status.sha, "devices[0].odin.status.sha must be nil when absent")
        XCTAssertNil(status.round, "devices[0].odin.status.round must be nil when absent")
        XCTAssertNil(status.reason, "devices[0].odin.status.reason must be nil when absent")
        XCTAssertNil(status.findings, "devices[0].odin.status.findings must be nil when absent")
        XCTAssertNil(status.verdict, "devices[0].odin.status.verdict must be nil when absent")
        XCTAssertNil(status.updated, "devices[0].odin.status.updated must be nil when absent")
    }

    func testMissingOdinBlockIsNotANeedsDecision() throws {
        let cases: [(name: String, odin: String?, present: Bool, state: String?)] = [
            ("key absent", nil, false, nil),
            ("null", "null", false, nil),
            ("{}", "{}", true, nil),
            ("idle", "{\"status\":{\"state\":\"idle\"}}", true, "idle"),
            ("reviewing", "{\"status\":{\"state\":\"reviewing\"}}", true, "reviewing"),
            ("counts only", "{\"counts\":{\"pass\":1,\"fail\":0}}", true, nil)
        ]
        for testCase in cases {
            guard let snapshot = decodeActivity(odinActivityJSON(testCase.odin)) else { continue }
            guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin \(testCase.name))") else { continue }
            XCTAssertEqual(device.odin == nil, !testCase.present,
                           "devices[0].odin presence for \(testCase.name) payload")
            XCTAssertEqual(device.odin?.status?.state, testCase.state,
                           "devices[0].odin.status.state for \(testCase.name) payload")
            XCTAssertFalse(device.odin?.status?.needsDecision == true,
                           "devices[0].odin.status.needsDecision must never be true for \(testCase.name) payload")
        }
    }

    func testOdinOpenDecisionsDecodeInOrder() throws {
        let body = "{\"status\":{\"state\":\"reviewing\",\"job\":\"other-job\"},\"open\":[{\"state\":\"needs_decision\",\"job\":\"monitor-landscape-scale\",\"repo\":\"biaslabs-ai/monitor-improvements\",\"pr\":4,\"sha\":\"376cd9d\",\"round\":4,\"reason\":\"no_progress\",\"findings\":2,\"verdict\":\"fail\",\"updated\":\"2026-10-10T01:00:00Z\"},{\"state\":\"needs_decision\",\"job\":\"hue-release\",\"pr\":7,\"reason\":\"repeat_finding\"}]}"
        guard let snapshot = decodeActivity(odinActivityJSON(body)) else { return }
        guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin)") else { return }
        guard let report = require(device.odin, "devices[0].odin (odin)") else { return }
        guard let open = require(report.open, "devices[0].odin.open") else { return }
        XCTAssertEqual(open.count, 2, "devices[0].odin.open must keep every entry")
        guard let first = element(open, at: 0, field: "devices[0].odin.open[0]") else { return }
        XCTAssertEqual(first.state, "needs_decision", "devices[0].odin.open[0].state")
        XCTAssertTrue(first.needsDecision, "devices[0].odin.open[0].needsDecision")
        XCTAssertEqual(first.job, "monitor-landscape-scale", "devices[0].odin.open[0].job")
        XCTAssertEqual(first.repo, "biaslabs-ai/monitor-improvements", "devices[0].odin.open[0].repo")
        XCTAssertEqual(first.pr, 4, "devices[0].odin.open[0].pr")
        XCTAssertEqual(first.sha, "376cd9d", "devices[0].odin.open[0].sha")
        XCTAssertEqual(first.round, 4, "devices[0].odin.open[0].round")
        XCTAssertEqual(first.reason, "no_progress", "devices[0].odin.open[0].reason")
        XCTAssertEqual(first.findings, 2, "devices[0].odin.open[0].findings")
        XCTAssertEqual(first.verdict, "fail", "devices[0].odin.open[0].verdict")
        XCTAssertEqual(first.updated, "2026-10-10T01:00:00Z", "devices[0].odin.open[0].updated")
        guard let second = element(open, at: 1, field: "devices[0].odin.open[1]") else { return }
        XCTAssertEqual(second.state, "needs_decision", "devices[0].odin.open[1].state")
        XCTAssertEqual(second.job, "hue-release", "devices[0].odin.open[1].job")
        XCTAssertEqual(second.pr, 7, "devices[0].odin.open[1].pr")
        XCTAssertEqual(second.reason, "repeat_finding", "devices[0].odin.open[1].reason")
        XCTAssertEqual(report.status?.state, "reviewing", "devices[0].odin.status.state decodes independently of open")
        XCTAssertEqual(report.status?.job, "other-job", "devices[0].odin.status.job decodes independently of open")
    }

    func testOdinOpenDecisionsEmptyListIsNotEmptyKey() throws {
        guard let snapshot = decodeActivity(odinActivityJSON("{\"status\":{\"state\":\"idle\"},\"open\":[]}")) else { return }
        guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin)") else { return }
        guard let report = require(device.odin, "devices[0].odin (odin)") else { return }
        XCTAssertNotNil(report.open, "devices[0].odin.open must survive an empty list: [] is the feed saying nothing is open")
        XCTAssertEqual(report.open?.count, 0, "devices[0].odin.open must decode as an empty list")
    }

    func testMissingOpenKeyDecodesToNil() throws {
        let bodies = [
            "{\"status\":{\"state\":\"needs_decision\",\"job\":\"monitor-landscape-scale\",\"pr\":4}}",
            "{\"counts\":{\"pass\":1,\"fail\":0}}"
        ]
        for body in bodies {
            guard let snapshot = decodeActivity(odinActivityJSON(body)) else { continue }
            guard let device = element(snapshot.devices, at: 0, field: "ActivitySnapshot.devices[0] (odin)") else { continue }
            XCTAssertNil(device.odin?.open,
                         "devices[0].odin.open must be nil when the key is absent (dashboard older than the list): \(body)")
        }
    }
}
