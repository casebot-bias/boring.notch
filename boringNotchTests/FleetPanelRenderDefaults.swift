//
//  FleetPanelRenderDefaults.swift
//  boringNotchTests
//
//  The two app defaults the Fleet views read. They live in boringNotch/models/Constants.swift,
//  which the test target does not compile (it drags in most of the app), so the snapshot test's
//  render harness defines them here with the same names and defaults. Keys and defaults must match
//  that file; a rename there has to be mirrored here.
//

import Defaults

extension Defaults.Keys {
    static let showFleet = Key<Bool>("showFleet", default: true)
    static let fleetBaseURL = Key<String>("fleetBaseURL", default: "https://case.tail2f9fd5.ts.net")
}
