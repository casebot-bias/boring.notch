//
//  FleetFormatTests.swift
//  boringNotchTests
//
//  Unit tests for the pure formatters in `FleetFormat`. `FleetModels.swift`,
//  `FleetFormat.swift` and `FleetPanelModel.swift` are compiled directly into
//  this test module, so no `@testable import` is needed.
//

import XCTest

final class FleetFormatTests: XCTestCase {

    // MARK: - Helpers

    private func job(_ key: String) -> FleetJob {
        FleetJob(key: key, pill: "frank", label: "Reviewing the diff", step: nil, elapsedSec: nil)
    }

    private func lane(_ state: FleetNodeState, jobs: [FleetJob] = []) -> FleetLane {
        FleetLane(id: "frank", label: "frank", state: state, jobs: jobs)
    }

    // MARK: - unknown

    func testUnknownRendersDash() {
        XCTAssertEqual(FleetFormat.unknown, "—")
    }

    // MARK: - percent

    func testPercentRoundsToWholePercent() {
        XCTAssertEqual(FleetFormat.percent(72), "72%")
    }

    func testPercentRoundsFractionalValueDown() {
        XCTAssertEqual(FleetFormat.percent(86.34), "86%")
    }

    func testPercentRealZeroRendersZeroPercentNotDash() {
        XCTAssertEqual(FleetFormat.percent(0), "0%")
    }

    func testPercentRoundsUpToHundred() {
        XCTAssertEqual(FleetFormat.percent(99.5), "100%")
    }

    // MARK: - fleetOutput

    func testFleetOutputNilRendersDash() {
        XCTAssertEqual(FleetFormat.fleetOutput(nil), FleetFormat.unknown)
    }

    func testFleetOutputRoundsToWholeNumberWithoutUnit() {
        XCTAssertEqual(FleetFormat.fleetOutput(401.4), "401")
    }

    func testFleetOutputZeroRendersZeroNotDash() {
        XCTAssertEqual(FleetFormat.fleetOutput(0), "0")
    }

    // MARK: - jobs

    func testJobsZeroReturnsIdle() {
        XCTAssertEqual(FleetFormat.jobs(0), "idle")
    }

    func testJobsNegativeReturnsIdle() {
        XCTAssertEqual(FleetFormat.jobs(-1), "idle")
    }

    func testJobsSingleIsOneJob() {
        XCTAssertEqual(FleetFormat.jobs(1), "1 job")
    }

    func testJobsPluralIsJobs() {
        XCTAssertEqual(FleetFormat.jobs(3), "3 jobs")
    }

    // MARK: - jobBadge

    func testJobBadgeZeroIsNil() {
        XCTAssertNil(FleetFormat.jobBadge(0))
    }

    func testJobBadgeZeroPadsSingleDigits() {
        XCTAssertEqual(FleetFormat.jobBadge(1), "01")
        XCTAssertEqual(FleetFormat.jobBadge(4), "04")
    }

    func testJobBadgeKeepsTwoDigits() {
        XCTAssertEqual(FleetFormat.jobBadge(12), "12")
    }

    // MARK: - step

    func testStepNilRendersNotReported() {
        XCTAssertEqual(FleetFormat.step(nil), "Not reported")
    }

    func testStepBlankRendersNotReported() {
        XCTAssertEqual(FleetFormat.step("  "), "Not reported")
    }

    func testStepKeepsPlainTextUnchanged() {
        XCTAssertEqual(FleetFormat.step("Viewing design PNG"), "Viewing design PNG")
    }

    func testStepTrimsSurroundingWhitespace() {
        XCTAssertEqual(FleetFormat.step("  Viewing design PNG \n"), "Viewing design PNG")
    }

    // MARK: - status

    func testStatusZeroIsAllClear() {
        XCTAssertEqual(FleetFormat.status(0), "All clear")
    }

    func testStatusOneIsSingularCritical() {
        XCTAssertEqual(FleetFormat.status(1), "1 critical")
    }

    func testStatusPluralIsNCritical() {
        XCTAssertEqual(FleetFormat.status(3), "3 critical")
    }

    // MARK: - linked

    func testLinkedAllOnline() {
        XCTAssertEqual(FleetFormat.linked(6, of: 6), "6/6 linked")
    }

    func testLinkedPartialReportsBothNumbers() {
        XCTAssertEqual(FleetFormat.linked(5, of: 6), "5/6 linked")
    }

    // MARK: - fraction

    func testFractionMapsPercentOntoUnitRange() {
        XCTAssertEqual(FleetFormat.fraction(50), 0.5, accuracy: 0.0001)
    }

    func testFractionClampsAboveToOne() {
        XCTAssertEqual(FleetFormat.fraction(150), 1.0, accuracy: 0.0001)
    }

    func testFractionClampsBelowToZero() {
        XCTAssertEqual(FleetFormat.fraction(-10), 0.0, accuracy: 0.0001)
    }

    func testFractionRealZeroMapsToZero() {
        XCTAssertEqual(FleetFormat.fraction(0), 0.0, accuracy: 0.0001)
    }

    // MARK: - isHighPressure

    func testHighPressureJustBelowNinetyFiveIsFalse() {
        XCTAssertFalse(FleetFormat.isHighPressure(94.9))
    }

    func testHighPressureAtNinetyFiveIsTrue() {
        XCTAssertTrue(FleetFormat.isHighPressure(95))
    }

    func testHighPressureAtFullIsTrue() {
        XCTAssertTrue(FleetFormat.isHighPressure(100))
    }

    // MARK: - responseDetail

    func testResponseDetailBusyCountsJobs() {
        XCTAssertEqual(FleetFormat.responseDetail(lane(.busy, jobs: [job("a"), job("b")])), "2 jobs")
    }

    func testResponseDetailBusyWithoutJobsIsWorking() {
        XCTAssertEqual(FleetFormat.responseDetail(lane(.busy)), "Working")
    }

    func testResponseDetailIdleIsIdle() {
        XCTAssertEqual(FleetFormat.responseDetail(lane(.idle)), "Idle")
    }

    func testResponseDetailOfflineIsOffline() {
        XCTAssertEqual(FleetFormat.responseDetail(lane(.offline)), "Offline")
    }

    // MARK: - fleetBaseURL

    func testFleetBaseURLStripsOneTrailingSlash() {
        XCTAssertEqual(FleetFormat.fleetBaseURL("https://case.tail2f9fd5.ts.net/")?.absoluteString,
                       "https://case.tail2f9fd5.ts.net")
    }

    func testFleetBaseURLStripsAllTrailingSlashes() {
        XCTAssertEqual(FleetFormat.fleetBaseURL("https://example.com///")?.absoluteString,
                       "https://example.com")
    }

    func testFleetBaseURLTrimsSurroundingWhitespace() {
        XCTAssertEqual(FleetFormat.fleetBaseURL("  https://case.tail2f9fd5.ts.net/ \n")?.absoluteString,
                       "https://case.tail2f9fd5.ts.net")
    }

    func testFleetBaseURLKeepsPlainURL() {
        XCTAssertEqual(FleetFormat.fleetBaseURL("https://example.com")?.absoluteString,
                       "https://example.com")
    }

    func testFleetBaseURLKeepsPathAndDropsOnlyTrailingSlash() {
        XCTAssertEqual(FleetFormat.fleetBaseURL("https://example.com/fleet/")?.absoluteString,
                       "https://example.com/fleet")
    }

    func testFleetBaseURLIsNilWhenBlank() {
        XCTAssertNil(FleetFormat.fleetBaseURL(""))
        XCTAssertNil(FleetFormat.fleetBaseURL("   "))
        XCTAssertNil(FleetFormat.fleetBaseURL("\n\t"))
        XCTAssertNil(FleetFormat.fleetBaseURL("/"))
    }
}
