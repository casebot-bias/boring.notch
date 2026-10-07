//
//  FleetThemeTests.swift
//  boringNotchTests
//
//  Fleet skin colours (Black / Dark olive), the settings default and its persistence.
//

import XCTest
import SwiftUI
import AppKit
import Defaults

final class FleetThemeTests: XCTestCase {

    // MARK: - Helpers

    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    private func assertColor(_ color: Color, _ hex: UInt32, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let (r, g, b, a) = components(color)
        XCTAssertEqual(a, 1, accuracy: 0.001, "\(message) alpha", file: file, line: line)
        XCTAssertEqual(r, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.001, "\(message) red", file: file, line: line)
        XCTAssertEqual(g, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.001, "\(message) green", file: file, line: line)
        XCTAssertEqual(b, CGFloat(hex & 0xFF) / 255, accuracy: 0.001, "\(message) blue", file: file, line: line)
    }

    // MARK: - Olive skin

    func testOliveThemeMatchesApprovedDesign() {
        let t = FleetTheme(skin: .olive)
        assertColor(t.panelTop,  0x1A2013, "olive panelTop")
        assertColor(t.panelBottom, 0x12160D, "olive panelBottom")
        assertColor(t.panelEdge, 0x232A1A, "olive panelEdge")
        assertColor(t.line,      0x2A3220, "olive line")
        assertColor(t.dim,       0x7D7A62, "olive dim")
        assertColor(t.text,      0xECE4D2, "olive text")
        assertColor(t.accent,    0xC9A77C, "olive accent")
        assertColor(t.ram,       0x4F5D34, "olive ram")
        assertColor(t.hot,       0xD9824B, "olive hot")
        assertColor(t.off,       0x3B4230, "olive off")
        assertColor(t.muted,     0x9A9478, "olive muted")
        assertColor(t.nameText,  0xB9BCB1, "olive nameText")
        assertColor(t.nameOff,   0x4A4C47, "olive nameOff")
        assertColor(t.jobText,   0xD4D6CB, "olive jobText")
        assertColor(t.busyFill,  0x2B2A1C, "olive busyFill")
        assertColor(t.satFill,   0x1D2415, "olive satFill")
        assertColor(t.offFill,   0x0B0B0A, "olive offFill")
        assertColor(t.offStroke, 0x262724, "olive offStroke")
        assertColor(t.coreFill,  0x232B18, "olive coreFill")
        assertColor(t.barTrack,  0x0E120A, "olive barTrack")
        assertColor(t.pillBorder, 0x4A3F2C, "olive pillBorder")
    }

    // MARK: - Black skin

    func testBlackThemeKeepsCurrentLook() {
        let t = FleetTheme(skin: .black)
        assertColor(t.panelTop,  0x000000, "black panelTop")
        assertColor(t.panelBottom, 0x000000, "black panelBottom")
        assertColor(t.line,      0x1D1F1A, "black line")
        assertColor(t.dim,       0x5B5F55, "black dim")
        assertColor(t.text,      0xE8EADF, "black text")
        assertColor(t.accent,    0x9FB38A, "black accent")
        assertColor(t.ram,       0x6D7F4F, "black ram")
        assertColor(t.hot,       0xD9824B, "black hot")
        assertColor(t.off,       0x3A3C37, "black off")
        assertColor(t.muted,     0x8A8D85, "black muted")
        assertColor(t.nameText,  0xB9BCB1, "black nameText")
        assertColor(t.nameOff,   0x4A4C47, "black nameOff")
        assertColor(t.jobText,   0xD4D6CB, "black jobText")
        assertColor(t.busyFill,  0x1B2016, "black busyFill")
        assertColor(t.satFill,   0x161714, "black satFill")
        assertColor(t.offFill,   0x0B0B0A, "black offFill")
        assertColor(t.offStroke, 0x262724, "black offStroke")
        assertColor(t.coreFill,  0x141611, "black coreFill")
        assertColor(t.barTrack,  0x141513, "black barTrack")
        assertColor(t.pillBorder, 0x2C3324, "black pillBorder")
        XCTAssertEqual(components(t.panelEdge).a, 0, accuracy: 0.001, "black panelEdge is clear")
    }

    // MARK: - Panel gradient

    @MainActor
    func testPanelGradientRunsPanelTopToPanelBottom() throws {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let renderer = ImageRenderer(content: Rectangle().fill(t.panel).frame(width: 4, height: 400))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage, "\(skin.rawValue) panel rendered")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)), "\(skin.rawValue) bitmap")

            let top = try XCTUnwrap(bitmap.colorAt(x: 2, y: 0)?.usingColorSpace(.sRGB), "\(skin.rawValue) top pixel")
            let bottom = try XCTUnwrap(bitmap.colorAt(x: 2, y: 399)?.usingColorSpace(.sRGB), "\(skin.rawValue) bottom pixel")

            let pairs: [(CGFloat, CGFloat, String)] = [
                (top.redComponent, bottom.redComponent, "red"),
                (top.greenComponent, bottom.greenComponent, "green"),
                (top.blueComponent, bottom.blueComponent, "blue"),
            ]
            let wanted = [t.panelTop, t.panelBottom].map { components($0) }
            for (index, pair) in pairs.enumerated() {
                let warm = [wanted[0].r, wanted[0].g, wanted[0].b][index]
                let cool = [wanted[1].r, wanted[1].g, wanted[1].b][index]
                // A rendered gradient is interpolated in a device colour space, so compare direction,
                // not the exact values: the top of the panel must sit at the panelTop end of the ramp.
                if abs(warm - cool) < 0.005 {
                    XCTAssertEqual(pair.0, pair.1, accuracy: 0.005, "\(skin.rawValue) \(pair.2) stays flat")
                } else if warm > cool {
                    XCTAssertGreaterThan(pair.0, pair.1, "\(skin.rawValue) \(pair.2) lightens towards the top")
                } else {
                    XCTAssertLessThan(pair.0, pair.1, "\(skin.rawValue) \(pair.2) darkens towards the top")
                }
            }
        }
    }

    // MARK: - Skin metadata

    func testSkinTitles() {
        XCTAssertEqual(FleetSkin.allCases.map(\.title), ["Black", "Dark olive"])
        for skin in FleetSkin.allCases {
            XCTAssertEqual(skin.id, skin.rawValue, "\(skin.rawValue) id")
        }
    }

    // MARK: - Settings default & persistence

    func testSkinDefaultIsOlive() {
        XCTAssertEqual(Defaults.Keys.fleetSkin.defaultValue, .olive)
        Defaults.reset(.fleetSkin)
        XCTAssertEqual(Defaults[.fleetSkin], .olive)
    }

    func testSkinPersists() {
        Defaults.reset(.fleetSkin)
        defer { Defaults.reset(.fleetSkin) }
        Defaults[.fleetSkin] = .black
        XCTAssertEqual(Defaults[.fleetSkin], .black)
        Defaults[.fleetSkin] = .olive
        XCTAssertEqual(Defaults[.fleetSkin], .olive)
    }
}
