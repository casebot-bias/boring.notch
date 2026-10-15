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

    /// The response map's origin lane ("case"), with `jobs` jobs, an optional reported speed and
    /// the `toolRuns` long commands the dashboard says its jobs are waiting on.
    private func origin(_ state: FleetNodeState, jobs: Int = 0, speed: Double? = nil,
                        toolRuns: [ToolRun] = []) -> FleetLane {
        FleetLane(id: "case", label: "case", state: state,
                  jobs: (0..<jobs).map { job("j\($0)") }, toolRuns: toolRuns, speed: speed)
    }

    /// One tool run as the activity feed reports it: `kind` "test"/"build"/"other", the optional
    /// job, label and elapsed seconds the formatter turns into a line. pid and since stay nil -
    /// the formatters never read them.
    private func run(kind: String, job: String? = nil, label: String? = nil,
                     elapsed: Int? = nil) -> ToolRun {
        ToolRun(job: job, kind: kind, label: label, pid: nil, since: nil, elapsedSec: elapsed)
    }

    /// A fixed clock instant from an ISO 8601 string with fractional seconds, so time-dependent
    /// formatters never judge by the wall clock.
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
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

    /// Both sides take the wider content plus the wing padding, never past the cap: a short row makes
    /// a narrow notch.
    func testClosedRowSideTakesTheWiderTextUpToTheCap() {
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 60, right: 70,
                                                        padding: FleetPanelMetrics.closedRowSidePadding), 82)
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 90, right: 70,
                                                        padding: FleetPanelMetrics.closedRowSidePadding), 102)
        XCTAssertEqual(FleetPanelMetrics.closedRowSide(left: 400, right: 70,
                                                        padding: FleetPanelMetrics.closedRowSidePadding),
                       FleetPanelMetrics.closedRowSideWidth)
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
        for line in ["12 working · 7 down", "12 working · 3 critical", "120 tok/s", "47 tok/s"] {
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

    // MARK: - Tool runs: the commands Case jobs wait on

    func testToolRunAgePrintsSecondsMinutesAndHours() {
        XCTAssertEqual(FleetFormat.toolRunAge(run(kind: "test", elapsed: 45)), "45s")
        XCTAssertEqual(FleetFormat.toolRunAge(run(kind: "test", elapsed: 600)), "10m")
        XCTAssertEqual(FleetFormat.toolRunAge(run(kind: "test", elapsed: 5400)), "1h30m")
        XCTAssertNil(FleetFormat.toolRunAge(run(kind: "test", elapsed: nil)),
                     "a run that reports no elapsed time has no age")
    }

    func testToolRunVerbNamesTheWorkTheKindMeans() {
        XCTAssertEqual(FleetFormat.toolRunVerb(run(kind: "test")), "testing")
        XCTAssertEqual(FleetFormat.toolRunVerb(run(kind: "build")), "building")
        XCTAssertEqual(FleetFormat.toolRunVerb(run(kind: "other")), "running")
        XCTAssertEqual(FleetFormat.toolRunVerb(run(kind: "")), "running",
                     "an absent or unknown kind still reads as plain running work")
    }

    func testToolRunLineJoinsThePartsItHas() {
        XCTAssertEqual(
            FleetFormat.toolRunLine(run(kind: "test", job: "monitor-platform-split",
                                        label: "smoke.cjs", elapsed: 600)),
            "monitor-platform-split · smoke.cjs · 10m")
        // A missing part drops out; the rest keep joining with the same separator.
        XCTAssertEqual(
            FleetFormat.toolRunLine(run(kind: "test", job: "monitor-platform-split", elapsed: 600)),
            "monitor-platform-split · 10m")
        XCTAssertEqual(
            FleetFormat.toolRunLine(run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs")),
            "monitor-platform-split · smoke.cjs")
        XCTAssertEqual(FleetFormat.toolRunLine(run(kind: "test", label: "smoke.cjs", elapsed: 600)),
                       "smoke.cjs · 10m")
    }

    func testClosedToolRunNamesOneRunOrCountsThem() throws {
        XCTAssertNil(FleetFormat.closedToolRun([]), "no runs: the closed row keeps its own reading")
        let one = try XCTUnwrap(FleetFormat.closedToolRun([run(kind: "test", elapsed: 600)]),
                                "one run is a reading")
        XCTAssertNil(one.number, "one run needs no count")
        XCTAssertEqual(one.word, "testing")
        XCTAssertEqual(one.age, "10m")
        let build = try XCTUnwrap(FleetFormat.closedToolRun([run(kind: "build", elapsed: 600)]),
                                  "one build run is a reading")
        XCTAssertEqual(build.word, "building")
        let many = try XCTUnwrap(
            FleetFormat.closedToolRun([run(kind: "test", elapsed: 600),
                                       run(kind: "build", elapsed: 120),
                                       run(kind: "other", elapsed: 30)]),
            "several runs are a reading")
        XCTAssertEqual(many.number, "3")
        XCTAssertEqual(many.word, "running")
        XCTAssertNil(many.age, "counting runs names no single age")
    }

    func testOldestToolRunIsTheOneWaitingLongest() {
        XCTAssertNil(FleetFormat.oldestToolRun([]), "no runs, no oldest")
        let old = run(kind: "test", job: "old", elapsed: 600)
        let fresh = run(kind: "build", job: "fresh", elapsed: 30)
        XCTAssertEqual(FleetFormat.oldestToolRun([fresh, old]), old,
                       "the run waiting longest is the oldest, whatever its place")
        let mute = run(kind: "other", job: "mute")
        XCTAssertEqual(FleetFormat.oldestToolRun([mute, old]), old,
                       "a run that reports no elapsed time never wins the title")
        let only = run(kind: "other", job: "mute")
        XCTAssertEqual(FleetFormat.oldestToolRun([only]), only,
                       "the lone run is the oldest of its list, elapsed time or not")
    }

    /// The row draws its sparkline at exactly this frame, so the number beside it never moves the
    /// notch: the strip the preview shows is 24 pt of trend, 10 pt tall - the 0.7 x 14 share rounded
    /// to a whole point, so the sparkline stays inside the shorter bar. The 24 pt width is the width
    /// cut's share of the bar's width budget: it pays for the speed number's three-digit reserve.
    func testClosedSparklineFrameIsItsFixedSize() {
        XCTAssertEqual(FleetPanelMetrics.closedSparklineWidth, 24)
        XCTAssertEqual(FleetPanelMetrics.closedSparklineHeight, 10,
                       "0.7 x 14, rounded to a whole point")
        XCTAssertLessThan(FleetPanelMetrics.closedSparklineHeight,
                          FleetPanelMetrics.closedBarHeight(30),
                          "and it fits inside the closed bar")
    }

    // MARK: - Closed sparkline series and speed grace

    func testSparklineSeriesIsAlwaysExactlyItsFrameOfPoints() {
        XCTAssertEqual(FleetFormat.sparklineSeries([]), Array(repeating: 0.0, count: 60),
                     "no trend reads as sixty quiet points, not an empty path")
        XCTAssertEqual(FleetFormat.sparklineSeries([nil, 3]),
                       Array(repeating: 0.0, count: 58) + [0, 3],
                     "the given points land last, nulls flat at zero, zero padding in front")
        // A trend longer than the frame keeps its newest `count` points.
        let long: [Double?] = (1...70).map(Double.init)
        XCTAssertEqual(FleetFormat.sparklineSeries(long), Array(11...70).map(Double.init))
        XCTAssertEqual(FleetFormat.sparklineSeries([nil, nil]), Array(repeating: 0.0, count: 60),
                     "an all-null window is a flat line, not a gap")
    }

    func testSpeedIdleSecMeasuresFromTheLastMeasurement() {
        let lastAt = "2026-10-13T23:41:59.737Z"
        let now = date(lastAt)
        XCTAssertEqual(FleetFormat.speedIdleSec(FleetSpeed(current: nil, lastAt: lastAt), now: now) ?? -1,
                       0, accuracy: 0.001, "the instant of the last measurement is zero seconds idle")
        XCTAssertEqual(
            FleetFormat.speedIdleSec(FleetSpeed(current: nil, lastAt: lastAt), now: now + 31) ?? -1,
            31, accuracy: 0.001)
        XCTAssertNil(FleetFormat.speedIdleSec(FleetSpeed(current: nil, lastAt: nil), now: now),
                     "without a lastAt there is no clock to measure from")
        XCTAssertNil(FleetFormat.speedIdleSec(FleetSpeed(current: nil, lastAt: "not a date"), now: now),
                     "an unparsable lastAt is as good as none")
        XCTAssertNil(FleetFormat.speedIdleSec(nil, now: now), "no speed block, no idle time")
    }

    func testSpeedKeepsLastValueInsideTheGraceAndWithoutAClock() {
        let lastAt = "2026-10-13T23:41:59.737Z"
        let now = date(lastAt)
        XCTAssertTrue(FleetFormat.speedKeepsLastValue(FleetSpeed(current: nil, lastAt: lastAt), now: now),
                      "zero seconds idle is inside the grace")
        XCTAssertTrue(
            FleetFormat.speedKeepsLastValue(FleetSpeed(current: nil, lastAt: lastAt), now: now + 30),
            "the last second of the grace still keeps the value")
        XCTAssertFalse(
            FleetFormat.speedKeepsLastValue(FleetSpeed(current: nil, lastAt: lastAt), now: now + 31),
            "one second past the 30 s grace starts the count at zero")
        // No clock to judge by: the value is kept - without a parsable lastAt there is nothing to
        // time out.
        XCTAssertTrue(FleetFormat.speedKeepsLastValue(FleetSpeed(current: nil, lastAt: nil), now: now))
        XCTAssertTrue(
            FleetFormat.speedKeepsLastValue(FleetSpeed(current: nil, lastAt: "not a date"), now: now))
        XCTAssertTrue(FleetFormat.speedKeepsLastValue(nil, now: now), "no speed block keeps nothing")
        XCTAssertEqual(FleetFormat.speedIdleGraceSec, 30)
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

    // MARK: - Case box: while a tool run is the work

    func testCaseBoxStateNamesTheRunningToolRun() {
        let smoke = run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600)
        let build = run(kind: "build", job: "monitor-platform-split", label: "app", elapsed: 600)
        let other = run(kind: "other", job: "monitor-platform-split", label: "seed.sh", elapsed: 600)
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.idle, toolRuns: [smoke])), "Testing")
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.idle, toolRuns: [build])), "Building")
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.idle, toolRuns: [other])), "Running")
        // Real model work and unreachability outrank a run.
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.busy, jobs: 1, toolRuns: [smoke])), "Working")
        XCTAssertEqual(FleetFormat.caseBoxState(origin(.offline, toolRuns: [smoke])), "Offline")
    }

    func testCaseBoxStateIsActiveForModelWorkOrToolRuns() {
        let smoke = run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600)
        XCTAssertTrue(FleetFormat.caseBoxStateIsActive(origin(.busy, jobs: 2)), "model work is active")
        XCTAssertTrue(FleetFormat.caseBoxStateIsActive(origin(.idle, toolRuns: [smoke])),
                      "a waiting tool run is work the accent should show")
        XCTAssertFalse(FleetFormat.caseBoxStateIsActive(origin(.idle)), "plain idle paints no accent")
        XCTAssertFalse(FleetFormat.caseBoxStateIsActive(origin(.offline, toolRuns: [smoke])),
                       "an unreachable machine is never active, runs or not")
    }

    func testCaseBoxToolRunAgeOnlyUnderARunningState() {
        let smoke = run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600)
        XCTAssertEqual(FleetFormat.caseBoxToolRunAge(origin(.idle, toolRuns: [smoke])), "10m",
                       "the age line under Testing says how long the run has waited")
        XCTAssertNil(FleetFormat.caseBoxToolRunAge(origin(.busy, jobs: 1, toolRuns: [smoke])),
                     "the working box shows its job line, not the run's age")
        XCTAssertNil(FleetFormat.caseBoxToolRunAge(origin(.idle)),
                     "plain idle has no age line")
    }

    /// The closed row's right side is one optional reading: a reported speed or the last value the
    /// API measured wins over everything else; running jobs stand in only while no speed was ever
    /// measured; a fleet that measured nothing gets no reading at all, so the row draws no dash.
    func testClosedRightReadingPrefersTheSpeedThenTheJobCount() throws {
        // A reported speed shows both of its parts, bright, whatever the job count.
        let reported = try XCTUnwrap(
            FleetFormat.closedRightReading(
                speed: FleetSpeed(current: 47.2, lastAt: nil), jobs: 3),
            "a reported speed has a reading")
        XCTAssertEqual(reported.number, "47")
        XCTAssertEqual(reported.unit, " tok/s")
        XCTAssertFalse(reported.dim)

        // No current speed but a last value the API measured, the clock 10 s past the payload's
        // lastAt and so inside the keep-the-last-value grace: the number dims, keeps its value, and
        // its unit says idle in words - the sparkline shows when the fleet last wrote, the unit has
        // to say this number is a remembered one, not a live one. The running job count stays
        // hidden. The numbers are the live activity feed's speed block of 2026-10-14T07:24Z, where
        // lastValue 16.273848069517346 is the speed the API itself last measured (the trend still
        // holds only nulls from the idle window); the clock is fixed, so the wall clock cannot judge
        // the grace.
        // The unit itself comes from the ladder, so the assertion is the suffix, not one rung's
        // spelling (see the ladder test for what the row's budget trims).
        let lastValueIdle = try XCTUnwrap(
            FleetFormat.closedRightReading(
                speed: FleetSpeed(current: nil, lastAt: "2026-10-13T23:41:59.737Z",
                                  trend: Array(repeating: nil, count: 60), stepSec: 10,
                                  lastValue: 16.273848069517346),
                jobs: 1,
                now: date("2026-10-13T23:41:59.737Z") + 10),
            "a last value the API measured is a reading")
        XCTAssertEqual(lastValueIdle.number, "16")
        XCTAssertTrue(lastValueIdle.dim)
        XCTAssertTrue(lastValueIdle.unit.hasSuffix(" · idle"),
                      "a kept value announces itself as remembered, got \(lastValueIdle.unit)")
        // The API's lastValue outranks an older point still sitting in the trend. With no lastAt
        // the row has no clock to judge by, so the value is kept.

        let withLastValue = try XCTUnwrap(
            FleetFormat.closedRightReading(
                speed: FleetSpeed(current: nil, lastAt: nil, trend: [120, 90], stepSec: 10,
                                  lastValue: 16.27),
                jobs: 0),
            "lastValue is a reading")
        XCTAssertEqual(withLastValue.number, "16")
        // The idle tail still fits beside a two-digit number - the pair is 141 pt against the row's
        // 160 pt text budget, so the first ladder rung holds (see the ladder test).
        XCTAssertEqual(withLastValue.unit, " tok/s · idle")
        XCTAssertTrue(withLastValue.dim)
        let trendOnly = try XCTUnwrap(
            FleetFormat.closedRightReading(
                speed: FleetSpeed(current: nil, lastAt: nil, trend: [120, 90], stepSec: 10),
                jobs: 0),
            "the newest non-nil trend point is a reading")
        XCTAssertEqual(trendOnly.number, "90")
        XCTAssertTrue(trendOnly.dim)
    }

    /// Nothing measured, nobody waiting: no reading, so the closed row draws no dash.
    func testClosedRightReadingIsNilWhenNothingWasEverMeasured() {
        XCTAssertNil(FleetFormat.closedRightReading(speed: nil, jobs: 0))
        // A speed block that never held a number is as good as no block at all.
        let neverMeasured = FleetSpeed(current: nil, lastAt: nil, trend: [])
        XCTAssertNil(FleetFormat.closedRightReading(speed: neverMeasured, jobs: 0))
    }

    /// No speed yet while jobs run: their count stands in, bright, as a job count - never a rate.
    func testClosedRightReadingShowsTheJobCountWhileNoSpeedExists() throws {
        let twoJobs = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: nil, jobs: 2),
            "running jobs have a reading")
        XCTAssertEqual(twoJobs.number, "2")
        XCTAssertEqual(twoJobs.unit, " jobs")
        XCTAssertFalse(twoJobs.dim)

        let oneJob = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: nil, jobs: 1),
            "one running job has a reading")
        XCTAssertEqual(oneJob.number, "1")
        XCTAssertEqual(oneJob.unit, " job")
        XCTAssertFalse(oneJob.dim)

        // The count stands in as a job count: it never takes a rate unit off the ladder.
        XCTAssertEqual(FleetFormat.closedRightReading(speed: nil, jobs: 2)?.unit,
                       " jobs")
    }

    /// The dimmed reading keeps its last value for `speedIdleGraceSec` after the last measurement,
    /// then prints 0 - dim either way. Inside the kept window the unit says idle in words; the zero
    /// after it needs no marker, its being zero is the marker. The clock comes from the caller, so
    /// both sides of the boundary sit on fixed instants, never the wall clock.
    func testClosedRightReadingKeepsTheLastValueOnlyInsideTheGrace() throws {
        let lastAt = "2026-10-13T23:41:59.737Z"
        let speed = FleetSpeed(current: nil, lastAt: lastAt,
                               trend: Array(repeating: nil, count: 60), stepSec: 10,
                               lastValue: 16.273848069517346)

        // 10 s after the measurement: inside the grace, so the last value stands, said as a kept one.
        let kept = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: speed, jobs: 0,
                                           now: date(lastAt) + 10),
            "a kept last value is a reading")
        XCTAssertEqual(kept.number, "16")
        XCTAssertTrue(kept.dim)
        XCTAssertTrue(kept.unit.hasSuffix(" · idle"),
                      "inside the grace the kept value says idle, got \(kept.unit)")

        // 31 s after: past the 30 s grace, the row prints 0 - still dim, still a rate unit, and no
        // idle word: a zero already reads as nothing flowing, so marking it idle would only repeat it.
        let zero = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: speed, jobs: 0,
                                           now: date(lastAt) + 31),
            "the zero after the grace is a reading")
        XCTAssertEqual(zero.number, "0")
        XCTAssertTrue(zero.dim)
        XCTAssertTrue(zero.unit.contains("/s"), "the zero keeps a rate unit, got \(zero.unit)")
        XCTAssertFalse(zero.unit.lowercased().contains("idle"),
                       "the zeroed reading never says idle, got \(zero.unit)")
    }

    /// The closed row prints the number at `closedSpeedNumberSize` beside a 24 pt sparkline, so a
    /// long number - or an idle reading with its " · idle" tail - trades its rate words down the
    /// ladder " tok/s" -> " t/s" until the pair fits the row's text budget again. The ladder is two
    /// rungs now, and the closed row no longer says "total" - only the open panel's `tokenRateUnit`
    /// still does. The idle suffix rides on every candidate, so the budget only ever trims the rate
    /// words in front of it; when nothing fits, the shortest candidate wins.
    func testClosedSpeedUnitLadderNarrowsForALongNumber() {
        XCTAssertEqual(FleetFormat.closedSpeedUnit(number: "47"), " tok/s")
        XCTAssertEqual(FleetFormat.closedSpeedUnit(number: "47", idle: true), " tok/s · idle")
        // Ten digits: 24 pt sparkline + 3 + 84 (the digits) + 3 + 39.6 (" tok/s") = 153.6 <= 160, so
        // even the long number still holds the first rung.
        XCTAssertEqual(FleetFormat.closedSpeedUnit(number: "1234567890"), " tok/s")
        // The idle tail is what nothing can hold beside ten digits: " tok/s · idle" needs 199.8 pt,
        // so the pair falls to " t/s" and keeps the " · idle" the kept value announces itself with.
        XCTAssertEqual(FleetFormat.closedSpeedUnit(number: "1234567890", idle: true), " t/s · idle")

        // The fit helper measures the same pair the row renders: the ten-digit number holds
        // " tok/s" (24 + 3 + 84 + 3 + 39.6 = 153.6 <= 160) but not " tok/s · idle" (199.8 > 160).
        // Even the short rung with the idle tail is too wide (186.6 > 160): the ladder hands back
        // " t/s · idle" as its shortest candidate, not as a pair that fits.
        XCTAssertTrue(FleetFormat.closedSpeedFits(number: "47", unit: " tok/s"))
        XCTAssertTrue(FleetFormat.closedSpeedFits(number: "47", unit: " tok/s · idle"))
        XCTAssertTrue(FleetFormat.closedSpeedFits(number: "1234567890", unit: " tok/s"))
        XCTAssertFalse(FleetFormat.closedSpeedFits(number: "1234567890", unit: " tok/s · idle"))
        XCTAssertFalse(FleetFormat.closedSpeedFits(number: "1234567890", unit: " t/s · idle"))
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

    /// The closed notch the job machine's display produces: a 30 pt menu bar. The fleet bar is 70 % of it.
    private let closedNotch: CGFloat = 30
    private var closedBarHeight: CGFloat { FleetPanelMetrics.closedBarHeight(closedNotch) }

    /// The closed row prints its speed number in the skin's accent - the black skin's only green -
    /// while a fleet that never measured anything hands the row no reading, so the row paints no
    /// accent at all and the busy row's green pixels can only come from that number.
    @MainActor
    func testClosedRowDrawsItsSpeedNumberInTheAccentColour() throws {
        // Same font-registration precaution as the case-box test: the rows ask FleetType for the
        // mono face, whose registration is memoised once per process.
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let theme = FleetTheme(skin: .black)
        // The run the TESTING strip shows: the activity feed's shape, one 600 s smoke test.
        let testRun = run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600)
        let speedReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 47.2, lastAt: nil), jobs: 2),
            "a reported speed has a reading")
        // The clock sits 10 s after the payload's lastAt - inside the keep-the-last-value grace -
        // so the idle row keeps 16 and never falls to 0 by the wall clock.
        let lastValueReading = try XCTUnwrap(
            FleetFormat.closedRightReading(
                speed: FleetSpeed(current: nil, lastAt: "2026-10-13T23:41:59.737Z",
                                  trend: Array(repeating: nil, count: 60), stepSec: 10,
                                  lastValue: 16.273848069517346),
                jobs: 1,
                now: date("2026-10-13T23:41:59.737Z") + 10),
            "the last value the API measured is a reading")
        let idleReading = FleetFormat.closedRightReading(speed: nil, jobs: 0,
                                                         now: date("2026-10-13T23:41:59.737Z"))
        XCTAssertNil(idleReading, "an idle fleet with nothing measured draws no number at all")

        func bitmap(for reading: FleetFormat.FleetClosedRightReading?) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: FleetClosedRowView(
                working: 2, alert: nil, reading: reading, theme: theme, gapWidth: 200, height: closedBarHeight
            ).background(Color.black))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "the closed row rendered")
            return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)),
                                 "closed row bitmap")
        }

        XCTAssertGreaterThan(accentPixelCount(try bitmap(for: speedReading), theme: theme), 0,
                             "the speed number draws in the accent")
        XCTAssertEqual(accentPixelCount(try bitmap(for: idleReading), theme: theme), 0,
                       "an idle row with no reading shows no accent at all")

        // The tool-run strip, on its own request:
        // `FLEET_TOOL_RUNS_PREVIEW=/tmp/toolruns.png xcodebuild test`. Two closed rows in the
        // TESTING state (working 0, one 600 s test run, the 60-point null trend the feed ships):
        // the kept reading 10 s after `lastAt` - 16, dim, its unit saying idle - above the idle
        // "0 tok/s" reading past the keep-the-last-value grace, so the committed image shows
        // both states of the right side side by side. Then the case box idle with that same run,
        // and the box busy with it: the idle box shows the run ("Testing" + its age) while the busy
        // box keeps its own "Working" line. Each preview is `if let` rather than
        // `guard … else { return }` so asking for one never skips the other.
        if let toolRunsPath = ProcessInfo.processInfo.environment["FLEET_TOOL_RUNS_PREVIEW"] {
            // 31 s after the same `lastAt` the kept reading above is taken from: past the 30 s
            // grace, so this row shows the zero the kept value falls to.
            let zeroReading = try XCTUnwrap(
                FleetFormat.closedRightReading(
                    speed: FleetSpeed(current: nil, lastAt: "2026-10-13T23:41:59.737Z",
                                      trend: Array(repeating: nil, count: 60), stepSec: 10,
                                      lastValue: 16.273848069517346),
                    jobs: 0,
                    now: date("2026-10-13T23:41:59.737Z") + 31),
                "the idle fleet past the grace still has its reading")
            // 10 s after that same `lastAt`, inside the grace: the remembered 16 with its idle unit.
            // The clock is pinned, so the strip never depends on when the test runs.
            let keptReading = try XCTUnwrap(
                FleetFormat.closedRightReading(
                    speed: FleetSpeed(current: nil, lastAt: "2026-10-13T23:41:59.737Z",
                                      trend: Array(repeating: nil, count: 60), stepSec: 10,
                                      lastValue: 16.273848069517346),
                    jobs: 0,
                    now: date("2026-10-13T23:41:59.737Z") + 10),
                "the fleet inside the grace keeps its reading")
            let toolRunTrend: [Double?] = Array(repeating: nil, count: 60)
            let toolRunStrip = ImageRenderer(content: VStack(spacing: 6) {
                FleetClosedRowView(working: 0, alert: nil, reading: keptReading, theme: theme,
                                   gapWidth: 200, height: closedBarHeight,
                                   toolRuns: [testRun], trend: toolRunTrend)
                FleetClosedRowView(working: 0, alert: nil, reading: zeroReading, theme: theme,
                                   gapWidth: 200, height: closedBarHeight,
                                   toolRuns: [testRun], trend: toolRunTrend)
                HStack(spacing: 20) {
                    FleetCaseBoxView(lane: origin(.idle, toolRuns: [testRun]), theme: theme)
                    FleetCaseBoxView(lane: origin(.busy, jobs: 1, toolRuns: [testRun]), theme: theme)
                }
            }.padding(16).background(Color.black))
            toolRunStrip.scale = 3
            let toolRunStripImage = try XCTUnwrap(toolRunStrip.nsImage, "the tool-run strip rendered")
            let toolRunStripBitmap = try XCTUnwrap(
                NSBitmapImageRep(data: try XCTUnwrap(toolRunStripImage.tiffRepresentation)),
                "tool-run strip bitmap")
            let toolRunPng = try XCTUnwrap(
                toolRunStripBitmap.representation(using: .png, properties: [:]), "tool-run preview PNG")
            XCTAssertNoThrow(try Data(toolRunPng).write(to: URL(fileURLWithPath: toolRunsPath)),
                             "the tool-run preview wrote")
        }

        // A preview strip, only on request: `FLEET_CLOSED_ROW_PREVIEW=/tmp/row.png xcodebuild test`.
        // Its three rows are the closed bar at its new height (`closedBarHeight`, 70 % of the closed
        // notch), each with one reading: the live speed, the kept value and the idle row.
        if let previewPath = ProcessInfo.processInfo.environment["FLEET_CLOSED_ROW_PREVIEW"] {
            let strip = ImageRenderer(content: VStack(spacing: 6) {
                FleetClosedRowView(working: 2, alert: nil, reading: speedReading, theme: theme,
                                   gapWidth: 200, height: closedBarHeight)
                FleetClosedRowView(working: 2, alert: nil, reading: lastValueReading, theme: theme,
                                   gapWidth: 200, height: closedBarHeight)
                FleetClosedRowView(working: 2, alert: nil, reading: idleReading, theme: theme,
                                   gapWidth: 200, height: closedBarHeight)
            }.padding(16).background(Color.black))
            strip.scale = 3
            let stripImage = try XCTUnwrap(strip.nsImage, "the preview strip rendered")
            let stripBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(stripImage.tiffRepresentation)),
                                            "preview strip bitmap")
            let png = try XCTUnwrap(stripBitmap.representation(using: .png, properties: [:]), "preview PNG")
            XCTAssertNoThrow(try Data(png).write(to: URL(fileURLWithPath: previewPath)), "the preview wrote")
        }
    }

    /// The bar is 70 % of the closed notch (owner request: it hung well below the menu bar), and the
    /// rendered row is exactly that tall - the text must fit inside it.
    @MainActor
    func testTheClosedBarIsSeventyPercentOfTheClosedNotch() throws {
        XCTAssertEqual(FleetPanelMetrics.closedBarHeightScale, 0.7, accuracy: 0.0001)
        XCTAssertEqual(FleetPanelMetrics.closedBarHeight(30), 21, accuracy: 0.0001)
        XCTAssertEqual(FleetPanelMetrics.closedBarHeight(38), 26.6, accuracy: 0.0001)
        // the bitmap is the rendered row at scale 2: 42 px for 21 pt
        let speedReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 47.2, lastAt: nil), jobs: 2),
            "a reported speed has a reading")
        XCTAssertEqual(try rowBitmap(working: 2, alert: nil, reading: speedReading, blackHole: false).pixelsHigh,
                       42)
    }

    /// The shorter bar must clip no text: the busy row at `closedBarHeight` puts no ink in its topmost
    /// or bottommost two pixel rows, so the glyphs and the sparkline stay inside the bar.
    @MainActor
    func testTheShorterBarClipsNoTextOrSparkline() throws {
        let speedReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 47.2, lastAt: nil), jobs: 2),
            "a reported speed has a reading")
        let flatTrend: [Double?] = Array(repeating: 0, count: 60)
        let bitmap = try rowBitmap(working: 2, alert: "3 critical", reading: speedReading, blackHole: false,
                                   trend: flatTrend)
        XCTAssertEqual(bitmap.pixelsHigh, 42, "21 pt at scale 2")

        // Ink is any colour channel above 0.05; the black background is 0 in every channel.
        func hasInk(inRows rows: Range<Int>) -> Bool {
            for y in rows {
                for x in 0..<bitmap.pixelsWide {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if pixel.redComponent > 0.05 || pixel.greenComponent > 0.05 || pixel.blueComponent > 0.05 {
                        return true
                    }
                }
            }
            return false
        }
        XCTAssertFalse(hasInk(inRows: 0..<2), "no ink in the topmost two pixel rows")
        XCTAssertFalse(hasInk(inRows: (bitmap.pixelsHigh - 2)..<bitmap.pixelsHigh),
                       "no ink in the bottommost two pixel rows")
    }

    // Content-sized wings keep the closed bar below seventy percent of its previous width.
    @MainActor
    func testTheClosedRowFitsItsContentAndIsUnderSeventyPercentOfTheOldBar() throws {
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let theme = FleetTheme(skin: .black)
        let flat: [Double?] = Array(repeating: 0, count: 60)
        let zeroReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 0, lastAt: nil), jobs: 0))
        let bigReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 147, lastAt: nil), jobs: 0))
        // The bitmap has two wings and two pixels per point.
        let wing = CGFloat(try rowBitmap(working: 0, alert: nil, reading: zeroReading,
                                        blackHole: false, gap: 0, trend: flat).pixelsWide) / 4
        let rightContent = FleetPanelMetrics.closedSparklineWidth + FleetPanelMetrics.closedSpeedSpacing
            + FleetPanelMetrics.closedNumberMinWidth + FleetPanelMetrics.closedSpeedSpacing
            + FleetType.monoWidth(text: " tok/s", size: FleetPanelMetrics.minTextSize)
        XCTAssertEqual(wing, rightContent + FleetPanelMetrics.closedRowSidePadding, accuracy: 0.5)

        // The old sparkline was 40 pt wide and the speed number had no three-digit reserve.
        let oldRightContent: CGFloat = 40 + FleetPanelMetrics.closedSpeedSpacing
            + FleetType.monoWidth(text: "0", size: FleetPanelMetrics.closedSpeedNumberSize, weight: .medium)
            + FleetPanelMetrics.closedSpeedSpacing
            + FleetType.monoWidth(text: " tok/s total", size: FleetPanelMetrics.minTextSize)
        // A display without a hardware notch had a 185 pt closed notch width, and the old code
        // added 5 pt clearance on each side on every display.
        let oldWidth = 2 * min(FleetPanelMetrics.closedRowTextWidth, oldRightContent) + (185 + 10)
        let gap = FleetPanelMetrics.closedRowGap(notchWidth: 185, hasHardwareNotch: false)
        let newWidth = CGFloat(try rowBitmap(working: 0, alert: nil, reading: zeroReading,
                                            blackHole: false, gap: gap, trend: flat).pixelsWide) / 2
        XCTAssertLessThanOrEqual(newWidth, 0.70 * oldWidth,
                                 "The new width \(newWidth) must be at most 70 percent of the old width \(oldWidth).")

        // Request the preview with `TEST_RUNNER_FLEET_CLOSED_WIDTH_PREVIEW=/tmp/width.png xcodebuild test`.
        if let previewPath = ProcessInfo.processInfo.environment["FLEET_CLOSED_WIDTH_PREVIEW"] {
            let renderer = ImageRenderer(content: VStack(spacing: 6) {
                FleetClosedRowView(working: 0, alert: nil, reading: zeroReading, theme: theme,
                                   gapWidth: gap, height: closedBarHeight, trend: flat)
                FleetClosedRowView(working: 12, alert: nil, reading: bigReading, theme: theme,
                                   gapWidth: gap, height: closedBarHeight, trend: flat)
                FleetClosedRowView(working: 2, alert: "3 critical", reading: zeroReading, theme: theme,
                                   gapWidth: gap, height: closedBarHeight, trend: flat)
            }.padding(.horizontal, 14).padding(.vertical, 6).background(Color.black))
            renderer.scale = 3
            XCTAssertNotNil(renderer.nsImage, "The closed-width preview rendered.")
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertNoThrow(try Data(png).write(to: URL(fileURLWithPath: previewPath)),
                             "The closed-width preview wrote.")
        }
    }

    // Equal wings keep the middle centred even when the working count changes.
    @MainActor
    func testTheClosedRowWingsAreEqualSoTheMiddleStaysCentred() throws {
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let flat: [Double?] = Array(repeating: 0, count: 60)
        let zeroReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 0, lastAt: nil), jobs: 0))
        let rightContent = FleetPanelMetrics.closedSparklineWidth + FleetPanelMetrics.closedSpeedSpacing
            + FleetPanelMetrics.closedNumberMinWidth + FleetPanelMetrics.closedSpeedSpacing
            + FleetType.monoWidth(text: " tok/s", size: FleetPanelMetrics.minTextSize)
        let wing = FleetPanelMetrics.closedRowSide(left: 0, right: rightContent,
                                                    padding: FleetPanelMetrics.closedRowSidePadding)
        let gap = FleetPanelMetrics.closedRowGap(notchWidth: 185, hasHardwareNotch: false)
        let bitmap = try rowBitmap(working: 0, alert: nil, reading: zeroReading,
                                   blackHole: false, gap: gap, trend: flat)
        let busyBitmap = try rowBitmap(working: 12, alert: nil, reading: zeroReading,
                                       blackHole: false, gap: gap, trend: flat)
        let scale: CGFloat = 2
        XCTAssertEqual(CGFloat(bitmap.pixelsWide) / scale, CGFloat(busyBitmap.pixelsWide) / scale, accuracy: 0.5)
        // The render snaps to the half-point pixel grid, and SwiftUI's text measurement can sit a
        // fraction from NSFont's, so the rendered width is the metric's arithmetic rounded to that
        // grid (305.5 rendered against 304.8 from the metrics at scale 2).
        XCTAssertEqual(CGFloat(bitmap.pixelsWide) / scale, 2 * wing + gap, accuracy: 1.0)

        // Ink is any sRGB channel above 0.05 against the black background.
        func hasInk(inColumn x: Int) -> Bool {
            for y in 0..<bitmap.pixelsHigh {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if pixel.redComponent > 0.05 || pixel.greenComponent > 0.05 || pixel.blueComponent > 0.05 {
                    return true
                }
            }
            return false
        }
        let lastLeftInk = try XCTUnwrap((0..<Int(ceil(wing * scale))).last(where: hasInk))
        let firstRightInk = try XCTUnwrap(
            (Int(ceil((wing + gap) * scale))..<bitmap.pixelsWide).first(where: hasInk))
        XCTAssertEqual(CGFloat(lastLeftInk) / scale, wing, accuracy: 2)
        XCTAssertEqual(CGFloat(firstRightInk) / scale, wing + gap, accuracy: 2)
    }

    // Reserving three digits keeps the bar still while the rate changes from zero to 147.
    @MainActor
    func testTheClosedSpeedNumberKeepsThreeDigits() throws {
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let flat: [Double?] = Array(repeating: 0, count: 60)
        let zeroReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 0, lastAt: nil), jobs: 0))
        let bigReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 147, lastAt: nil), jobs: 0))
        let gap = FleetPanelMetrics.closedRowGap(notchWidth: 185, hasHardwareNotch: false)
        let zeroWidth = CGFloat(try rowBitmap(working: 0, alert: nil, reading: zeroReading,
                                             blackHole: false, gap: gap, trend: flat).pixelsWide) / 2
        let bigWidth = CGFloat(try rowBitmap(working: 0, alert: nil, reading: bigReading,
                                            blackHole: false, gap: gap, trend: flat).pixelsWide) / 2
        XCTAssertEqual(zeroWidth, bigWidth, accuracy: 0.5)
    }

    /// The closed row animates its whole width on one key. Four digits pass the three-digit reserve and
    /// really widen the bar, so that change must move the bar, while the reserve still holds 0 -> 147.
    @MainActor
    func testTheClosedRowWidthAnimationCoversEveryContentChange() throws {
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let theme = FleetTheme(skin: .black)
        let flat: [Double?] = Array(repeating: 0, count: 60)
        let gap = FleetPanelMetrics.closedRowGap(notchWidth: 185, hasHardwareNotch: false)
        let zeroReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 0, lastAt: nil), jobs: 0))
        let oneFortySevenReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 147, lastAt: nil), jobs: 0))
        let ninetyNineNineReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 999, lastAt: nil), jobs: 0))
        let thousandReading = try XCTUnwrap(
            FleetFormat.closedRightReading(speed: FleetSpeed(current: 1000, lastAt: nil), jobs: 0))

        // The bar's width in points: the bitmap has two pixels per point.
        func width(_ reading: FleetFormat.FleetClosedRightReading) throws -> CGFloat {
            CGFloat(try rowBitmap(working: 0, alert: nil, reading: reading, blackHole: false,
                                  gap: 2 * FleetPanelMetrics.closedRowSidePadding, trend: flat).pixelsWide) / 2
        }

        // The row is two wings, and both wings are as wide as the wider side, so each digit the number
        // grows past the reserve moves the bar twice: once per wing.
        let thousandWidth = try width(thousandReading)
        let ninetyNineNineWidth = try width(ninetyNineNineReading)
        let extraDigitWidth = FleetType.monoWidth(text: "1000", size: FleetPanelMetrics.closedSpeedNumberSize,
                                                  weight: .medium) - FleetPanelMetrics.closedNumberMinWidth
        XCTAssertEqual(thousandWidth - ninetyNineNineWidth, 2 * extraDigitWidth, accuracy: 1.0,
                       "999 -> 1000 moves the bar by two extra digit widths, one per wing")

        // A rate inside the three-digit reserve does not move the bar, so the animation has nothing to cover there.
        let zeroWidth = try width(zeroReading)
        let oneFortySevenWidth = try width(oneFortySevenReading)
        XCTAssertEqual(zeroWidth, oneFortySevenWidth, accuracy: 0.5,
                       "0 -> 147 stays inside the three-digit reserve and does not move the bar")

        // The animation watches `widthKey`, so the key must change whenever any input the width comes from changes.
        func makeRow(working: Int, alert: String?, reading: FleetFormat.FleetClosedRightReading?,
                     toolRuns: [ToolRun], blackHole: FleetBlackHoleState) -> FleetClosedRowView {
            FleetClosedRowView(working: working, alert: alert, reading: reading, theme: theme,
                               gapWidth: gap, height: closedBarHeight, toolRuns: toolRuns, trend: flat,
                               blackHole: blackHole)
        }
        let baseRow = makeRow(working: 0, alert: nil, reading: zeroReading, toolRuns: [], blackHole: .hidden)
        XCTAssertEqual(baseRow.widthKey,
                       makeRow(working: 0, alert: nil, reading: zeroReading, toolRuns: [], blackHole: .hidden).widthKey,
                       "two identical rows share one width key")
        XCTAssertNotEqual(baseRow.widthKey,
                          makeRow(working: 0, alert: nil, reading: thousandReading, toolRuns: [], blackHole: .hidden).widthKey,
                          "the reading crossing the three-digit reserve changes the width key")
        XCTAssertNotEqual(baseRow.widthKey,
                          makeRow(working: 12, alert: nil, reading: zeroReading, toolRuns: [], blackHole: .hidden).widthKey,
                          "the working count changes the width key")
        XCTAssertNotEqual(baseRow.widthKey,
                          makeRow(working: 0, alert: "3 critical", reading: zeroReading, toolRuns: [], blackHole: .hidden).widthKey,
                          "the alert changes the width key")
        XCTAssertNotEqual(baseRow.widthKey,
                          makeRow(working: 0, alert: nil, reading: zeroReading,
                                  toolRuns: [run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600)],
                                  blackHole: .hidden).widthKey,
                          "the working count's tool runs change the width key")
        XCTAssertNotEqual(baseRow.widthKey,
                          makeRow(working: 0, alert: nil, reading: zeroReading, toolRuns: [],
                                  blackHole: FleetBlackHoleState(working: 4, isVisible: true)).widthKey,
                          "the black hole changes the width key")
    }

    /// The closed row at `closedBarHeight` on black, at scale 2: the frame the closed bar draws in.
    @MainActor
    private func rowBitmap(working: Int, alert: String?, reading: FleetFormat.FleetClosedRightReading?,
                           blackHole: Bool, gap: CGFloat = 200, trend: [Double?]? = nil) throws -> NSBitmapImageRep {
        // The rows ask FleetType for the mono face, whose registration is memoised once per process.
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let renderer = ImageRenderer(content: FleetClosedRowView(
            working: working, alert: alert, reading: reading, theme: FleetTheme(skin: .black),
            gapWidth: gap, height: closedBarHeight, trend: trend,
            blackHole: blackHole ? FleetBlackHoleState(working: working, isVisible: true) : .hidden
        ).background(Color.black))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "the closed row rendered")
        return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)),
                             "closed row bitmap")
    }

    /// The CURRENT WORK column is the only place a waiting run's full command appears, so a leaf
    /// view that painted nothing while runs existed would be indistinguishable from an empty fleet -
    /// every formatter could stay right and the panel would still show Case doing nothing. Rendering
    /// the view with two runs and with none, and counting the lit pixels both times, tells those
    /// apart: the lines are there when the fleet has work, and the empty state really is blank.
    /// Judged on luminance, not colour: the lines draw in `theme.dim`, so no accent is involved.
    @MainActor
    func testToolRunLinesDrawTheRunsAndNothingWithoutThem() throws {
        // The run lines ask FleetType for the mono face, whose registration is memoised once per
        // process. Register the test bundle's own faces first: without this the render would pin
        // the system fallback for every later test, and FleetTypeTests would fail on our account.
        FleetType.registerBundledFonts(in: Bundle(for: FleetFormatTests.self))
        let theme = FleetTheme(skin: .black)
        // Two runs the activity feed reports: a 10 m smoke test and a 3 m build, each with the job
        // and label the formatter puts on its line.
        let runs = [
            run(kind: "test", job: "monitor-platform-split", label: "smoke.cjs", elapsed: 600),
            run(kind: "build", job: "boring-notch", label: "boringNotch", elapsed: 180),
        ]

        // The column's own width and the two 16 pt rows two runs take, on the black background:
        // anything lit inside this box is the view's own doing, so a view that stopped drawing its
        // lines would leave the box as empty as the no-runs render.
        func linesBitmap(_ runList: [ToolRun]) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: FleetToolRunLines(runs: runList, theme: theme)
                .frame(width: FleetPanelMetrics.workColumnWidth,
                       height: 2 * FleetPanelMetrics.caseJobLineHeight)
                .background(Color.black))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.nsImage, "the tool-run lines rendered")
            return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)),
                                 "tool-run lines bitmap")
        }

        XCTAssertGreaterThan(litPixelCount(try linesBitmap(runs)), 0,
                             "two runs draw their lines")
        XCTAssertEqual(litPixelCount(try linesBitmap([])), 0,
                       "no runs draw no lines at all")

        // A preview strip, only on request:
        // `TEST_RUNNER_FLEET_TOOL_RUNS_LINES_PREVIEW=/tmp/runlines.png xcodebuild test`. The two
        // runs above the empty column, so the blank state can be seen next to the painted one.
        // `if let` rather than `guard … else { return }`, as in this file's other previews.
        if let previewPath = ProcessInfo.processInfo.environment["FLEET_TOOL_RUNS_LINES_PREVIEW"] {
            let strip = ImageRenderer(content: VStack(spacing: 12) {
                FleetToolRunLines(runs: runs, theme: theme)
                    .frame(width: FleetPanelMetrics.workColumnWidth,
                           height: 2 * FleetPanelMetrics.caseJobLineHeight)
                FleetToolRunLines(runs: [], theme: theme)
                    .frame(width: FleetPanelMetrics.workColumnWidth,
                           height: 2 * FleetPanelMetrics.caseJobLineHeight)
            }.padding(16).background(Color.black))
            strip.scale = 3
            let stripImage = try XCTUnwrap(strip.nsImage, "the preview strip rendered")
            let stripBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(stripImage.tiffRepresentation)),
                                            "preview strip bitmap")
            let png = try XCTUnwrap(stripBitmap.representation(using: .png, properties: [:]), "preview PNG")
            XCTAssertNoThrow(try Data(png).write(to: URL(fileURLWithPath: previewPath)), "the preview wrote")
        }
    }

    /// Pixels lit above the black background: Rec.709 luminance over 0.15. The black skin's run
    /// line (`dim`, 0x939A87) measures 0.59, and the background it sits on - `Color.black` under the
    /// box - 0.00, so this counts the glyphs and their antialiasing and nothing else.
    private func litPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent
                    + 0.0722 * pixel.blueComponent
                if luminance > 0.15 { count += 1 }
            }
        }
        return count
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
