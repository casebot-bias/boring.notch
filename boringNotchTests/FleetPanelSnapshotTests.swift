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
//  for the FLEET tab and `FLEET_PANEL_DECISIONS_PREVIEW` for the DECISIONS tab. xcodebuild
//  only forwards `TEST_RUNNER_`-prefixed names into the test process, so the invocation is
//  env TEST_RUNNER_FLEET_PANEL_FLEET_PREVIEW=<path> TEST_RUNNER_FLEET_PANEL_DECISIONS_PREVIEW=<path> xcodebuild test -project boringNotch.xcodeproj -scheme boringNotchTests -destination 'platform=macOS,arch=arm64'
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

    /// Pixels with any channel above 0.12: what proves the panel drew something.
    private func litPixels(_ rep: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(c.redComponent, c.greenComponent, c.blueComponent) > 0.12 { count += 1 }
            }
        }
        return count
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

    // MARK: - Test

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
}
