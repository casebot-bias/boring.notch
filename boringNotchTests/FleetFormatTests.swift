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

    /// An available reading (`state == "ok"`) carrying a value.
    private func ok(_ value: Double) -> Reading {
        Reading(value: value, state: "ok", note: nil)
    }

    /// An unavailable reading; the value may still be present, which must not
    /// make it usable.
    private func unavailable(_ value: Double?) -> Reading {
        Reading(value: value, state: "unavailable", note: nil)
    }

    // MARK: - percent

    func testPercentAvailableValueRoundsToNearestWhole() {
        XCTAssertEqual(FleetFormat.percent(ok(38.6)), "39%")
    }

    func testPercentAvailableValueRoundsDown() {
        XCTAssertEqual(FleetFormat.percent(ok(7.25)), "7%")
    }

    func testPercentRealZeroRendersAsZeroNeverDash() {
        XCTAssertEqual(FleetFormat.percent(ok(0)), "0%")
    }

    func testPercentUnavailableNilValueRendersDash() {
        XCTAssertEqual(FleetFormat.percent(unavailable(nil)), "—")
    }

    func testPercentUnavailableWithNumberStillRendersDash() {
        // State, not just a nil value, gates availability.
        XCTAssertEqual(FleetFormat.percent(unavailable(12.5)), "—")
    }

    // MARK: - celsius

    func testCelsiusAvailableValueRoundsDown() {
        XCTAssertEqual(FleetFormat.celsius(ok(32.2607)), "32°C")
    }

    func testCelsiusAvailableValueRoundsUp() {
        XCTAssertEqual(FleetFormat.celsius(ok(40.8)), "41°C")
    }

    func testCelsiusUnavailableRendersDash() {
        XCTAssertEqual(FleetFormat.celsius(unavailable(nil)), "—")
    }

    // MARK: - tokensPerSecond

    func testTokensPerSecondNilRendersDash() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(nil), "—")
    }

    func testTokensPerSecondZeroRendersZeroWithOneDecimal() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(0), "0.0 tok/s")
    }

    func testTokensPerSecondRendersOneDecimalPlace() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(12.34), "12.3 tok/s")
    }

    func testTokensPerSecondSmallValueRoundsToOneDecimal() {
        XCTAssertEqual(FleetFormat.tokensPerSecond(0.05), "0.1 tok/s")
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

    func testBarFractionMapsPercentOntoUnitRange() {
        XCTAssertEqual(FleetFormat.barFraction(ok(38.6)), 0.386, accuracy: 0.0001)
    }

    func testBarFractionClampsAboveToOne() {
        XCTAssertEqual(FleetFormat.barFraction(ok(150)), 1.0, accuracy: 0.0001)
    }

    func testBarFractionClampsBelowToZero() {
        XCTAssertEqual(FleetFormat.barFraction(ok(-10)), 0.0, accuracy: 0.0001)
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

    // MARK: - gpuOrTokens

    func testGpuOrTokensFallsBackToGPUWhenTokensAbsent() {
        XCTAssertEqual(FleetFormat.gpuOrTokens(gpu: ok(12.0), tokPerSec: nil), "GPU 12%")
    }

    func testGpuOrTokensPrefersTokensEvenWhenZero() {
        XCTAssertEqual(FleetFormat.gpuOrTokens(gpu: ok(12.0), tokPerSec: 0), "0.0 tok/s")
    }

    func testGpuOrTokensRendersDashWhenNeitherAvailable() {
        XCTAssertEqual(FleetFormat.gpuOrTokens(gpu: unavailable(nil), tokPerSec: nil), "—")
    }
}
