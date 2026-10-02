//
//  FleetWorkRowsView.swift
//  boringNotch
//
//  "Now working on" rows: deduplicated, sorted, capped at 4.
//  Depends only on Foundation and the model types declared in the same target.
//

import SwiftUI

struct FleetWorkRowsView: View {
    let items: [ActivityItem]

    // MARK: - Body

    var body: some View {
        let rows = sortedDeduplicated
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel
                ForEach(rows) { item in
                    workRow(item)
                }
            }
        }
    }

    // MARK: - Section Label

    private var sectionLabel: some View {
        Text("Now working on")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255))
    }

    // MARK: - Work Row

    private func workRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 6) {
            Text(item.device)
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255))
                .padding(.horizontal, 6)
                .background(Color(red: 0x1D / 255, green: 0x24 / 255, blue: 0x18 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.label)
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEA / 255))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(FleetFormat.elapsed(item.elapsedSec))
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Dedup & Sort

    /// Deduplicate by id, sort elapsed ascending (nil last), take 4.
    private var sortedDeduplicated: [ActivityItem] {
        var seen = Set<String>()
        let unique = items.filter { item in
            seen.insert(item.id).inserted
        }
        return unique
            .sorted { a, b in
                let ea = a.elapsedSec ?? Int.max
                let eb = b.elapsedSec ?? Int.max
                return ea < eb
            }
            .prefix(4)
            .map { $0 }
    }
}
