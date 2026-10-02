//
//  FleetMachineCardsView.swift
//  boringNotch
//
//  Four-across grid of machine stat cards, ported from the `.grid`/`.card` block
//  of notch-design.html: title dot + CPU/RAM bars + GPU-or-tokens row with temperature.
//

import SwiftUI

// MARK: - Colors

private enum FleetCardColors {
    static let sage = Color(red: 0x9F / 255, green: 0xB3 / 255, blue: 0x8A / 255)
    static let warn = Color(red: 0xC8 / 255, green: 0x69 / 255, blue: 0x3A / 255)
    static let foreground = Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
    static let muted = Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x80 / 255)
    static let cardBackground = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let track = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
}

// MARK: - View

struct FleetMachineCardsView: View {
    let machines: [FleetMachine]
    let activity: ActivitySnapshot?

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(machines) { machine in
                card(for: machine)
            }
        }
    }

    // MARK: Card

    private func card(for machine: FleetMachine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title row: 6 pt sage dot + machine title.
            HStack(spacing: 5) {
                Circle()
                    .fill(FleetCardColors.sage)
                    .frame(width: 6, height: 6)
                Text(machine.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FleetCardColors.foreground)
                    .lineLimit(1)
            }
            .padding(.bottom, 2)

            metricRow(label: "CPU", value: FleetFormat.percent(machine.cpuLoadPct))
            bar(fraction: FleetFormat.barFraction(machine.cpuLoadPct), fill: FleetCardColors.sage)
                .padding(.bottom, 2)

            metricRow(label: "RAM", value: FleetFormat.percent(machine.ramUsedPct))
            bar(
                fraction: FleetFormat.barFraction(machine.ramUsedPct),
                fill: FleetFormat.isRAMWarning(machine.ramUsedPct) ? FleetCardColors.warn : FleetCardColors.sage
            )
            .padding(.bottom, 2)

            // GPU/tokens row: activity tok/s wins, else machine GPU %, temperature on the right.
            metricRow(
                label: FleetFormat.gpuOrTokens(gpu: machine.gpuUtilPct, tokPerSec: tokPerSec(for: machine.id)),
                value: FleetFormat.celsius(machine.cpuTempC)
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleetCardColors.cardBackground)
        .cornerRadius(8)
    }

    // MARK: Rows

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(FleetCardColors.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(FleetCardColors.foreground)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// 3 pt `#2A2A2A` track with a leading-aligned fill scaled to `fraction` (0...1).
    private func bar(fraction: Double, fill: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FleetCardColors.track)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * CGFloat(max(0.0, min(1.0, fraction))))
            }
        }
        .frame(height: 3)
    }

    private func tokPerSec(for machineId: String) -> Double? {
        activity?.devices.first { $0.device == machineId }?.tokPerSec
    }
}
