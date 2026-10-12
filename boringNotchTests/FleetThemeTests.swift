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

    // MARK: - Alert colour

    func testAlertIsTheSameRedOnEverySkin() {
        for skin in FleetSkin.allCases {
            assertColor(FleetTheme(skin: skin).alert, 0xE5484D, "\(skin.rawValue) alert")
        }
    }

    func testAlertIsRedAndNeverTheOfflineColour() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let alert = components(t.alert)
            let hot = components(t.hot)
            XCTAssertGreaterThan(alert.r, alert.g, "\(skin.rawValue) alert reads as red: red beats green")
            XCTAssertGreaterThan(alert.r, alert.b, "\(skin.rawValue) alert reads as red: red beats blue")
            XCTAssertGreaterThan(abs(alert.r - hot.r), 0.001, "\(skin.rawValue) alert differs from hot on red")
            XCTAssertGreaterThan(abs(alert.g - hot.g), 0.001, "\(skin.rawValue) alert differs from hot on green")
            XCTAssertGreaterThan(abs(alert.b - hot.b), 0.001, "\(skin.rawValue) alert differs from hot on blue")
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
                ("muted", t.muted), ("dim", t.dim), ("alertChipText", t.alertChipText),
                ("hotText", t.hotText),
                ("nameOff", t.nameOff),
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
            // PR #14's alert colour is a dot/signal colour and never text: it must clear the dot
            // floor, and the alert's words are drawn in `hot`, which the accent assertion above covers.
            XCTAssertGreaterThanOrEqual(contrast(t.alert, bg), 3.0,
                                        "\(skin) the needs-decision alert dot must reach 3:1")
            XCTAssertLessThan(contrast(t.alert, bg), 7.0,
                              "\(skin) the alert red is a dot colour: it must stay below the 7:1 text floor so it is never used for words")
            // Why an alert dot may not reuse the busy cells' dim pulse: at that opacity the
            // composited colour falls under the 3:1 dot floor, so the alert must breathe by size.
            let alertComponents = components(t.alert)
            let dimmed = Color(.sRGB,
                               red: 0.45 * Double(alertComponents.r),
                               green: 0.45 * Double(alertComponents.g),
                               blue: 0.45 * Double(alertComponents.b),
                               opacity: 1)
            XCTAssertLessThan(contrast(dimmed, bg), 3.0,
                              "\(skin) a dimmed alert dot would fall under the dot floor - never dim it")
            // `wire` is also what FleetMiniSignalMap draws the closed map's wires with:
            XCTAssertGreaterThanOrEqual(contrast(t.wire, bg), 3.0,
                                        "\(skin) idle wires, closed map included, at least 3:1")
            XCTAssertLessThan(contrast(t.line, bg), 3.0,
                              "\(skin) the line hairline is too dark for those wires - do not use it for them")
        }
    }

    /// The ODIN tab's action-needed chip draws its words over the alert red at 16 % on the panel,
    /// not over the bare panel: that composite is the words' real background.
    func testAlertChipTextClearsItsFloorOnTheChipBackground() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let panel = components(t.panelTop)
            let red = components(t.alert)
            let chip = Color(.sRGB,
                             red: Double(red.r * 0.16 + panel.r * 0.84),
                             green: Double(red.g * 0.16 + panel.g * 0.84),
                             blue: Double(red.b * 0.16 + panel.b * 0.84),
                             opacity: 1)
            XCTAssertGreaterThanOrEqual(contrast(t.alertChipText, chip), 7.0,
                                        "\(skin) the chip's words must read at 7:1 on the chip")
            XCTAssertGreaterThanOrEqual(contrast(t.alert, chip), 3.0,
                                        "\(skin) the chip's pulsing dot must reach 3:1 on the chip")
        }
    }

    /// `hot` marks (arcs, chip borders, gauge values at 13 pt) and `hotText` words are two colours: the
    /// words must clear the 7:1 text floor on both panels, and the lighter twin must actually be lighter.
    func testHotTextIsTheTextGradeTwinOfHot() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let bg = t.panelTop
            XCTAssertGreaterThanOrEqual(contrast(t.hotText, bg), 7.0,
                                        "\(skin) attention words need the 7:1 text floor")
            XCTAssertGreaterThan(contrast(t.hotText, bg), contrast(t.hot, bg),
                                 "\(skin) hotText is hot's lighter twin")
        }
    }

    /// The footer's reading text is data at 11 pt, so every level's words must clear the text floor on
    /// both skins, and the alert level must never borrow the alert red itself (a dot colour held below
    /// 7:1 on purpose). The RAM ring's ok-level arc is the memory blue, a mark: 3:1.
    func testRingLevelColoursClearTheirFloors() {
        for skin in FleetSkin.allCases {
            let t = FleetTheme(skin: skin)
            let bg = t.panelTop
            for level in [FleetRingLevel.ok, .hot, .alert] {
                let words = t.ringTextColor(level)
                // `accent` and `hot` are the owner's exempt accent colours: 4.5:1 as words.
                let floor: CGFloat = (level == .ok) ? 4.5 : 7.0
                XCTAssertGreaterThanOrEqual(contrast(words, bg), floor,
                                            "\(skin) \(level) ring words must clear their floor")
            }
            XCTAssertGreaterThanOrEqual(contrast(t.ringTextColor(nil), bg), 7.0,
                                        "\(skin) a missing reading prints in dim text")
            XCTAssertNotEqual(t.ringTextColor(.alert), t.alert,
                              "\(skin) the alert level's words must not be the alert dot colour")
            for kind in FleetRingKind.allCases {
                XCTAssertGreaterThanOrEqual(contrast(t.ringArcColor(.ok, kind: kind), bg), 3.0,
                                            "\(skin) the \(kind.rawValue) ok-level arc must reach 3:1")
            }
            XCTAssertEqual(t.ringArcColor(.ok, kind: .ram), t.memory, "\(skin) RAM keeps the memory blue under 70 %")
            XCTAssertEqual(t.ringArcColor(.hot, kind: .cpu), t.hot, "\(skin) 70-89 % arcs use hot")
            XCTAssertEqual(t.ringArcColor(.alert, kind: .gpu), t.alert, "\(skin) 90 %+ arcs use alert")
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
