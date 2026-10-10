//
//  FleetFormatTests.swift
//  boringNotchTests
//
//  Unit tests for the pure formatters in `FleetFormat`. `FleetModels.swift`,
//  `FleetFormat.swift` and `FleetPanelModel.swift` are compiled directly into
//  this test module, so no `@testable import` is needed.
//

import XCTest
import AppKit

final class FleetFormatTests: XCTestCase {

    // MARK: - Helpers

    private func job(_ key: String) -> FleetJob {
        FleetJob(key: key, pill: "frank", label: "Reviewing the diff", step: nil, elapsedSec: nil)
    }

    private func lane(_ state: FleetNodeState, jobs: [FleetJob] = [], decisions: [FleetDecision] = []) -> FleetLane {
        FleetLane(id: "frank", label: "frank", state: state, jobs: jobs, decisions: decisions)
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

    // MARK: - decisionDetail

    /// The alert's detail line reads the first open entry's pull request, falling back to
    /// "Needs decision" when none was reported. `responseDetail` stays the lane's activity
    /// detail: a busy lane still reads "Working" even with an open decision.
    func testDecisionDetailReadsTheFirstOpenEntry() {
        let monitor = FleetDecision(job: "monitor-landscape-scale", pr: 4, reason: "no_progress", round: 4)
        let other = FleetDecision(job: "other-job", pr: nil, reason: nil, round: nil)
        XCTAssertEqual(FleetFormat.decisionDetail(lane(.idle, decisions: [monitor])), "PR #4")
        XCTAssertEqual(FleetFormat.decisionDetail(lane(.idle, decisions: [other])), "Needs decision")
        XCTAssertEqual(FleetFormat.decisionDetail(lane(.idle, decisions: [monitor, other])), "PR #4")
        XCTAssertEqual(FleetFormat.decisionDetail(lane(.idle, decisions: [other, monitor])), "Needs decision")
        XCTAssertEqual(FleetFormat.responseDetail(lane(.busy, decisions: [monitor])), "Working")
    }

    func testDecisionReasonMapsTheThreeReasonsToPlainWords() {
        XCTAssertEqual(FleetFormat.decisionReason("repeat_finding", round: nil), "same problem came back")
        XCTAssertEqual(FleetFormat.decisionReason("no_progress", round: nil), "fixes not reducing problems")
        XCTAssertEqual(FleetFormat.decisionReason("round_limit", round: 4), "4 fix rounds used")
    }

    func testDecisionReasonRoundLimitWithoutARoundStillReads() {
        XCTAssertEqual(FleetFormat.decisionReason("round_limit", round: nil), "round limit reached")
    }

    func testDecisionReasonUnknownFallsBackToDecisionNeeded() {
        XCTAssertEqual(FleetFormat.decisionReason(nil, round: 4), "decision needed")
        XCTAssertEqual(FleetFormat.decisionReason("", round: nil), "decision needed")
        XCTAssertEqual(FleetFormat.decisionReason("something_new", round: nil), "decision needed")
    }

    func testDecisionSubjectJoinsJobAndPullRequest() {
        XCTAssertEqual(FleetFormat.decisionSubject(
            FleetDecision(job: "monitor-landscape-scale", pr: 4, reason: nil, round: nil)),
                       "monitor-landscape-scale · PR #4")
    }

    func testDecisionSubjectToleratesMissingParts() {
        XCTAssertEqual(FleetFormat.decisionSubject(
            FleetDecision(job: "monitor-landscape-scale", pr: nil, reason: nil, round: nil)),
                       "monitor-landscape-scale")
        XCTAssertEqual(FleetFormat.decisionSubject(FleetDecision(job: nil, pr: 4, reason: nil, round: nil)), "PR #4")
        XCTAssertEqual(FleetFormat.decisionSubject(FleetDecision(job: "   ", pr: 4, reason: nil, round: nil)), "PR #4")
        XCTAssertEqual(FleetFormat.decisionSubject(
            FleetDecision(job: nil, pr: nil, reason: nil, round: nil)),
                       FleetFormat.unknown)
    }

    // MARK: - decision staleness

    func testDecisionStalenessMarksOnlyAnUnreachableFeed() {
        XCTAssertNil(FleetFormat.decisionStaleness(true))
        XCTAssertEqual(FleetFormat.decisionStaleness(false), "last known")
    }

    func testDecisionCountLabelOnlyAppearsAboveOne() {
        XCTAssertNil(FleetFormat.decisionCountLabel(0))
        XCTAssertNil(FleetFormat.decisionCountLabel(1))
        XCTAssertEqual(FleetFormat.decisionCountLabel(2), "2 open")
        XCTAssertEqual(FleetFormat.decisionCountLabel(5), "5 open")
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

    // MARK: - Panel metrics: the strings must fit their blocks

    private func monospacedWidth(_ text: String, size: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The owner saw "Offli…" and "1 j…" once the text grew to 11 pt. The panel now gives the
    /// response-map row `responseMapColumnWidth` minus its fixed furniture, and the closed row's
    /// side block `closedRowTextWidth`; every string those blocks can hold has to fit.
    func testMapAndClosedRowStringsFitTheirMetrics() {
        let detailBudget = FleetPanelMetrics.responseMapColumnWidth - FleetPanelMetrics.responseMapRowOverhead
        for detail in ["Idle", "Offline", "Working", "1 job", "2 jobs"] {
            XCTAssertLessThanOrEqual(
                monospacedWidth(detail, size: FleetPanelMetrics.minTextSize), detailBudget,
                "\(detail) does not fit the response-map detail budget")
        }
        for status in ["1 working", "3 critical", FleetFormat.linked(7, of: 7)] {
            XCTAssertLessThanOrEqual(
                monospacedWidth(status, size: FleetPanelMetrics.minTextSize),
                FleetPanelMetrics.closedRowTextWidth,
                "\(status) does not fit the closed row's text budget")
        }
    }

    /// A response-map column cannot be narrower than its furniture plus the detail budget, and the
    /// closed row's side block cannot be narrower than its mini map, gap and text budget.
    func testBlockWidthsCoverTheirContents() {
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapColumnWidth,
                                    FleetPanelMetrics.responseMapRowOverhead + 50)
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapWidth,
                                    2 * FleetPanelMetrics.responseMapColumnWidth + 60)
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.closedRowSideWidth,
                                    FleetPanelMetrics.closedRowMapWidth + 10 + FleetPanelMetrics.closedRowTextWidth)
    }
}
