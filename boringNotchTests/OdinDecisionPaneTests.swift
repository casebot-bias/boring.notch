import XCTest
import SwiftUI
import AppKit

private final class PaneDriver: ObservableObject {
    @Published var decisions: [FleetDecision]
    init(_ decision: FleetDecision) { decisions = [decision] }
}

private struct PaneFixture: View {
    @ObservedObject var driver: PaneDriver
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OdinDecisionView(decisions: driver.decisions, sendingJob: nil, sentJob: nil,
                             error: nil, startsOnFound: true, onSend: { _, _ in })
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 604, alignment: .topLeading)
        .background(Color.black)
    }
}

/// The findings box is a ScrollView, and `ImageRenderer` draws a ScrollView as a blank image,
/// so these tests host the real view in an `NSHostingView`, scroll it through AppKit's own
/// `NSScrollView` and rasterise it with `cacheDisplay`. The proof image is the live view's
/// `cacheDisplay` pass with the same view's PDF pass over its indicator strip: `cacheDisplay`
/// paints no `NSScroller` at all (0 lit pixels in the box's right strip, and for a plain
/// AppKit scroll view too), while PDF paints the indicator but no layer-backed SwiftUI content.
///
/// The proof PNGs come from the env vars `ODIN_PANE_TALL_PREVIEW`, `ODIN_PANE_BOTTOM_PREVIEW`
/// and `ODIN_PANE_SHORT_PREVIEW`; only their `TEST_RUNNER_`-prefixed names reach the test
/// process, so the invocation is
/// `env TEST_RUNNER_ODIN_PANE_TALL_PREVIEW=docs/fleet-decision-pane-tall.png xcodebuild test ...`.
final class OdinDecisionPaneTests: XCTestCase {
    @MainActor private func decision(short: Bool = false, replacement: Bool = false) -> FleetDecision {
        FleetDecision(job: replacement ? "odin-pane-replacement" : "odin-pane-fixture", repo: "case/x", pr: 1,
                      reason: "round_limit", round: 2,
                      found: short ? ["finding 1: one short line."] : (0..<12).map {
                          "finding \($0 + 1): \(replacement ? "Replacement" : "Original") review identifies a reproducible failure requiring careful inspection before approval."
                      }, question: "One sentence question.", options: OdinOption.defaults)
    }

    @MainActor private func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        } while Date() < end
    }

    @MainActor private func host(_ driver: PaneDriver) -> (NSHostingView<PaneFixture>, NSWindow) {
        XCTAssertTrue(FleetType.registerBundledFonts(in: Bundle(for: Self.self)))
        let view = NSHostingView(rootView: PaneFixture(driver: driver))
        view.frame = NSRect(x: 0, y: 0, width: 604, height: 300)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        pump(0.6)
        return (view, window)
    }

    @MainActor private func scrollView(_ view: NSView) throws -> NSScrollView {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = try? scrollView(child) { return scroll }
        }
        throw NSError(domain: "Missing SwiftUI NSScrollView", code: 1)
    }

    @MainActor private func raster(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * 2,
            pixelsHigh: Int(view.bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @MainActor private func pdfRaster(_ view: NSView, scale: Int) throws -> NSBitmapImageRep {
        let provider = try XCTUnwrap(CGDataProvider(data: view.dataWithPDF(inside: view.bounds) as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: Int(view.bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        // Bitmap contexts already include rep.size's pixel density; apply the requested scale once.
        context.concatenate(context.ctm.inverted())
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.drawPDFPage(page)
        return rep
    }

    private func indicatorPixels(_ rep: NSBitmapImageRep, box: NSRect) -> Int {
        var count = 0
        for y in max(0, Int(box.minY * 2))..<min(rep.pixelsHigh, max(0, Int(box.maxY * 2))) {
            for x in max(0, min(rep.pixelsWide, Int((box.maxX - 17) * 2)))..<min(rep.pixelsWide, max(0, Int(box.maxX * 2))) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(c.redComponent, c.greenComponent, c.blueComponent) > 0.12 { count += 1 }
            }
        }
        return count
    }

    @MainActor private func proofImage(_ host: NSView, box scroll: NSScrollView,
                                      rep: NSBitmapImageRep, preview: String) throws -> (before: Int, after: Int) {
        scroll.flashScrollers()
        pump(0.3)
        let scrollerRep = try pdfRaster(scroll, scale: 2)
        let r = host.convert(scroll.bounds, from: scroll)
        let boxRect = NSRect(x: r.minX, y: host.isFlipped ? r.minY : host.bounds.height - r.maxY,
                             width: r.width, height: r.height)
        let body = NSRect(x: boxRect.minX, y: boxRect.minY, width: boxRect.width - 17, height: boxRect.height)
        let bodyBefore = brightest(rep, body)
        let before = indicatorPixels(rep, box: boxRect)
        let y = host.isFlipped ? host.bounds.height - r.maxY : r.minY
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clip(to: NSRect(x: r.maxX - 17, y: y, width: 17, height: r.height))
        NSImage(cgImage: try XCTUnwrap(scrollerRep.cgImage), size: scroll.bounds.size)
            .draw(in: NSRect(x: r.minX, y: y, width: r.width, height: r.height))
        NSGraphicsContext.restoreGraphicsState()
        let after = indicatorPixels(rep, box: boxRect)
        let bodyAfter = brightest(rep, body)
        XCTAssertEqual(bodyBefore, bodyAfter, accuracy: 0.001, "\(preview) body \(bodyBefore) -> \(bodyAfter)")
        print("\(preview) body brightness \(bodyBefore) -> \(bodyAfter)")
        if let path = ProcessInfo.processInfo.environment[preview] {
            let bounds = box(scroll, in: host)
            let height = min(rep.pixelsHigh, Int((bounds.maxY + 2) * 2))
            let width = min(rep.pixelsWide, Int(r.maxX * 2))
            let crop = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for y in 0..<height {
                for x in 0..<width {
                    if let color = rep.colorAt(x: x, y: y) { crop.setColor(color, atX: x, y: y) }
                }
            }
            try XCTUnwrap(crop.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            print("\(preview): \(path), \(width)x\(height), indicator \(before) -> \(after)")
        }
        return (before, after)
    }

    // All raster rectangles use top-left point coordinates, independently of AppKit's flippedness.
    @MainActor private func box(_ scroll: NSScrollView, in host: NSView) -> CGRect {
        let r = host.convert(scroll.contentView.bounds, from: scroll.contentView)
        return CGRect(x: r.minX, y: host.isFlipped ? r.minY : host.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private func brightest(_ rep: NSBitmapImageRep, _ rect: CGRect) -> CGFloat {
        var result: CGFloat = 0
        for y in max(0, Int(rect.minY * 2))..<min(rep.pixelsHigh, max(0, Int(rect.maxY * 2))) {
            for x in max(0, Int(rect.minX * 2))..<min(rep.pixelsWide, max(0, Int(rect.maxX * 2))) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    // Exclude the orange bullets; measure neutral text only.
                    if abs(c.redComponent - c.greenComponent) < 0.16 {
                        result = max(result, min(c.redComponent, c.greenComponent, c.blueComponent))
                    }
                }
            }
        }
        return result
    }

    @MainActor private func scrollToEnd(_ host: NSView, _ scroll: NSScrollView) throws {
        let rect = host.convert(scroll.bounds, from: scroll)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        let target = try XCTUnwrap(host.hitTest(point))
        print("ODIN target=\(target), host frame=\(host.frame), rect=\(rect), point=\(point)")
        for _ in 0..<60 {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
            pump(0.03)
        }
        pump(0.3)
        print("ODIN clip after 60 wheel events: \(scroll.contentView.bounds)")
    }

    @MainActor private func assertRows(_ scroll: NSScrollView, rep: NSBitmapImageRep, host: NSView, atEnd: Bool,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let document = try XCTUnwrap(scroll.documentView)
        let clip = scroll.contentView.bounds
        let rowHeight = (document.bounds.height - 11 * 4) / 12
        let first = CGRect(x: 10, y: 0, width: clip.width - 30, height: rowHeight)
        let last = CGRect(x: 10, y: 11 * (rowHeight + 4), width: clip.width - 30, height: rowHeight)
        let visible = atEnd ? last : first
        let absent = atEnd ? first : last
        XCTAssertFalse(clip.intersects(absent), "\(atEnd ? "FIRST" : "LAST") finding must be outside the viewport: clip=\(clip), row=\(absent)", file: file, line: line)
        XCTAssertTrue(clip.intersects(visible), file: file, line: line)
        let b = box(scroll, in: host)
        let region = CGRect(x: b.minX + 10, y: b.minY + max(0, visible.minY - clip.minY), width: b.width - 30,
                            height: min(rowHeight, clip.maxY - visible.minY))
        XCTAssertGreaterThan(brightest(rep, region), 0.35, "Visible finding row must contain bright text: \(region)", file: file, line: line)
    }

    @MainActor private func windowBox(_ scroll: NSScrollView, in host: NSView) -> NSRect {
        var rect = box(scroll, in: host)
        if !host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
        return host.convert(rect, to: nil)
    }

    @MainActor func testTheFindingsBoxClaimsItsOwnScroll() throws {
        let (view, window) = host(PaneDriver(decision()))
        defer { window.close() }
        func marker(in view: NSView) -> ScrollClaimView? {
            if let marker = view as? ScrollClaimView { return marker }
            return view.subviews.lazy.compactMap { marker(in: $0) }.first
        }
        let claim = try XCTUnwrap(marker(in: view), "The real findings box must install a ScrollClaimView")
        let scroll = try scrollView(view)
        let rect = scroll.convert(scroll.bounds, to: nil)
        let clip = windowBox(scroll, in: view)
        let claimed = claim.convert(claim.bounds, to: nil)
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let options = NSPoint(x: rect.maxX + 20, y: rect.midY)
        let above = NSPoint(x: rect.midX, y: rect.maxY + 5)
        print("ODIN claim rect=\(claimed), box rect=\(rect), clip rect=\(clip), centre=\(centre), options=\(options), above=\(above)")
        XCTAssertEqual(claimed.minX, rect.minX, accuracy: 1.5)
        XCTAssertEqual(claimed.maxX, rect.maxX, accuracy: 1.5)
        XCTAssertEqual(claimed.minY, rect.minY, accuracy: 1.5)
        XCTAssertEqual(claimed.maxY, rect.maxY, accuracy: 1.5)
        // The narrower clip view is inside the claim: the scroller gutter is claimed too, on purpose.
        XCTAssertTrue(claimed.contains(clip))
        XCTAssertLessThan(clip.width, claimed.width)
        XCTAssertTrue(ScrollClaimView.claims(centre, in: window))
        XCTAssertTrue(view.convert(view.bounds, to: nil).contains(options))
        XCTAssertFalse(ScrollClaimView.claims(options, in: window))
        XCTAssertFalse(ScrollClaimView.claims(above, in: window))
        XCTAssertFalse(ScrollClaimView.claims(centre, in: nil))
        let parent = try XCTUnwrap(claim.superview)
        XCTAssertNil(claim.hitTest(parent.convert(centre, from: nil)))
    }

    @MainActor func testAScrollOnTheBoxDoesNotDriveTheNotchGesture() throws {
        let (view, window) = host(PaneDriver(decision()))
        defer { window.close() }
        window.setFrameOrigin(.zero)
        pump(0.05)
        let rect = windowBox(try scrollView(view), in: view)
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let options = NSPoint(x: rect.maxX + 20, y: rect.midY)
        XCTAssertTrue(view.convert(view.bounds, to: nil).contains(options))
        XCTAssertFalse(ScrollClaimView.claims(options, in: window))
        let screenHeight = try XCTUnwrap(NSScreen.screens.first).frame.height
        func wheel(at point: NSPoint) throws -> NSEvent {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0))
            cg.location = CGPoint(x: window.frame.minX + point.x,
                                  y: screenHeight - (window.frame.minY + point.y))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(event.locationInWindow, point, "Scroll event mapping must preserve the requested window point")
            return event
        }
        var actions: [(CGFloat, NSEvent.Phase)] = []
        func pairs() -> String {
            actions.map { "(\($0.0), \($0.1 == .began ? "began" : $0.1 == .changed ? "changed" : $0.1 == .ended ? "ended" : String($0.1.rawValue)))" }.joined(separator: ", ")
        }
        let coordinator = ScrollMonitor.Coordinator(direction: .up, threshold: 4) {
            actions.append(($0, $1))
        }
        defer { coordinator.removeMonitor() }
        for _ in 0..<6 {
            coordinator.handleScroll(try wheel(at: centre), in: window)
            pump(0.03)
        }
        print("ODIN box actions=[\(pairs())]")
        XCTAssertFalse(actions.contains { $0.1 == .began || $0.1 == .changed }, pairs())
        XCTAssertFalse(actions.contains { $0.0 > 4 }, pairs())
        actions.removeAll()
        for _ in 0..<6 {
            coordinator.handleScroll(try wheel(at: options), in: window)
            pump(0.03)
        }
        print("ODIN options actions=[\(pairs())]")
        XCTAssertTrue(actions.contains { $0.1 == .began && $0.0 >= 4 }, pairs())

        // Start a fresh gesture, then cross into the box while it is still active.
        coordinator.removeMonitor()
        actions.removeAll()
        for _ in 0..<6 {
            coordinator.handleScroll(try wheel(at: options), in: window)
            if actions.contains(where: { $0.1 == .began && $0.0 >= 4 }) { break }
            pump(0.03)
        }
        XCTAssertTrue(actions.contains { $0.1 == .began && $0.0 >= 4 }, pairs())
        let beforeReset = actions.count
        coordinator.handleScroll(try wheel(at: centre), in: window)
        pump(0.4)
        print("ODIN reset actions=[\(pairs())], reset suffix=\(actions.dropFirst(beforeReset))")
        XCTAssertEqual(actions.count, beforeReset + 1, pairs())
        if actions.count > beforeReset {
            XCTAssertEqual(actions[beforeReset].0, 0, pairs())
            XCTAssertEqual(actions[beforeReset].1, .ended, pairs())
        }
    }

    @MainActor func testTheTallBoxScrollsToTheLastFinding() throws {
        let (view, window) = host(PaneDriver(decision()))
        defer { window.close() }
        let scroll = try scrollView(view)
        let top = try raster(view)
        try assertRows(scroll, rep: top, host: view, atEnd: false)
        let b = box(scroll, in: view)
        let middle = brightest(top, CGRect(x: b.minX + 10, y: b.midY - 20, width: b.width - 30, height: 40))
        let bottom = brightest(top, CGRect(x: b.minX + 10, y: b.maxY - 3, width: b.width - 30, height: 3))
        print("ODIN fade top bottom=\(bottom), middle=\(middle), factor=\(bottom / middle)")
        XCTAssertGreaterThan(bottom, 0, "The fade sample must contain text, not an empty row")
        // Measured ratio 0.0522: leave room for glyph antialiasing, not an unfaded band.
        XCTAssertLessThan(bottom, middle * 0.2, "Bottom \(bottom), middle \(middle), factor \(bottom / middle); expected < 0.2")
        let scroller = try XCTUnwrap(scroll.verticalScroller)
        XCTAssertFalse(scroller.isHidden)
        XCTAssertLessThan(scroller.knobProportion, 0.99)
        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height)
        print("ODIN tall knobProportion=\(scroller.knobProportion), hidden=\(scroller.isHidden), alpha=\(scroller.alphaValue)")
        let tallProof = try proofImage(view, box: scroll, rep: top, preview: "ODIN_PANE_TALL_PREVIEW")
        XCTAssertEqual(tallProof.before, 0, "Indicator \(tallProof.before) -> \(tallProof.after)")
        XCTAssertGreaterThan(tallProof.after, 0, "Indicator \(tallProof.before) -> \(tallProof.after)")
        try scrollToEnd(view, scroll)
        let end = try raster(view)
        try assertRows(scroll, rep: end, host: view, atEnd: true)
        let endMiddle = brightest(end, CGRect(x: b.minX + 10, y: b.midY - 20, width: b.width - 30, height: 40))
        let endBottom = brightest(end, CGRect(x: b.minX + 10, y: b.maxY - 3, width: b.width - 30, height: 3))
        print("ODIN end bottom=\(endBottom), middle=\(endMiddle), factor=\(endBottom / endMiddle)")
        // The final 3 pt contains antialiased descenders (measured ratio 0.9030).
        XCTAssertGreaterThan(endBottom, endMiddle * 0.85, "End bottom \(endBottom), middle \(endMiddle), factor \(endBottom / endMiddle): fade must be gone")
        let endBand = brightest(end, CGRect(x: b.minX + 10, y: b.maxY - OdinDecisionPaneMetrics.fadeHeight,
                                            width: b.width - 30, height: OdinDecisionPaneMetrics.fadeHeight))
        XCTAssertGreaterThan(endBand, endMiddle * 0.95, "Unfaded 12 pt band \(endBand), middle \(endMiddle)")
        let bottomProof = try proofImage(view, box: scroll, rep: end, preview: "ODIN_PANE_BOTTOM_PREVIEW")
        XCTAssertEqual(bottomProof.before, 0, "Indicator \(bottomProof.before) -> \(bottomProof.after)")
        XCTAssertGreaterThan(bottomProof.after, 0, "Indicator \(bottomProof.before) -> \(bottomProof.after)")
    }

    @MainActor func testASingleShortFindingLeavesTheBoxAtItsContentHeight() throws {
        let (tall, tallWindow) = host(PaneDriver(decision()))
        defer { tallWindow.close() }
        let tallBox = box(try scrollView(tall), in: tall)
        XCTAssertEqual(tallBox.height, 96, accuracy: 0.5)
        let (short, shortWindow) = host(PaneDriver(decision(short: true)))
        defer { shortWindow.close() }
        let rep = try raster(short)
        let scroll = try scrollView(short)
        let b = box(scroll, in: short)
        XCTAssertGreaterThan(brightest(rep, b.insetBy(dx: 10, dy: 0)), 0.35)
        XCTAssertLessThanOrEqual(b.height, 20, "Single-line box \(b)")
        XCTAssertGreaterThan(b.height, 0)
        XCTAssertLessThan(b.height, 96)
        XCTAssertEqual(b.height, try XCTUnwrap(scroll.documentView).bounds.height, accuracy: 0.5)
        XCTAssertLessThan(brightest(rep, CGRect(x: b.minX + 10, y: b.maxY, width: b.width - 30, height: 6)), 0.1, "No dim band beneath the line")
        XCTAssertGreaterThanOrEqual(tallBox.maxY - b.maxY, 20, "Tall edge \(tallBox.maxY), short edge \(b.maxY)")
        XCTAssertLessThanOrEqual(tallBox.maxY - b.maxY, 96, "Tall edge \(tallBox.maxY), short edge \(b.maxY)")
        print("ODIN box edges tall=\(tallBox.maxY), short=\(b.maxY); heights tall=\(tallBox.height), short=\(b.height)")
        if let scroller = scroll.verticalScroller {
            print("ODIN short knobProportion=\(scroller.knobProportion), hidden=\(scroller.isHidden), alpha=\(scroller.alphaValue)")
            XCTAssertTrue(scroller.knobProportion <= 0.01 || scroller.isHidden || scroller.alphaValue == 0)
            XCTAssertLessThanOrEqual(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height + 0.5)
        } else { print("ODIN short scroller: none") }
        let shortProof = try proofImage(short, box: scroll, rep: rep, preview: "ODIN_PANE_SHORT_PREVIEW")
        XCTAssertEqual(shortProof.before, 0, "Indicator \(shortProof.before) -> \(shortProof.after)")
        XCTAssertEqual(shortProof.after, 0, "Indicator \(shortProof.before) -> \(shortProof.after)")
    }

    @MainActor func testANewDecisionStartsAtTheTopAgain() throws {
        let driver = PaneDriver(decision())
        let (view, window) = host(driver)
        defer { window.close() }
        let old = try scrollView(view)
        try scrollToEnd(view, old)
        try assertRows(old, rep: raster(view), host: view, atEnd: true)
        driver.decisions = [decision(replacement: true)]
        pump(0.6)
        let fresh = try scrollView(view)
        XCTAssertEqual(fresh.contentView.bounds.minY, 0, accuracy: 0.5)
        try assertRows(fresh, rep: raster(view), host: view, atEnd: false)
    }

    @MainActor func testTheBoxHeightRule() {
        for (content, expected): (CGFloat, CGFloat) in [(0, 96), (40, 40), (96, 96), (400, 96)] {
            XCTAssertEqual(OdinDecisionPaneMetrics.boxHeight(contentHeight: content), expected)
        }
        XCTAssertTrue(OdinDecisionPaneMetrics.moreBelow(offset: 0, boxHeight: 96, contentHeight: 400))
        XCTAssertFalse(OdinDecisionPaneMetrics.moreBelow(offset: 304, boxHeight: 96, contentHeight: 400))
        XCTAssertFalse(OdinDecisionPaneMetrics.moreBelow(offset: 0, boxHeight: 40, contentHeight: 40))
    }
}
