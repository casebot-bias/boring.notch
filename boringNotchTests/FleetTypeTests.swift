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
}
