//
//  FleetPressureView.swift
//  boringNotch
//
//  Footer peak strip: one thin ring per hardware peak (CPU / GPU / RAM)
//  with the highest reported reading and the host that reported it.
//

import Defaults
import SwiftUI

struct FleetPressureView: View {
    let peaks: [FleetPeak]

    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    var body: some View {
        HStack(spacing: 22) {
            ForEach(peaks) { peak in
                PeakReading(peak: peak, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PeakReading: View {
    let peak: FleetPeak
    let theme: FleetTheme

    /// The rounded percent shown by `FleetFormat.percent`, so the colour tracks the number the user reads.
    private var displayedPercent: Int? {
        peak.value.map { Int($0.rounded()) }
    }

    /// Level colour shared by ring and number: < 70 % accent, 70-89 % hot, >= 90 % alert,
    /// `dim` when the peak has no reading.
    private var levelColor: Color {
        guard let percent = displayedPercent else { return theme.dim }
        if percent >= 90 { return theme.alert }
        if percent >= 70 { return theme.hot }
        return theme.accent
    }

    private var arcColor: Color {
        displayedPercent == nil ? theme.line : levelColor
    }

    private var valueText: String {
        guard let value = peak.value else { return FleetFormat.unknown }
        return FleetFormat.percent(value)
    }

    private var hostText: String {
        guard peak.value != nil else { return "Not reported" }
        return peak.host ?? FleetFormat.unknown
    }

    var body: some View {
        HStack(spacing: 7) {
            ring
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                (
                    Text(peak.kind.title)
                        .foregroundColor(theme.muted)
                    + Text(" \(valueText)")
                        .foregroundColor(levelColor)
                )
                .font(FleetType.mono(size: 13, weight: .medium))
                Text(hostText)
                    .font(FleetType.mono(size: 11))
                    .foregroundColor(theme.dim)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(theme.line, lineWidth: 1.5)
            if let value = peak.value {
                Circle()
                    .trim(from: 0, to: FleetFormat.fraction(value))
                    .stroke(arcColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
