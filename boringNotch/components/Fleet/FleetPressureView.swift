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

    private var highPressure: Bool {
        guard let value = peak.value else { return false }
        return FleetFormat.isHighPressure(value)
    }

    private var arcColor: Color {
        highPressure ? theme.hot : theme.accent
    }

    private var valueText: String {
        guard let value = peak.value else { return FleetFormat.unknown }
        return FleetFormat.percent(value)
    }

    private var valueColor: Color {
        highPressure ? theme.hot : theme.text
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(peak.kind.title)
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                    Text(valueText)
                        .font(.system(size: 12))
                        .foregroundColor(valueColor)
                }
                Text(hostText)
                    .font(.system(size: 11, design: .monospaced))
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
