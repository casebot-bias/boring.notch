//
//  FleetFormatTests.swift
//  boringNotchTests
//
//  Unit tests for the pure formatters in `FleetFormat`. Both `FleetModels.swift`
//  and `FleetFormat.swift` are compiled directly into this test module, so no
//  `@testable import` is needed.
//

import XCTest

final class FleetFormatTests: XCTestCase {

    // MARK: - Helpers

    private func ok(_ value: Double) -> Reading {
        Reading(value: value, state: "ok", note: nil)
    }

    private func unavailable(_ value: Double?) -> Reading {
        Reading(value: value, state: "unavailable", note: nil)
    }
    // MARK: - unknown
    func testUnknownRendersDash() {
        XCTAssertEqual(FleetFormat.unknown, "—")
    }
    // MARK: - degrees
    func testDegreesAvailableValueRoundsDown() {
        XCTAssertEqual(FleetFormat.degrees(ok(38.37)), "38°")
    }

    func testDegreesAvailableValueRoundsUp() {
        XCTAssertEqual(FleetFormat.degrees(ok(40.8)), "41°")
    }

    func testDegreesRealZeroRendersAsZeroNeverDash() {
        XCTAssertEqual(FleetFormat.degrees(ok(0)), "0°")
    }

    func testDegreesUnavailableNilValueRendersDash() {
        XCTAssertEqual(FleetFormat.degrees(unavailable(nil)), "—")
    }

    func testDegreesUnavailableWithNumberStillRendersDash() {
        XCTAssertEqual(FleetFormat.degrees(unavailable(12.5)), "—")
    }
    // MARK: - tokensPerSecond
    func testTokensPerSecondNilRendersDash() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(nil), "—")
    }

    func testTokensPerSecondZeroRendersZeroWithoutDecimal() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(0), "0 t/s")
    }

    func testTokensPerSecondRoundsToWholeTokenPerSecond() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(12.34), "12 t/s")
    }

    func testTokensPerSecondSmallValueRoundsToZero() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(0.4), "0 t/s")
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
        XCTAssertEqual(FleetFormat.jobs(2), "2 jobs")
    }

    func testJobsMultipleIsJobs() {
        XCTAssertEqual(FleetFormat.jobs(5), "5 jobs")
    }
    // MARK: - elapsed
    func testElapsedNilRendersDash() {
        XCTAssertEqual(FleetFormat.elapsed(nil), "—")
    }

    func testElapsedNegativeRendersDash() {
        XCTAssertEqual(FleetFormat.elapsed(-1), "—")
    }

    func testElapsedZeroRendersAsZeroSeconds() {
        XCTAssertEqual(FleetFormat.elapsed(0), "0s")
    }

    func testElapsedUnderOneMinuteRendersSeconds() {
        XCTAssertEqual(FleetFormat.elapsed(44), "44s")
    }

    func testElapsedMinutesZeroPadSeconds() {
        XCTAssertEqual(FleetFormat.elapsed(1444), "24m 04s")
    }

    func testElapsedExactHourZeroPadsMinutes() {
        XCTAssertEqual(FleetFormat.elapsed(3600), "1h 00m")
    }

    func testElapsedHoursZeroPadMinutesAndDropSeconds() {
        XCTAssertEqual(FleetFormat.elapsed(3730), "1h 02m")
    }

    func testElapsedTwoHoursRendersHoursAndMinutes() {
        XCTAssertEqual(FleetFormat.elapsed(7200), "2h 00m")
    }
    // MARK: - barFraction
    func testBarFractionUnavailableIsZero() {
        XCTAssertEqual(FleetFormat.barFraction(unavailable(nil)), 0.0, accuracy: 0.0001)
    }

    func testBarFractionMapsValueOntoUnitRange() {
        XCTAssertEqual(FleetFormat.barFraction(ok(38.6)), 0.386, accuracy: 0.0001)
    }

    func testBarFractionClampsAboveToOne() {
        XCTAssertEqual(FleetFormat.barFraction(ok(150)), 1.0, accuracy: 0.0001)
    }

    func testBarFractionClampsBelowToZero() {
        XCTAssertEqual(FleetFormat.barFraction(ok(-10)), 0.0, accuracy: 0.0001)
    }

    func testBarFractionRealZeroMapsToZero() {
        XCTAssertEqual(FleetFormat.barFraction(ok(0)), 0.0, accuracy: 0.0001)
    }
    // MARK: - isRAMWarning
    func testRAMWarningAtEightyIsNotAWarning() {
        XCTAssertFalse(FleetFormat.isRAMWarning(ok(80)))
    }

    func testRAMWarningAboveEightyWarns() {
        XCTAssertTrue(FleetFormat.isRAMWarning(ok(80.1)))
    }

    func testRAMWarningIgnoredWhenUnavailable() {
        XCTAssertFalse(FleetFormat.isRAMWarning(unavailable(99)))
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
