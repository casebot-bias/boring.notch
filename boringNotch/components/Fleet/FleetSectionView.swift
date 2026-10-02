//
//  FleetSectionView.swift
//  boringNotch
//
//  Right-hand fleet column of the opened notch (design: notch-design.html):
//  1 px divider, header readout, node map, machine cards, work rows. The parent
//  places this view in a 460 pt column next to Now Playing and sizes it.
//

import SwiftUI

struct FleetSectionView: View {
    @ObservedObject private var store = FleetStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                headerRow

                if store.fleet != nil || store.activity != nil {
                    FleetMapView(model: store.mapModel)
                    FleetMachineCardsView(machines: store.fleet?.machines ?? [], activity: store.activity)
                    FleetWorkRowsView(items: workItems)
                } else {
                    Text("Waiting for fleet…")
                        .font(.system(size: 10))
                        .foregroundColor(Self.muted)
                }
            }
            .padding(.leading, 18)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("FLEET · \(store.mapModel.nodes.count) nodes + origin")
            Spacer()
            Text("\(store.activeCount) active")
        }
        .font(.system(size: 11))
        .foregroundColor(Self.muted)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    /// Raw flattened items; sorting, dedup and the 4-row cap live in FleetWorkRowsView.
    private var workItems: [ActivityItem] {
        return store.activity?.devices.flatMap(\.items) ?? []
    }

    // MARK: - Palette

    private static let muted = Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255)
}
