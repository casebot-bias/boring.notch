//
//  FleetSectionView.swift
//  boringNotch
//
//  Right-hand fleet column of the opened notch:
//  1 px divider, "FLEET" header readout, orbit + lanes side-by-side, fixed Now block.
//

import SwiftUI

// MARK: - Palette

enum FleetPalette {
    /// Palette for the fleet panel, ported from the approved fleet-notch-v2 design.
    static let sage     = Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255)
    static let olive    = Color(red: 0x6D / 255, green: 0x7F / 255, blue: 0x4F / 255)
    static let hot      = Color(red: 0xD9 / 255, green: 0x82 / 255, blue: 0x4B / 255)
    static let off      = Color(red: 0x3A / 255, green: 0x3C / 255, blue: 0x37 / 255)
    static let line     = Color(red: 0x1D / 255, green: 0x1F / 255, blue: 0x1A / 255)
    static let dim      = Color(red: 0x5B / 255, green: 0x5F / 255, blue: 0x55 / 255)
    static let text     = Color(red: 0xE8 / 255, green: 0xEA / 255, blue: 0xDF / 255)
    static let nameText = Color(red: 0xB9 / 255, green: 0xBC / 255, blue: 0xB1 / 255)
    static let nameOff  = Color(red: 0x4A / 255, green: 0x4C / 255, blue: 0x47 / 255)
    static let busyFill = Color(red: 0x1B / 255, green: 0x20 / 255, blue: 0x16 / 255)
    static let satFill  = Color(red: 0x16 / 255, green: 0x17 / 255, blue: 0x14 / 255)
    static let offFill  = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0A / 255)
    static let offStroke = Color(red: 0x26 / 255, green: 0x27 / 255, blue: 0x24 / 255)
    static let coreFill = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x11 / 255)
    static let barTrack = Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x13 / 255)
    static let pillBorder = Color(red: 0x2C / 255, green: 0x33 / 255, blue: 0x24 / 255)
    static let jobText  = Color(red: 0xD4 / 255, green: 0xD6 / 255, blue: 0xCB / 255)
    static let muted    = Color(red: 0x8A / 255, green: 0x8D / 255, blue: 0x85 / 255)
}

// MARK: - Section View

struct FleetSectionView: View {
    @ObservedObject private var store = FleetStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(alignment: .center, spacing: 14) {
                    FleetOrbitView(model: store.orbitModel)
                    FleetLanesView(lanes: store.orbitModel.lanes)
                }
                FleetNowView(jobs: store.orbitModel.nowJobs)
            }
            .padding(.leading, 18)
        }
        .frame(height: fleetSectionHeight, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("FLEET")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(FleetPalette.muted)
            Spacer(minLength: 8)
            Text("\(store.activeCount) active")
                .font(.system(size: 11))
                .foregroundColor(FleetPalette.sage)
        }
        .frame(maxWidth: .infinity)
    }
}
