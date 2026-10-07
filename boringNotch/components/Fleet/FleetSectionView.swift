//
//  FleetSectionView.swift
//  boringNotch
//
//  Right-hand fleet column of the opened notch:
//  1 px divider, "FLEET" header readout, orbit + lanes side-by-side, fixed Now block.
//  Colours are driven by FleetTheme (skin: FleetSkin).

import SwiftUI
import Defaults


// MARK: - Section View

struct FleetSectionView: View {
    @ObservedObject private var store = FleetStore.shared
    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            theme.line
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
                .foregroundColor(theme.muted)
            Spacer(minLength: 8)
            Text("\(store.activeCount) active")
                .font(.system(size: 11))
                .foregroundColor(theme.accent)
        }
        .frame(maxWidth: .infinity)
    }
}
