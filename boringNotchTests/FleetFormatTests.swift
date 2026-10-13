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
import SwiftUI

final class FleetFormatTests: XCTestCase {

    // MARK: - Helpers

    private func job(_ key: String) -> FleetJob {
        FleetJob(key: key, pill: "frank", label: "Reviewing the diff", step: nil, elapsedSec: nil)
    }

    private func lane(_ state: FleetNodeState, jobs: [FleetJob] = [], decisions: [FleetDecision] = []) -> FleetLane {
        FleetLane(id: "frank", label: "frank", state: state, jobs: jobs, decisions: decisions)
    }

    /// The response map's origin lane ("case"), with `jobs` jobs and an optional reported speed.
    private func origin(_ state: FleetNodeState, jobs: Int = 0, speed: Double? = nil) -> FleetLane {
        FleetLane(id: "case", label: "case", state: state,
                  jobs: (0..<jobs).map { job("j\($0)") }, speed: speed)
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

    // MARK: - closed alert

    func testClosedAlertIsHiddenWhenAllIsWell() {
        XCTAssertNil(FleetFormat.closedAlert(critical: 0, down: 0))
    }

    func testClosedAlertShowsModelDownMachines() {
        XCTAssertEqual(FleetFormat.closedAlert(critical: 0, down: 2), "2 down")
    }

    func testClosedAlertCriticalWinsOverDown() {
        XCTAssertEqual(FleetFormat.closedAlert(critical: 3, down: 1), "3 critical")
    }

    /// Both sides take the wider text, never past the cap: a short row makes a narrow notch.
    func testClosedRowSideTakesTheWiderTextUpToTheCap() {
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 60, right: 70), 70)
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 90, right: 70), 90)
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 400, right: 70), FleetPanelMetrics.closedRowSideWidth)
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

    // MARK: - Case jobs: reasons, line, badge, proof

    func testNewDecisionReasonsReadInPlainWords() {
        XCTAssertEqual(FleetFormat.decisionReason("no_commit", round: 2), "fix round, no new commit")
        XCTAssertEqual(FleetFormat.decisionReason("qa_skipped", round: nil), "review could not run")
        XCTAssertEqual(FleetFormat.decisionReason("watchdog_stalled", round: nil), "job stuck after restart")
        XCTAssertEqual(FleetFormat.decisionWhy(FleetDecision(reason: "no_commit", round: 2)),
                       "fix round, no new commit · round 2 of 4")
    }

    func testCommitAgeIsShort() {
        XCTAssertNil(FleetFormat.commitAge(minutes: nil))
        XCTAssertEqual(FleetFormat.commitAge(minutes: 0), "0m")
        XCTAssertEqual(FleetFormat.commitAge(minutes: 12), "12m")
        XCTAssertEqual(FleetFormat.commitAge(minutes: 59), "59m")
        XCTAssertEqual(FleetFormat.commitAge(minutes: 60), "1h00m")
        XCTAssertEqual(FleetFormat.commitAge(minutes: 125), "2h05m")
        XCTAssertEqual(FleetFormat.commitAge(minutes: 1500), "1d")
        XCTAssertEqual(FleetFormat.commitAge(minutes: -3), "0m")
    }

    func testWatchdogBadgeRules() {
        func badge(_ state: String?) -> FleetFormat.CaseJobBadge? {
            FleetFormat.caseJobBadge(CaseJobWatchdog(state: state))
        }
        XCTAssertEqual(badge("nudged"), FleetFormat.CaseJobBadge(text: "NUDGED", level: .amber))
        XCTAssertEqual(badge("restarted"), FleetFormat.CaseJobBadge(text: "RESTART", level: .amber))
        XCTAssertEqual(badge("escalated"), FleetFormat.CaseJobBadge(text: "STUCK", level: .red))
        XCTAssertNil(badge("ok"))
        XCTAssertNil(badge("none"))
        XCTAssertNil(badge("something_new"))
        XCTAssertNil(badge(nil))
        XCTAssertNil(FleetFormat.caseJobBadge(nil))
    }

    func testCaseJobLineFullAndPartial() {
        let full = CaseJob(job: "notch-job-heartbeat", running: true, itemsPassed: 2, itemsTotal: 5,
                           minutesSinceCommit: 12, watchdog: CaseJobWatchdog(state: "nudged"))
        XCTAssertEqual(FleetFormat.caseJobLine(full),
                       FleetFormat.CaseJobLine(name: "notch-job-heartbeat", items: "2/5", commit: "12m",
                                               commitIsStale: false,
                                               badge: FleetFormat.CaseJobBadge(text: "NUDGED", level: .amber)))
        let bare = FleetFormat.caseJobLine(CaseJob(job: "a", running: true))
        XCTAssertEqual(bare, FleetFormat.CaseJobLine(name: "a", items: nil, commit: nil,
                                                     commitIsStale: false, badge: nil))
        // A total of zero or a passed count above the total never reads oddly.
        XCTAssertNil(FleetFormat.caseJobLine(CaseJob(job: "a", itemsPassed: 0, itemsTotal: 0)).items)
        XCTAssertEqual(FleetFormat.caseJobLine(CaseJob(job: "a", itemsPassed: 9, itemsTotal: 5)).items, "5/5")
        XCTAssertEqual(FleetFormat.caseJobLine(CaseJob(job: "a", itemsTotal: 5)).items, "0/5")
    }

    func testCommitAgeTurnsAmberAfterSixtyMinutes() {
        func stale(_ minutes: Int?) -> Bool {
            FleetFormat.caseJobLine(CaseJob(job: "a", minutesSinceCommit: minutes)).commitIsStale
        }
        XCTAssertFalse(stale(nil))
        XCTAssertFalse(stale(12))
        XCTAssertFalse(stale(60))
        XCTAssertTrue(stale(61))
        XCTAssertTrue(stale(300))
    }

    func testProofLine() {
        XCTAssertEqual(FleetFormat.proofLine(CaseJobProof(total: 4, proven: 2, missing: 2, blocking: 0)),
                       FleetFormat.CaseJobProofLine(text: "proof 2/4", blocking: nil))
        XCTAssertEqual(FleetFormat.proofLine(CaseJobProof(total: 4, proven: 2, missing: 2, blocking: 1)),
                       FleetFormat.CaseJobProofLine(text: "proof 2/4", blocking: "1 blocking"))
        XCTAssertNil(FleetFormat.proofLine(nil))
        XCTAssertNil(FleetFormat.proofLine(CaseJobProof(total: 0, proven: 0, missing: 0, blocking: 0)))
        XCTAssertNil(FleetFormat.proofLine(CaseJobProof()))
    }

    func testDecisionProofComesFromTheMatchingJob() {
        let jobs = [CaseJob(job: "other", proof: CaseJobProof(total: 3, proven: 3, missing: 0, blocking: 0)),
                    CaseJob(job: "mine", proof: CaseJobProof(total: 4, proven: 2, missing: 2, blocking: 1))]
        XCTAssertEqual(FleetFormat.decisionProof(FleetDecision(job: "mine"), jobs: jobs)?.text, "proof 2/4")
        XCTAssertNil(FleetFormat.decisionProof(FleetDecision(job: "unknown"), jobs: jobs))
        XCTAssertNil(FleetFormat.decisionProof(FleetDecision(), jobs: jobs))
        XCTAssertNil(FleetFormat.decisionProof(FleetDecision(job: "mine"), jobs: []))
    }

    // MARK: - Case jobs: the strings must fit

    /// A job line is name + `12/12` + `1h59m` + `RESTART`; the right part has to leave the name its floor.
    func testLongestCaseJobLineLeavesTheNameItsFloor() {
        let size = FleetPanelMetrics.minTextSize
        let right = ["12/12", "1h59m", "RESTART"]
        let width = right.reduce(CGFloat(0)) { $0 + monospacedWidth($1, size: size) }
            + FleetPanelMetrics.caseJobLineSpacing * CGFloat(right.count)
        XCTAssertLessThanOrEqual(width, FleetPanelMetrics.workColumnWidth - FleetPanelMetrics.caseJobMinNameWidth,
                                 "items, age and badge leave the job name its floor")
    }

    /// The decision detail's why row: the longest reason, the proof readout and the PR button share one line.
    func testWhyRowFitsReasonProofAndPullRequestButton() {
        let size = FleetPanelMetrics.minTextSize
        let rowWidth: CGFloat = 604 - 19
        let prButton: CGFloat = 100
        let proof = ["proof 12/12", "12 blocking"]
        let proofWidth = proof.reduce(CGFloat(0)) { $0 + monospacedWidth($1, size: size) } + 8 * 3
        for reason in ["repeat_finding", "no_progress", "round_limit", "no_commit", "qa_skipped", "watchdog_stalled",
                       "product_choice"] {
            let why = FleetFormat.decisionWhy(FleetDecision(reason: reason, round: 4))
            XCTAssertLessThanOrEqual(monospacedWidth(why, size: size) + proofWidth + prButton, rowWidth,
                                     "\(why) does not fit the why row with proof")
        }
    }

    /// The heartbeat lines and the shorter preview list stay inside the column's height: the notch does not grow.
    func testWorkColumnStaysInItsHeight() {
        for lines in 0...FleetPanelMetrics.caseJobLineLimit {
            let previews = FleetPanelMetrics.previewLimit(caseJobLines: lines)
            XCTAssertLessThanOrEqual(
                FleetPanelMetrics.workContentHeight(caseJobLines: lines, previews: previews, moreLink: true),
                FleetPanelMetrics.workColumnHeight, "\(lines) heartbeat lines do not fit the column")
        }
        XCTAssertEqual(FleetPanelMetrics.previewLimit(caseJobLines: 0), 2, "no feed: the column reads as before")
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
        for detail in ["Idle", "Offline", "Working", "1 job", "2 jobs", "39 tok/s", "Down"] {
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
        // The closed row is one line per side; the longest left lines must fit the side budget.
        for line in ["12 working · 7 down", "12 working · 3 critical", "120 tok/s"] {
            XCTAssertLessThanOrEqual(
                monospacedWidth(line, size: FleetPanelMetrics.minTextSize),
                FleetPanelMetrics.closedRowTextWidth,
                "\(line) does not fit the closed row's text budget")
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
    /// closed row's side block cannot be narrower than its one-line text budget.
    func testBlockWidthsCoverTheirContents() {
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapColumnWidth,
                                    FleetPanelMetrics.responseMapRowOverhead + 50)
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.responseMapWidth,
                                    2 * FleetPanelMetrics.responseMapColumnWidth + 60)
        XCTAssertGreaterThanOrEqual(FleetPanelMetrics.closedRowSideWidth,
                                    FleetPanelMetrics.closedRowTextWidth)
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
        XCTAssertEqual(FleetFormat.healthLine(runningTasks: 1, linked: 7, of: 7, critical: 0, down: 1),
                       "1 task · 7/7 linked · 1 down")
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

    func testMedianSpeedIsTheMedianOfTheReportingDevices() {
        XCTAssertNil(FleetFormat.medianSpeed([]))
        XCTAssertNil(FleetFormat.medianSpeed([nil, nil]))
        XCTAssertNil(FleetFormat.medianSpeed([nil]))
        XCTAssertEqual(FleetFormat.medianSpeed([nil, 38.5, nil]) ?? 0, 38.5, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.medianSpeed([30, 10, 20]) ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.medianSpeed([10, 20]) ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.medianSpeed([0, 40, nil]) ?? 0, 20, accuracy: 0.001)
    }

    /// The owner's case: with a single writer the fleet number is that writer's own speed.
    func testOneWriterAtThirtyNineIsTheFleetNumberAndTheHeaderText() {
        let fleet = FleetSpeed(current: FleetFormat.medianSpeed([nil, 38.5, nil, nil]), lastAt: nil)
        XCTAssertEqual(fleet.current ?? 0, 38.5, accuracy: 0.001)
        XCTAssertEqual(FleetFormat.speedNumberText(fleet), "39")
        XCTAssertFalse(FleetFormat.speedIsIdle(fleet))
    }

    /// Answering the 4th of 4 decisions leaves three: the index clamps to 2, so the third chip stays
    /// selected and the steppers step from there.
    func testClampedIndexKeepsAChipSelectedWhenTheListShrinks() {
        XCTAssertEqual(FleetFormat.clampedIndex(3, count: 4), 3)
        XCTAssertEqual(FleetFormat.clampedIndex(3, count: 3), 2)
        XCTAssertEqual(FleetFormat.clampedIndex(2, count: 3), 2)
        XCTAssertEqual(FleetFormat.clampedIndex(0, count: 3), 0)
        XCTAssertEqual(FleetFormat.clampedIndex(9, count: 4), 3)
        XCTAssertEqual(FleetFormat.clampedIndex(-2, count: 4), 0)
        XCTAssertEqual(FleetFormat.clampedIndex(2, count: 0), 0)
    }

    // MARK: - Footer rings

    func testRingLevelSplitsOkHotAlertAtTheDesignBoundaries() {
        XCTAssertNil(FleetFormat.ringLevel(nil))
        XCTAssertEqual(FleetFormat.ringLevel(0), .ok)
        XCTAssertEqual(FleetFormat.ringLevel(69), .ok)
        XCTAssertEqual(FleetFormat.ringLevel(70), .hot)
        XCTAssertEqual(FleetFormat.ringLevel(89), .hot)
        XCTAssertEqual(FleetFormat.ringLevel(90), .alert)
        XCTAssertEqual(FleetFormat.ringLevel(100), .alert)
    }

    func testRingValueTextPrintsThePercentAndDashesWhenMissing() {
        XCTAssertEqual(FleetFormat.ringValueText(88), "88")
        XCTAssertEqual(FleetFormat.ringValueText(0), "0")
        XCTAssertEqual(FleetFormat.ringValueText(nil), "—")
    }

    func testRingHeadlineNamesTheHighestReadingWithItsType() {
        let gpuTop = FleetHostReading(id: "frank", label: "frank", cpu: 13, gpu: 94, ram: 86, live: true)
        XCTAssertEqual(FleetFormat.ringHeadline(gpuTop), "GPU 94")
        let ramTop = FleetHostReading(id: "claire", label: "claire", cpu: 0, gpu: 0, ram: 88, live: true)
        XCTAssertEqual(FleetFormat.ringHeadline(ramTop), "RAM 88")
        // A reported 0 is still a reading: zeroes print as "CPU 0", never as the dash.
        let zeros = FleetHostReading(id: "case", label: "case", cpu: 0, gpu: 0, ram: 0, live: true)
        XCTAssertEqual(FleetFormat.ringHeadline(zeros), "CPU 0")
        // Ties keep ring order: cpu, then gpu, then ram.
        let tie = FleetHostReading(id: "dali", label: "dali", cpu: 88, gpu: 88, ram: 50, live: true)
        XCTAssertEqual(FleetFormat.ringHeadline(tie), "CPU 88")
        let missing = FleetHostReading(id: "mac", label: "mac", cpu: nil, gpu: nil, ram: nil, live: false)
        XCTAssertEqual(FleetFormat.ringHeadline(missing), "—")
    }

    func testRingDetailListsAllThreeNumbersForTheTooltipAndVoiceOver() {
        let host = FleetHostReading(id: "frank", label: "frank", cpu: 13, gpu: 94, ram: 86, live: true)
        XCTAssertEqual(FleetFormat.ringDetail(host), "frank: CPU 13% · GPU 94% · RAM 86%")
        let gapped = FleetHostReading(id: "mac", label: "mac", cpu: nil, gpu: 12, ram: nil, live: true)
        XCTAssertEqual(FleetFormat.ringDetail(gapped), "mac: CPU — · GPU 12% · RAM —")
    }

    // MARK: - Case box: the origin's work

    func testCaseBoxStateReadsTheOriginsWork() {
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.busy)), "Working")
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.idle)), "Online")
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.offline)), "Offline")
    }

    func testCaseBoxJobCountOnlyWhileBusyWithJobs() {
        XCTAssertEqual(FleetFormat.caseBoxJobs(origin(.busy, jobs: 1)), "1 job")
        XCTAssertEqual(FleetFormat.caseBoxJobs(origin(.busy, jobs: 2)), "2 jobs")
        XCTAssertNil(FleetFormat.caseBoxJobs(origin(.busy, jobs: 0)))
        XCTAssertNil(FleetFormat.caseBoxJobs(origin(.idle, jobs: 3)))
        XCTAssertNil(FleetFormat.caseBoxJobs(origin(.offline, jobs: 1)))
    }

    /// The closed row's right side: a reported speed wins; with none, running jobs replace the dash.
    func testClosedRightReadingFallsBackToTheJobCountWithoutASpeed() {
        let idleTotal = FleetFormat.closedRightReading(speed: nil, jobs: 0)
        XCTAssertEqual(idleTotal.number, "—")
        XCTAssertEqual(idleTotal.unit, " tok/s total")
        XCTAssertTrue(idleTotal.dim)

        let twoJobs = FleetFormat.closedRightReading(speed: nil, jobs: 2)
        XCTAssertEqual(twoJobs.number, "2")
        XCTAssertEqual(twoJobs.unit, " jobs")
        XCTAssertFalse(twoJobs.dim)

        let oneJob = FleetFormat.closedRightReading(speed: nil, jobs: 1)
        XCTAssertEqual(oneJob.number, "1")
        XCTAssertEqual(oneJob.unit, " job")
        XCTAssertFalse(oneJob.dim)

        let current = FleetFormat.closedRightReading(
            speed: FleetSpeed(current: 154.4, lastAt: nil, trend: [], stepSec: 10), jobs: 3)
        XCTAssertEqual(current.number, "154")
        XCTAssertEqual(current.unit, " tok/s total")
        XCTAssertFalse(current.dim)

        let last = FleetFormat.closedRightReading(
            speed: FleetSpeed(current: nil, lastAt: nil, trend: [120.0], stepSec: 10), jobs: 5)
        XCTAssertEqual(last.number, "120")
        XCTAssertEqual(last.unit, " idle")
        XCTAssertTrue(last.dim)
    }

    /// The origin box says "Working" in the skin's accent - the black skin's only green - so
    /// an idle box that paints no accent at all proves the busy box's green pixels come from
    /// that one line.
    @MainActor
    func testBusyCaseBoxDrawsItsWorkInTheAccentColour() throws {
        // The box's data lines ask FleetType for the mono face, whose registration is memoised once
        // per process. Register the test bundle's own faces first: without this the render would pin
        // the system fallback for every later test, and FleetTypeTests would fail on our account.
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let theme = FleetTheme(skin: .black)
        let idle = origin(.idle)
        let busy = origin(.busy, jobs: 2)

        func bitmap(for lane: FleetLane) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: FleetCaseBoxView(lane: lane, theme: theme).background(Color.black))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "the case box rendered")
            return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)), "case box bitmap")
        }

        let busyPixels = accentPixelCount(try bitmap(for: busy), theme: theme)
        XCTAssertGreaterThan(busyPixels, 0, "the Working line draws in the accent")
        XCTAssertEqual(accentPixelCount(try bitmap(for: idle), theme: theme), 0,
                       "an idle box shows no accent at all")

        // A preview strip, only on request: `FLEET_CASE_BOX_PREVIEW=/tmp/box.png xcodebuild test`.
        guard let previewPath = ProcessInfo.processInfo.environment["FLEET_CASE_BOX_PREVIEW"] else { return }
        let strip = ImageRenderer(content: HStack(spacing: 20) {
            FleetCaseBoxView(lane: idle, theme: theme)
            FleetCaseBoxView(lane: busy, theme: theme)
        }.padding(16).background(Color.black))
        strip.scale = 3
        let stripImage = try XCTUnwrap(strip.nsImage, "the preview strip rendered")
        let stripBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(stripImage.tiffRepresentation)),
                                       "preview strip bitmap")
        let png = try XCTUnwrap(stripBitmap.representation(using: .png, properties: [:]), "preview PNG")
        XCTAssertNoThrow(try Data(png).write(to: URL(fileURLWithPath: previewPath)), "the preview wrote")
    }

    /// Pixels that are the skin's accent and nothing else: within 0.06 of the accent in every sRGB
    /// component, and saturated towards green. The box's greys (dim, muted, text and the stroke) all
    /// sit within 0.07 of grey on the green-minus-blue axis, the accent at 0.16, so the extra test
    /// keeps brightened grey antialiasing out of the count.
    private func accentPixelCount(_ bitmap: NSBitmapImageRep, theme: FleetTheme) -> Int {
        guard let accent = NSColor(theme.accent).usingColorSpace(.sRGB) else { return 0 }
        let target = (accent.redComponent, accent.greenComponent, accent.blueComponent)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(pixel.redComponent - target.0) <= 0.06,
                   abs(pixel.greenComponent - target.1) <= 0.06,
                   abs(pixel.blueComponent - target.2) <= 0.06,
                   pixel.greenComponent - pixel.blueComponent > 0.12 {
                    count += 1
                }
            }
        }
        return count
    }
}
