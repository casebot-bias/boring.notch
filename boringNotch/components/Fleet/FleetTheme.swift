//
//  FleetTheme.swift
//  boringNotch
//
//  Fleet skin colours, ported from the approved fleet-notch-v3-olive design.
//

import Defaults
import SwiftUI

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

enum FleetSkin: String, CaseIterable, Identifiable, Defaults.Serializable {
    case black
    case olive

    var id: String { rawValue }

    var title: String {
        self == .olive ? "Dark olive" : "Black"
    }
}

/// Colours for the current fleet skin.
struct FleetTheme {
    init(skin: FleetSkin) {
        self.skin = skin
        switch skin {
        case .black:
            panelTop      = rgb(0x000000)
            panelBottom   = rgb(0x000000)
            panelEdge     = .clear
            line          = rgb(0x1D1F1A)
            dim           = rgb(0x5B5F55)
            text          = rgb(0xE8EADF)
            accent        = rgb(0x9FB38A)
            ram           = rgb(0x6D7F4F)
            hot           = rgb(0xD9824B)
            off           = rgb(0x3A3C37)
            muted         = rgb(0x8A8D85)
            nameText      = rgb(0xB9BCB1)
            nameOff       = rgb(0x4A4C47)
            jobText       = rgb(0xD4D6CB)
            busyFill      = rgb(0x1B2016)
            satFill       = rgb(0x161714)
            offFill       = rgb(0x0B0B0A)
            offStroke     = rgb(0x262724)
            coreFill      = rgb(0x141611)
            barTrack      = rgb(0x141513)
            pillBorder    = rgb(0x2C3324)
        case .olive:
            panelTop      = rgb(0x1A2013)
            panelBottom   = rgb(0x12160D)
            panelEdge     = rgb(0x232A1A)
            line          = rgb(0x2A3220)
            dim           = rgb(0x7D7A62)
            text          = rgb(0xECE4D2)
            accent        = rgb(0xC9A77C)
            ram           = rgb(0x4F5D34)
            hot           = rgb(0xD9824B)
            off           = rgb(0x3B4230)
            muted         = rgb(0x9A9478)
            nameText      = rgb(0xB9BCB1)
            nameOff       = rgb(0x4A4C47)
            jobText       = rgb(0xD4D6CB)
            busyFill      = rgb(0x2B2A1C)
            satFill       = rgb(0x1D2415)
            offFill       = rgb(0x0B0B0A)
            offStroke     = rgb(0x262724)
            coreFill      = rgb(0x232B18)
            barTrack      = rgb(0x0E120A)
            pillBorder    = rgb(0x4A3F2C)
        }
    }

    let skin: FleetSkin
    let panelTop: Color
    let panelBottom: Color
    let panelEdge: Color

    let line: Color
    let dim: Color
    let text: Color
    let accent: Color
    let ram: Color
    let hot: Color
    let off: Color
    let muted: Color
    let nameText: Color
    let nameOff: Color
    let jobText: Color
    let busyFill: Color
    let satFill: Color
    let offFill: Color
    let offStroke: Color
    let coreFill: Color
    let barTrack: Color
    let pillBorder: Color

    var panel: LinearGradient {
        LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension Defaults.Keys {
    static let fleetSkin = Key<FleetSkin>("fleetSkin", default: .olive)
}
