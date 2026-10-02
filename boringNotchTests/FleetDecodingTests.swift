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
}
