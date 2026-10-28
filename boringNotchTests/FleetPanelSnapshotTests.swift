//
//  FleetPanelSnapshotTests.swift
//  boringNotchTests
//
//  The opened notch's Fleet column drawn from the committed fixtures: the one-line header,
//  the FLEET / DECISIONS tab strip, then the tab itself. `ImageRenderer` draws a SwiftUI
//  ScrollView blank and the DECISIONS tab contains one, so the panel is hosted in an
//  `NSHostingView` inside a borderless `NSWindow` (`orderFrontRegardless()`, the run loop
//  drained for 0.6 s) and rasterised with `cacheDisplay` into a 2x `NSBitmapImageRep`.
//  Both tabs draw the same fixed model, so the two images differ only by the tab.
//
//  The proof PNGs are written only when an env var names a path: `FLEET_PANEL_FLEET_PREVIEW`
//  for the FLEET tab and `FLEET_PANEL_DECISIONS_PREVIEW` for the DECISIONS tab; the work-column
//  shots add `FLEET_WORK_OVERFLOW_PREVIEW` and `FLEET_WORK_STRESS_PREVIEW`. xcodebuild
//  only forwards `TEST_RUNNER_`-prefixed names into the test process, so the invocation is
//  env TEST_RUNNER_FLEET_PANEL_FLEET_PREVIEW=<path> TEST_RUNNER_FLEET_PANEL_DECISIONS_PREVIEW=<path> TEST_RUNNER_FLEET_WORK_OVERFLOW_PREVIEW=<path> TEST_RUNNER_FLEET_WORK_STRESS_PREVIEW=<path> xcodebuild test -project boringNotch.xcodeproj -scheme boringNotchTests -destination 'platform=macOS,arch=arm64'
//  Without either var nothing is written and nothing fails.
//

import XCTest
import SwiftUI
import AppKit

/// The panel under test: one tab of the fixed model, over black, at the panel's own 604 x 300.
private struct PanelFixture: View {
    let initialTab: FleetPanelTab
    let model: FleetPanelModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            FleetSectionView(initialTab: initialTab, previewModel: model)
                .frame(width: 604, height: 300, alignment: .topLeading)
        }
        .frame(width: 604, height: 300)
    }
}

/// Thrown when the built model carries no odin lane; the XCTFail at the throw site names the cause.
private enum FleetPanelSnapshotError: Error {
    case missingOdinLane
}

final class FleetPanelSnapshotTests: XCTestCase {

    /// The panel's own size: `fleetSectionWidth` x `FleetPanelMetrics.fleetSectionHeight`.
    private static let panelSize = CGSize(width: 604, height: 300)

    // MARK: - Model

    /// The one model both tabs draw: the committed fixtures plus two Case jobs and Odin's open decision.
    @MainActor private func panelModel() throws -> FleetPanelModel {
        let fleet = try FleetSnapshot.decode(try XCTUnwrap(fixture("fleet")))
        let activity = try ActivitySnapshot.decode(try XCTUnwrap(fixture("activity")))
        let jobs = CaseJobsSnapshot(jobs: [
            CaseJob(job: "notch-fleet-smaller-fonts", running: true, itemsPassed: 2, itemsTotal: 5,
                    minutesSinceCommit: 12),
            CaseJob(job: "odin-pane-fixture", running: true, itemsPassed: 1, itemsTotal: 4,
                    minutesSinceCommit: 65),
        ])
        var model = FleetPanelModelBuilder.build(fleet: fleet, activity: activity, fleetLive: true, caseJobs: jobs)
        // One open decision on Odin's lane: the DECISIONS tab's content, and the FLEET tab's chip.
        guard let odin = model.agents.firstIndex(where: { $0.id == "odin" }) else {
            XCTFail("the built model has no odin lane to carry a decision")
            throw FleetPanelSnapshotError.missingOdinLane
        }
        model.agents[odin].decisions = [FleetDecision(
            job: "notch-fleet-smaller-fonts",
            repo: "case/bot-bias/boring.notch",
            pr: 32,
            reason: "round_limit",
            round: 2,
            found: ["f1: the Fleet panel's text is crowded.",
                    "f2: the DECISIONS tab reads tight.",
                    "f3: the footer rings sit close to their labels."],
            question: "Is every Fleet panel text a little smaller, with the same layout, colours and words?",
            options: OdinOption.defaults)]
        return model
    }

    /// The owner's screenshot, as a model: two Case heartbeats, four waiting test runs, and four
    /// running jobs (the case lane plus the first three agents), so the work column's lines push
    /// the footer down. Derived from `panelModel()`, keeping the map, speed and host readings.
    @MainActor private func overflowModel() throws -> FleetPanelModel {
        var model = try panelModel()
        model.caseJobs = [
            CaseJob(job: "visage-onb2-wiring", running: true, itemsPassed: 4, itemsTotal: 6,
                    minutesSinceCommit: 11),
            CaseJob(job: "visage-onb2-save-home", running: true, itemsPassed: 6, itemsTotal: 6,
                    minutesSinceCommit: 14),
        ]
        model.origin.toolRuns = [
            ToolRun(job: "visage-onb2-wiring", kind: "test", label: "node", pid: 101, since: nil, elapsedSec: 7620),
            ToolRun(job: "visage-onb2-wiring", kind: "test", label: "node", pid: 102, since: nil, elapsedSec: 7500),
            ToolRun(job: "visage-onb2-save-home", kind: "test", label: "node", pid: 103, since: nil, elapsedSec: 420),
            ToolRun(job: "visage-onb2-save-home", kind: "test", label: "node", pid: 104, since: nil, elapsedSec: 400),
        ]
        // Four running jobs: the case lane's own, plus one on each of the first three agents.
        model.origin.state = .busy
        model.origin.jobs = [FleetJob(key: "overflow-case", pill: "case",
                                      label: "notch-fleet-smaller-fonts",
                                      step: "Checking the work column", elapsedSec: 300)]
        for index in model.agents.indices.prefix(3) {
            let id = model.agents[index].id
            model.agents[index].state = .busy
            model.agents[index].jobs = [FleetJob(key: "overflow-agent-\(id)", pill: id,
                                                 label: "visage-onb2-wiring",
                                                 step: "Running tests", elapsedSec: 120)]
        }
        XCTAssertEqual(model.runningTaskCount, 4, "the overflow fixture has four running jobs")
        XCTAssertEqual(model.nowJobs.count, 4, "and four jobs in the preview list")
        return model
    }

    /// The same two heartbeats and four busy lanes, with eight waiting runs over four jobs: the
    /// stress variant, one run line per job on top of the overflow shot.
    @MainActor private func stressModel() throws -> FleetPanelModel {
        var model = try overflowModel()
        model.origin.toolRuns = [
            ToolRun(job: "visage-onb2-wiring", kind: "test", label: "node", pid: 201, since: nil, elapsedSec: 7620),
            ToolRun(job: "visage-onb2-wiring", kind: "test", label: "node", pid: 202, since: nil, elapsedSec: 7500),
            ToolRun(job: "visage-onb2-save-home", kind: "test", label: "node", pid: 203, since: nil, elapsedSec: 420),
            ToolRun(job: "visage-onb2-save-home", kind: "test", label: "node", pid: 204, since: nil, elapsedSec: 400),
            ToolRun(job: "notch-fleet-smaller-fonts", kind: "test", label: "node", pid: 205, since: nil, elapsedSec: 900),
            ToolRun(job: "notch-fleet-smaller-fonts", kind: "test", label: "node", pid: 206, since: nil, elapsedSec: 880),
            ToolRun(job: "odin-pane-fixture", kind: "test", label: "node", pid: 207, since: nil, elapsedSec: 60),
            ToolRun(job: "odin-pane-fixture", kind: "test", label: "node", pid: 208, since: nil, elapsedSec: 50),
        ]
        return model
    }

    // MARK: - Render harness (the OdinDecisionPaneTests window + pump + cacheDisplay pattern)

    /// Drains the run loop, so the hosting view lays out and draws before it is rasterised.
    @MainActor private func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        } while Date() < end
    }

    /// Hosts one tab in a borderless window of the panel's own size and lets it draw.
    @MainActor private func host(_ initialTab: FleetPanelTab, _ model: FleetPanelModel) -> (NSHostingView<PanelFixture>, NSWindow) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: PanelFixture(initialTab: initialTab, model: model))
        view.frame = NSRect(origin: .zero, size: Self.panelSize)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        pump(0.6)
        return (view, window)
    }

    /// The hosted view at 2x: `cacheDisplay` paints what the live window paints, ScrollViews included.
    @MainActor private func raster(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * 2,
            pixelsHigh: Int(view.bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    // MARK: - Proof

    /// Writes the bitmap to the path `name` (or `TEST_RUNNER_\(name)`) holds; no var, no file.
    private func writePreview(_ rep: NSBitmapImageRep, env name: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[name] ?? environment["TEST_RUNNER_\(name)"] else { return }
        XCTAssertNoThrow(try XCTUnwrap(rep.representation(using: .png, properties: [:]), "the PNG representation")
                             .write(to: URL(fileURLWithPath: path)),
                         "the \(name) proof PNG is writable at \(path)", file: file, line: line)
    }

    /// Pixels with any channel above 0.12 in the given pixel rows, all columns: what proves the
    /// panel drew something, and what the footer and bottom-edge checks count.
    private func litPixels(_ rep: NSBitmapImageRep, rows: Range<Int>) -> Int {
        var count = 0
        for y in rows {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(c.redComponent, c.greenComponent, c.blueComponent) > 0.12 { count += 1 }
            }
        }
        return count
    }

    /// Pixels with any channel above 0.12 over the whole bitmap.
    private func litPixels(_ rep: NSBitmapImageRep) -> Int {
        litPixels(rep, rows: 0..<rep.pixelsHigh)
    }

    /// The rows in `rows` that carry a real mark: at least `minimum` lit pixels, which a glyph, a ring
    /// arc or a rule reaches and an antialiased stray pixel does not.
    private func rowsWithInk(_ rep: NSBitmapImageRep, rows: Range<Int>, atLeast minimum: Int) -> [Int] {
        rows.filter { litPixels(rep, rows: $0..<($0 + 1)) >= minimum }
    }

    // MARK: - Fixtures (the FleetDecodingTests loader)

    /// Loads a bundled fixture, trying the `Fixtures` subdirectory first and the
    /// bundle root second. Fails the test (without crashing) when neither is found.
    private func fixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data? {
        let bundle = Bundle(for: Self.self)
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

    // MARK: - Tests

    @MainActor func testRendersTheFleetAndDecisionsTabs() throws {
        XCTAssertTrue(FleetType.registerBundledFonts(in: Bundle(for: Self.self)),
                      "the test bundle ships the three JetBrains Mono faces")
        let model = try panelModel()

        for (tab, envName) in [(FleetPanelTab.fleet, "FLEET_PANEL_FLEET_PREVIEW"),
                               (.odin, "FLEET_PANEL_DECISIONS_PREVIEW")] {
            let (view, window) = host(tab, model)
            defer { window.close() }
            let rep = try raster(view)
            XCTAssertEqual(rep.pixelsWide, 1208, "\(envName): 604 pt at 2x")
            XCTAssertGreaterThanOrEqual(litPixels(rep), 2000,
                                        "\(envName): the panel drew content, not a blank bitmap")
            writePreview(rep, env: envName)
        }
    }

    /// The FLEET tab drawn with a work column full of lines: the owner's overflow shot and its
    /// eight-run stress variant. Each must fit the column's height budget and keep the gauge row
    /// inside the panel.
    @MainActor func testRendersTheWorkColumnStates() throws {
        XCTAssertTrue(FleetType.registerBundledFonts(in: Bundle(for: Self.self)),
                      "the test bundle ships the three JetBrains Mono faces")
        let cases: [(model: FleetPanelModel, envName: String)] = [
            (try overflowModel(), "FLEET_WORK_OVERFLOW_PREVIEW"),
            (try stressModel(), "FLEET_WORK_STRESS_PREVIEW"),
        ]
        for (model, envName) in cases {
            let (view, window) = host(.fleet, model)
            defer { window.close() }
            let rep = try raster(view)
            XCTAssertEqual(rep.pixelsWide, 1208, "\(envName): 604 pt at 2x")
            XCTAssertEqual(rep.pixelsHigh, 600, "\(envName): 300 pt at 2x")
            XCTAssertGreaterThanOrEqual(litPixels(rep), 2000,
                                        "\(envName): the panel drew content, not a blank bitmap")
            let plan = FleetPanelMetrics.workPlan(caseJobs: model.runningCaseJobs, toolRuns: model.toolRuns,
                                                  jobs: model.nowJobs, runningTaskCount: model.runningTaskCount)
            XCTAssertLessThanOrEqual(plan.height, FleetPanelMetrics.workColumnHeight,
                                     "\(envName): the work plan is \(plan.height) pt, over the \(FleetPanelMetrics.workColumnHeight) pt column")
            // The gauge row sits in the footer band; its own last glyph row ends at 592, so nothing may
            // draw in the panel's last 2 pt (rows 596..<600 at 2x). The clipped "before" render has a
            // 380-430 pixel mark on each of those rows (glyphs running off the edge); a row that fits
            // carries at most a stray antialiased pair.
            let footer = litPixels(rep, rows: 520..<592)
            let clipped = rowsWithInk(rep, rows: 596..<600, atLeast: 20)
            print("\(envName): plan height \(plan.height) pt, footer lit \(footer), ink rows at the edge \(clipped)")
            XCTAssertTrue(clipped.isEmpty, "\(envName): rows \(clipped) still carry ink at the panel's bottom 4 pt, so the gauge row is clipped")
            XCTAssertGreaterThanOrEqual(footer, 400, "\(envName): the footer band has fewer than 400 lit pixels, so the gauge row did not draw")
            writePreview(rep, env: envName)
        }
    }
}
