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
        assertColor(t.dim,       0xB0AC85, "olive dim")
        assertColor(t.text,      0xECE4D2, "olive text")
        assertColor(t.accent,    0xC9A77C, "olive accent")
        assertColor(t.memory,    0x8FA6B4, "olive memory")
        assertColor(t.hot,       0xD9824B, "olive hot")
        assertColor(t.off,       0x75865C, "olive off")
        assertColor(t.muted,     0xBFB78F, "olive muted")
        assertColor(t.nameText,  0xB9BCB1, "olive nameText")
        assertColor(t.nameOff,   0xB3A989, "olive nameOff")
        assertColor(t.jobText,   0xD4D6CB, "olive jobText")
        assertColor(t.barTrack,  0x0E120A, "olive barTrack")
        assertColor(t.pillBorder, 0x4A3F2C, "olive pillBorder")
    }

    // MARK: - Black skin

    func testBlackThemeKeepsCurrentLook() {
        let t = FleetTheme(skin: .black)
        assertColor(t.panelTop,  0x000000, "black panelTop")
        assertColor(t.panelBottom, 0x000000, "black panelBottom")
        assertColor(t.line,      0x1D1F1A, "black line")
        assertColor(t.dim,       0x939A87, "black dim")
        assertColor(t.text,      0xE8EADF, "black text")
        assertColor(t.accent,    0x9FB38A, "black accent")
        assertColor(t.memory,    0x7F9BB5, "black memory")
        assertColor(t.hot,       0xD9824B, "black hot")
        assertColor(t.off,       0x6D7166, "black off")
        assertColor(t.muted,     0xA7ACA0, "black muted")
        assertColor(t.nameText,  0xB9BCB1, "black nameText")
        assertColor(t.nameOff,   0x93988C, "black nameOff")
        assertColor(t.jobText,   0xD4D6CB, "black jobText")
        assertColor(t.barTrack,  0x141513, "black barTrack")
        assertColor(t.pillBorder, 0x2C3324, "black pillBorder")
        XCTAssertEqual(components(t.panelEdge).a, 0, accuracy: 0.001, "black panelEdge is clear")
    }

    // MARK: - Response-map wire

    func testBlackWireMatchesApprovedDesign() {
        let t = FleetTheme(skin: .black)
        assertColor(t.wire, 0x7B7B7B, "black wire")
    }

    func testOliveWireMatchesApprovedDesign() {
        let t = FleetTheme(skin: .olive)
        assertColor(t.wire, 0x878267, "olive wire")
    }

    func testWireIsReadableAndBrighterThanLineOnEverySkin() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let wire = components(t.wire)
            let line = components(t.line)
            let wireMax = max(wire.r, wire.g, wire.b)
            let lineMax = max(line.r, line.g, line.b)
            XCTAssertGreaterThanOrEqual(wireMax, 0.35, "\(skin) wire is at least ~35% white")
            XCTAssertGreaterThan(wireMax, lineMax, "\(skin) wire must be brighter than the hairline line colour")
        }
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

    func testSkinDefaultIsBlack() {
        XCTAssertEqual(Defaults.Keys.fleetSkin.defaultValue, .black)
        Defaults.reset(.fleetSkin)
        XCTAssertEqual(Defaults[.fleetSkin], .black)
    }

    func testSkinPersists() {
        Defaults.reset(.fleetSkin)
        defer { Defaults.reset(.fleetSkin) }
        Defaults[.fleetSkin] = .black
        XCTAssertEqual(Defaults[.fleetSkin], .black)
        Defaults[.fleetSkin] = .olive
        XCTAssertEqual(Defaults[.fleetSkin], .olive)
    }

    // MARK: - Contrast floors

    /// WCAG relative luminance of an sRGB colour.
    private func luminance(_ color: Color) -> CGFloat {
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (r, g, b, _) = components(color)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The owner could not read the panel: grey on black was too dark. Every text colour must clear
    /// its floor against the lighter end of that skin's panel gradient (the worst case for light
    /// text): 7:1 for text under 12 pt, at least 3:1 for status dots and idle wires. The owner exempted
    /// the accent colours (`accent`, `hot`) from the 7:1 text floor, so they are held to 4.5:1 instead.
    func testEveryTextColourClearsItsContrastFloor() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let bg = t.panelTop
            let textRoles: [(String, Color)] = [
                ("text", t.text), ("jobText", t.jobText), ("nameText", t.nameText),
                ("muted", t.muted), ("dim", t.dim), ("nameOff", t.nameOff),
            ]
            for (name, colour) in textRoles {
                XCTAssertGreaterThanOrEqual(contrast(colour, bg), 7.0,
                                            "\(skin) \(name) must reach 7:1 for text under 12 pt")
            }
            // accent and hot are the approved design's accent colours: the owner exempted them from
            // the text floor, but they still have to read as text.
            for (name, colour) in [("accent", t.accent), ("hot", t.hot)] {
                XCTAssertGreaterThanOrEqual(contrast(colour, bg), 4.5,
                                            "\(skin) \(name) is an accent colour: at least 4.5:1")
            }
            XCTAssertGreaterThanOrEqual(contrast(t.off, bg), 3.0, "\(skin) status dots at least 3:1")
            // `wire` is also what FleetMiniSignalMap draws the closed map's wires with:
            XCTAssertGreaterThanOrEqual(contrast(t.wire, bg), 3.0,
                                        "\(skin) idle wires, closed map included, at least 3:1")
            XCTAssertLessThan(contrast(t.line, bg), 3.0,
                              "\(skin) the line hairline is too dark for those wires - do not use it for them")
        }
    }

    /// The reading hierarchy the panel relies on: body text beats names, names beat muted, muted beats dim.
    func testTextHierarchyBeatsMutedBeatsDim() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let bg = t.panelTop
            XCTAssertGreaterThan(contrast(t.text, bg), contrast(t.nameText, bg), "\(skin) text > nameText")
            XCTAssertGreaterThan(contrast(t.nameText, bg), contrast(t.muted, bg), "\(skin) nameText > muted")
            XCTAssertGreaterThan(contrast(t.muted, bg), contrast(t.dim, bg), "\(skin) muted > dim")
        }
    }
}
