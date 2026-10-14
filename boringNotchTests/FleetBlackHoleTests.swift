import XCTest
import AppKit
import SwiftUI

/// The black hole the closed row shows while the fleet works: its fall model, the scalars that
/// scale with the fleet, the visibility rule, and the pixels the row reserves for the disc.
final class FleetBlackHoleTests: XCTestCase {

    /// A particle falls inward and never back out: the radius strictly shrinks across the disc and
    /// clamps at the core, and a completed fall respawns whole at the edge on a golden-angle slice.
    func testParticleStepShrinksTheRadiusAndRespawnsAtTheEdge() {
        let size = FleetBlackHoleMetrics.size
        let edge = FleetBlackHoleModel.radius(phase: 0, size: size)
        let core = FleetBlackHoleModel.radius(phase: 1, size: size)
        XCTAssertGreaterThan(edge, core, "the disc's outer edge sits outside the core")
        let stops = [0.0, 0.25, 0.5, 0.75, 1.0]
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertGreaterThan(FleetBlackHoleModel.radius(phase: a, size: size),
                                 FleetBlackHoleModel.radius(phase: b, size: size),
                                 "the radius falls between phase \(a) and \(b)")
        }
        XCTAssertEqual(FleetBlackHoleModel.radius(phase: 2, size: size), core,
                       "past the core the phase clamps instead of overshooting")

        let start = FleetBlackHoleParticle(phase: 0, angle: 0, fallRate: 1)
        let first = FleetBlackHoleModel.step(start, dt: 0.1, spin: 1)
        XCTAssertGreaterThan(first.phase, start.phase, "a step advances the fall")
        XCTAssertLessThan(FleetBlackHoleModel.radius(phase: first.phase, size: size), edge,
                          "and the radius falls with it")

        // Run the clock until it wraps: every step before the wrap is a plain advance, and the
        // wrap is a clean respawn at the edge on the next golden angle - never a partial wrap.
        var particle = start
        var wrapped = false
        for _ in 0..<200 {
            let next = FleetBlackHoleModel.step(particle, dt: 0.1, spin: 1)
            if wrapped { break }
            if next.phase < particle.phase {
                wrapped = true
                XCTAssertEqual(next.phase, 0, accuracy: 1e-12, "the wrap is a respawn, not a partial wrap")
                XCTAssertEqual(FleetBlackHoleModel.radius(phase: next.phase, size: size), edge,
                               accuracy: 1e-9, "the respawned particle is back at the edge")
                XCTAssertEqual(next.angle,
                               FleetBlackHoleModel.fract(0 + FleetBlackHoleModel.respawnAngle),
                               accuracy: 1e-9, "the respawn lands on the next golden angle")
            } else {
                XCTAssertGreaterThan(next.phase, particle.phase, "the fall keeps advancing")
                XCTAssertEqual(next.angle, particle.angle, accuracy: 1e-12,
                               "only the spin moves the angle, never the fall")
            }
            particle = next
        }
        XCTAssertTrue(wrapped, "a 2.6 s fall completes inside 200 steps of 0.1 s")
    }

    /// More workers spin the hole faster, thicker and brighter, each on its own plateau.
    func testSpinAndParticleCountScaleWithTheFleetAndCap() {
        XCTAssertEqual(FleetBlackHoleMetrics.spin(working: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(FleetBlackHoleMetrics.spin(working: 4), 1.6, accuracy: 1e-12)
        XCTAssertEqual(FleetBlackHoleMetrics.spin(working: 10), FleetBlackHoleMetrics.maxSpin,
                       accuracy: 1e-12)
        XCTAssertEqual(FleetBlackHoleMetrics.spin(working: 0), 1, accuracy: 1e-12,
                       "an idle fleet still spins the calm disc")
        var previousSpin = FleetBlackHoleMetrics.spin(working: 0)
        for working in 1...14 {
            let spin = FleetBlackHoleMetrics.spin(working: working)
            XCTAssertLessThanOrEqual(spin, FleetBlackHoleMetrics.maxSpin, "spin caps at maxSpin")
            XCTAssertGreaterThanOrEqual(spin, previousSpin, "spin never falls as the fleet grows")
            previousSpin = spin
        }

        XCTAssertEqual(FleetBlackHoleMetrics.particleCount(working: 1),
                       FleetBlackHoleMetrics.minParticles)
        XCTAssertEqual(FleetBlackHoleMetrics.particleCount(working: 4), 9)
        XCTAssertEqual(FleetBlackHoleMetrics.particleCount(working: 10),
                       FleetBlackHoleMetrics.maxParticles)
        XCTAssertEqual(FleetBlackHoleMetrics.particleCount(working: 0),
                       FleetBlackHoleMetrics.minParticles, "an idle fleet still trails the minimum")
        var previousCount = FleetBlackHoleMetrics.particleCount(working: 0)
        for working in 1...14 {
            let count = FleetBlackHoleMetrics.particleCount(working: working)
            XCTAssertLessThanOrEqual(count, FleetBlackHoleMetrics.maxParticles, "the field caps")
            XCTAssertGreaterThanOrEqual(count, previousCount, "the field never thins")
            previousCount = count
        }

        XCTAssertEqual(FleetBlackHoleMetrics.brightness(working: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(FleetBlackHoleMetrics.brightness(working: 4), 1.15, accuracy: 1e-12)
        XCTAssertEqual(FleetBlackHoleMetrics.brightness(working: 10), 1.25, accuracy: 1e-12)
        var previousBrightness = FleetBlackHoleMetrics.brightness(working: 0)
        for working in 1...14 {
            let brightness = FleetBlackHoleMetrics.brightness(working: working)
            XCTAssertLessThanOrEqual(brightness, 1.25, "brightness caps at the saturated ceiling")
            XCTAssertGreaterThanOrEqual(brightness, previousBrightness, "the hole never dims as work grows")
            previousBrightness = brightness
        }
    }

    /// The hole shows while anything works, and while only a run the case itself started is alive.
    func testVisibilityRuleFollowsWorkingCountAndToolRuns() {
        XCTAssertEqual(FleetBlackHoleState.resolve(working: 0, toolRuns: []), FleetBlackHoleState.hidden)
        let testRun = ToolRun(job: "case", kind: "test", label: nil, pid: nil, since: nil, elapsedSec: 600)
        let running = FleetBlackHoleState.resolve(working: 0, toolRuns: [testRun])
        XCTAssertTrue(running.isVisible, "the case's own test run keeps the hole alive")
        XCTAssertEqual(running.working, 0, "a test run is not a working item")
        let working = FleetBlackHoleState.resolve(working: 2, toolRuns: [])
        XCTAssertTrue(working.isVisible)
        XCTAssertEqual(working.working, 2)
        let nonsense = FleetBlackHoleState.resolve(working: -1, toolRuns: [])
        XCTAssertFalse(nonsense.isVisible, "a negative count is never work")
        XCTAssertEqual(nonsense.working, 0, "and it clamps to zero rather than leaking through")
    }

    /// The row makes room for the hole only while work runs: shown, it is wider by exactly the
    /// 18 pt disc plus its 6 pt gap, and it paints warm pixels the idle row cannot produce.
    @MainActor
    func testTheRowReservesTheHoleOnlyWhileWorkRuns() throws {
        // The row asks FleetType for the mono face, whose registration is memoised per process;
        // claim the test bundle's own faces before any other render test pins the fallback.
        FleetType.registerBundledFonts(in: Bundle(for: FleetBlackHoleTests.self))
        let theme = FleetTheme(skin: .black)
        let shown = FleetBlackHoleState.resolve(working: 4, toolRuns: [])

        func bitmap(_ view: some View) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "the closed row rendered")
            return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)),
                                 "closed row bitmap")
        }
        func warmPixels(_ bitmap: NSBitmapImageRep) -> Int {
            var count = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if pixel.redComponent > 0.40, pixel.redComponent - pixel.blueComponent > 0.10 {
                        count += 1
                    }
                }
            }
            return count
        }
        func frozen<V: View>(_ view: V) -> some View { view.environment(\.fleetBlackHoleFrozenTime, 1.7) }

        let shownRow = try bitmap(frozen(FleetClosedRowView(
            working: 4, alert: nil, reading: nil, theme: theme, gapWidth: 80, height: 28,
            blackHole: shown).background(Color.black)))
        let hiddenRow = try bitmap(frozen(FleetClosedRowView(
            working: 4, alert: nil, reading: nil, theme: theme, gapWidth: 80, height: 28,
            blackHole: .hidden).background(Color.black)))

        let reserved = shownRow.pixelsWide - hiddenRow.pixelsWide
        // Both sides of the row are as wide as the wider one (see `FleetEqualSidesLayout`), so the
        // hole and its gap widen the row on both sides: 2 * (18 + 6) pt, in bitmap pixels (scale 2),
        // with one pixel of rounding allowed.
        let expected = Int(2 * (FleetBlackHoleMetrics.size + FleetBlackHoleMetrics.gap)) * 2
        XCTAssertGreaterThanOrEqual(reserved, expected,
                                    "the shown row is wider than the idle row by the hole and its gap")
        XCTAssertLessThanOrEqual(reserved, expected + 2,
                                "and reserves exactly the disc plus its gap, nothing more")

        XCTAssertGreaterThan(warmPixels(shownRow), 0,
                             "the disc and its ring are the row's only warm source")
        XCTAssertEqual(warmPixels(hiddenRow), 0, "an idle row paints no warm pixel at all")

        // The committed docs image, only on request:
        // `FLEET_BLACK_HOLE_PREVIEW=/tmp/hole.png xcodebuild test`. An `if`, never a `guard`, so
        // asking for the preview never skips the assertions above.
        if let previewPath = ProcessInfo.processInfo.environment["FLEET_BLACK_HOLE_PREVIEW"] {
            let reading = try XCTUnwrap(
                FleetFormat.closedRightReading(speed: FleetSpeed(current: 47.2, lastAt: nil),
                                               jobs: 4, total: true),
                "a reported speed has a reading")
            let preview = ImageRenderer(content: FleetClosedRowView(
                working: 4, alert: nil, reading: reading, theme: theme, gapWidth: 200, height: 28,
                blackHole: shown)
                .environment(\.fleetBlackHoleFrozenTime, 1.7)
                .padding(16)
                .background(Color.black))
            preview.scale = 3
            let previewImage = try XCTUnwrap(preview.nsImage, "the preview row rendered")
            let previewBitmap = try XCTUnwrap(
                NSBitmapImageRep(data: try XCTUnwrap(previewImage.tiffRepresentation)),
                "preview bitmap")
            let png = try XCTUnwrap(previewBitmap.representation(using: .png, properties: [:]),
                                    "preview PNG")
            XCTAssertNoThrow(try Data(png).write(to: URL(fileURLWithPath: previewPath)),
                             "the preview wrote")
        }
    }
}
