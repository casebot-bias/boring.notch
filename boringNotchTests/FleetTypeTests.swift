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

    /// The one scale is clamped after scaling: nothing draws below `minTextSize`, so the rendered
    /// floor is `minTextSize` itself. Bases at or below the threshold `minTextSize / textScale`
    /// all draw at the floor; above it the panel's ratio applies (12.5 -> 11.5, 15 -> 13.8).
    /// A base between the floor and the threshold (11.5) catches the bug: clamping the base
    /// before scaling would draw it below 11 pt.
    func testTheScaleClampsAtTheRenderedFloor() {
        XCTAssertEqual(FleetType.scaled(6), 11, accuracy: 0.0001, "a base under the floor draws at the floor")
        XCTAssertEqual(FleetType.scaled(FleetPanelMetrics.minTextSize), 11, accuracy: 0.0001, "the floor base draws at the floor")
        XCTAssertEqual(FleetType.scaled(11.5), 11, accuracy: 0.0001, "above the base floor but below the post-scale floor, still the floor")
        let threshold = FleetPanelMetrics.minTextSize / FleetPanelMetrics.textScale
        XCTAssertEqual(FleetType.scaled(threshold - 0.05), 11, accuracy: 0.0001, "just below the threshold the floor holds")
        XCTAssertEqual(FleetType.scaled(threshold), 11, accuracy: 0.0001, "at the threshold the floor still holds")
        XCTAssertEqual(FleetType.scaled(threshold + 0.5), (threshold + 0.5) * FleetPanelMetrics.textScale, accuracy: 0.0001, "just above the threshold the scale applies")
        XCTAssertEqual(FleetType.scaled(12.5), 11.5, accuracy: 0.0001)
        XCTAssertEqual(FleetType.scaled(15), 13.8, accuracy: 0.0001)
    }
}
