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

    func testResponseDetailSaysNeedsYouForALaneWithAnOpenDecision() {
        let alert = lane(.idle, decisions: [FleetDecision(job: "notch-map-overlap", pr: 4)])
        XCTAssertEqual(FleetFormat.responseDetail(alert), "Needs you")
        XCTAssertEqual(FleetFormat.responseDetail(lane(.busy, decisions: [])), "Working")
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
        for detail in ["Idle", "Offline", "Working", "1 job", "2 jobs", "39 tok/s"] {
            XCTAssertLessThanOrEqual(
                monospacedWidth(detail, size: FleetPanelMetrics.minTextSize), detailBudget,
                "\(detail) does not fit the response-map detail budget")
        }
        // The alert lane reads "Needs you" from FleetFormat.responseDetail.
        let alertLane = FleetLane(id: "odin", label: "odin", state: .idle, jobs: [],
                                  decisions: [FleetDecision(job: "notch-map-overlap", pr: 4)])
        XCTAssertEqual(FleetFormat.responseDetail(alertLane), "Needs you")
        XCTAssertLessThanOrEqual(
            monospacedWidth("Needs you", size: FleetPanelMetrics.minTextSize),
            FleetPanelMetrics.responseMapColumnWidth - 11,
            "Needs you fits the alert row's detail room (that row has no badge)")
        for status in ["1 working", "3 critical", FleetFormat.linked(7, of: 7)] {
            XCTAssertLessThanOrEqual(
                monospacedWidth(status, size: FleetPanelMetrics.minTextSize),
                FleetPanelMetrics.closedRowTextWidth,
                "\(status) does not fit the closed row's text budget")
        }
    }

    /// The new design must not make the notch taller: the panel is the 300 pt it always was, and the
    /// map still has room for four rows of `responseMapMinRowHeight`.
    func testPanelStaysAtItsOldHeightAndFitsTheMapRows() {
        XCTAssertEqual(FleetPanelMetrics.fleetSectionHeight, 300,
                       "the new design must not make the notch taller")
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapHeight(rows: 4),
                                    4 * FleetPanelMetrics.responseMapMinRowHeight,
                                    "the map's grid is four rows of responseMapMinRowHeight")
        let nameLine = NSFont.systemFont(ofSize: 12)
        let statusLine = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let linePair = (nameLine.ascender - nameLine.descender + nameLine.leading)
            + 1
            + (statusLine.ascender - statusLine.descender + statusLine.leading)
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapMinRowHeight, linePair,
                                    "one map row fits the 12 pt name line and the 11 pt status line")
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

    // MARK: - actionNeededLabel

    func testActionNeededLabelCounts() {
        XCTAssertNil(FleetFormat.actionNeededLabel(0))
        XCTAssertEqual(FleetFormat.actionNeededLabel(1), "1 ACTION NEEDED")
        XCTAssertEqual(FleetFormat.actionNeededLabel(4), "4 ACTIONS NEEDED")
    }

    // MARK: - decisionChip

    func testDecisionChipNamesTheJobAndThePR() {
        XCTAssertEqual(FleetFormat.decisionChip(FleetDecision(job: "ciri-skill-trim", pr: 9)),
                       "ciri-skill-trim #9")
        XCTAssertEqual(FleetFormat.decisionChip(FleetDecision(job: "notch-map-overlap")), "notch-map-overlap")
        XCTAssertEqual(FleetFormat.decisionChip(FleetDecision(pr: 4)), "#4")
        XCTAssertEqual(FleetFormat.decisionChip(FleetDecision()), "—")
    }

    // MARK: - decisionWhy

    func testDecisionWhyAddsTheRoundExceptWhenTheReasonNamesIt() {
        XCTAssertEqual(FleetFormat.decisionWhy(FleetDecision(reason: "repeat_finding", round: 4)),
                       "same problem came back · round 4 of 4")
        XCTAssertEqual(FleetFormat.decisionWhy(FleetDecision(reason: "no_progress", round: 3)),
                       "fixes not reducing problems · round 3 of 4")
        XCTAssertEqual(FleetFormat.decisionWhy(FleetDecision(reason: "product_choice")), "product choice")
        XCTAssertEqual(FleetFormat.decisionWhy(FleetDecision(reason: "round_limit", round: 4)),
                       "4 fix rounds used")
    }

    // MARK: - decisionQuestion

    func testDecisionQuestionFallsBackToTheReason() {
        XCTAssertEqual(FleetFormat.decisionQuestion(FleetDecision(question: "Remove the other 29 skills?")),
                       "Remove the other 29 skills?")
        XCTAssertEqual(FleetFormat.decisionQuestion(FleetDecision(reason: "product_choice", question: "   ")),
                       "Odin stopped: product choice. How do we go on?")
        XCTAssertEqual(FleetFormat.decisionQuestion(FleetDecision(reason: "repeat_finding", round: 4)),
                       "Odin stopped: same problem came back. How do we go on?")
    }

    // MARK: - decisionProgress

    func testDecisionProgressReadsOneOpenOrNOfM() {
        XCTAssertEqual(FleetFormat.decisionProgress(index: 0, count: 1), "1 open")
        XCTAssertEqual(FleetFormat.decisionProgress(index: 0, count: 4), "1 of 4")
        XCTAssertEqual(FleetFormat.decisionProgress(index: 2, count: 4), "3 of 4")
        XCTAssertEqual(FleetFormat.decisionProgress(index: 9, count: 4), "4 of 4")
    }

    // MARK: - healthLine

    func testHealthLineReadsTasksLinkedAndStatus() {
        XCTAssertEqual(FleetFormat.healthLine(runningTasks: 0, linked: 7, of: 7, critical: 0),
                       "0 tasks · 7/7 linked · All clear")
        XCTAssertEqual(FleetFormat.healthLine(runningTasks: 1, linked: 6, of: 7, critical: 1),
                       "1 task · 6/7 linked · 1 critical")
    }

    // MARK: - speed

    func testSpeedNumberTextReadsCurrentThenLastThenUnknown() {
        XCTAssertEqual(FleetFormat.speedNumberText(FleetSpeed(current: 154.4, lastAt: "x")), "154")
        XCTAssertEqual(FleetFormat.speedNumberText(FleetSpeed(current: 38.5, lastAt: "x")), "39")
        XCTAssertEqual(FleetFormat.speedNumberText(FleetSpeed(current: nil, lastAt: "x", trend: [120, nil, 38.5])), "39")
        XCTAssertEqual(FleetFormat.speedNumberText(FleetSpeed(current: nil, lastAt: nil, trend: [nil, nil])), "—")
        XCTAssertEqual(FleetFormat.speedNumberText(nil), "—")
    }

    func testSpeedIsIdleOnlyWithoutACurrentReading() {
        XCTAssertTrue(FleetFormat.speedIsIdle(FleetSpeed(current: nil, lastAt: nil)))
        XCTAssertTrue(FleetFormat.speedIsIdle(nil))
        XCTAssertFalse(FleetFormat.speedIsIdle(FleetSpeed(current: 0, lastAt: nil)))
    }

    func testSpeedDetailOnlyForABusyLaneWithAReading() {
        let busy = FleetLane(id: "frank", label: "frank", state: .busy, jobs: [], speed: 38.5)
        XCTAssertEqual(FleetFormat.speedDetail(busy), "39 tok/s")
        XCTAssertEqual(FleetFormat.responseDetail(busy), "39 tok/s")
        let idle = FleetLane(id: "frank", label: "frank", state: .idle, jobs: [], speed: 38.5)
        XCTAssertNil(FleetFormat.speedDetail(idle))
        XCTAssertEqual(FleetFormat.responseDetail(idle), "Idle")
        let busyWithout = FleetLane(id: "frank", label: "frank", state: .busy, jobs: [])
        XCTAssertNil(FleetFormat.speedDetail(busyWithout))
        XCTAssertEqual(FleetFormat.responseDetail(busyWithout), "Working")
    }
}
