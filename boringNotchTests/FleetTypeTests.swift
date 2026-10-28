import XCTest

/// The Fleet data font: JetBrains Mono when the bundled faces register, the system monospaced font otherwise.
final class FleetTypeTests: XCTestCase {

    /// The bundle ships JetBrains Mono, so registering it makes `mono(size:)` resolve to that face.
    func testRegistrationMakesMonoResolveToJetBrainsMono() {
        XCTAssertTrue(FleetType.registerBundledFonts(in: Bundle(for: FleetTypeTests.self)),
                      "the test bundle ships the three JetBrains Mono faces")
        XCTAssertEqual(FleetType.resolvedMonoPostScriptName, "JetBrainsMono-Regular")
        XCTAssertFalse(FleetType.didFallBack)
    }

    /// The three weights the design uses all resolve to their own face once registered.
    func testEveryWeightResolvesToItsOwnFace() {
        FleetType.registerBundledFonts(in: Bundle(for: FleetTypeTests.self))
        let cases: [(FleetType.Weight, String)] = [
            (.regular, "JetBrainsMono-Regular"),
            (.medium, "JetBrainsMono-Medium"),
            (.bold, "JetBrainsMono-Bold"),
        ]
        for (weight, name) in cases {
            _ = FleetType.mono(size: 11, weight: weight)
            XCTAssertNotNil(NSFont(name: name, size: 11), "\(name) is available after registration")
        }
    }

    /// The one scale never draws below the floor's own drawn size: a base under `minTextSize` is
    /// clamped to it first, so 11 pt and anything smaller all draw at the same 10.12 pt, and
    /// larger text keeps the panel's ratio.
    func testTheScaleClampsAtTheBaseFloor() {
        let floor = FleetType.scaled(FleetPanelMetrics.minTextSize)
        XCTAssertEqual(floor, 10.12, accuracy: 0.0001, "the 11 pt floor draws at the panel scale")
        XCTAssertEqual(FleetType.scaled(6), floor, "a base under the floor is clamped to it, never drawn smaller")
        XCTAssertEqual(FleetType.scaled(12.5), 11.5, accuracy: 0.0001)
        XCTAssertEqual(FleetType.scaled(15), 13.8, accuracy: 0.0001)
    }
}
