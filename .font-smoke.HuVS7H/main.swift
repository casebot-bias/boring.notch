import AppKit
import SwiftUI
let samples: [CGFloat] = [6, 11, 11.5, 12.5, 15]
for base in samples { print("base=\(base) rendered=\(FleetType.scaled(base))") }
let host = NSHostingView(rootView: Text("Fleet floor").font(FleetType.size(11)))
let measured = FleetType.monoWidth(text: "Fleet floor", size: 11)
let expectedSize = FleetPanelMetrics.minTextSize * FleetPanelMetrics.textScale
let expectedWidth = ("Fleet floor" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: expectedSize, weight: .regular)]).width
print("word-font hosting size=\(host.fittingSize); mono measured=\(measured), owner-floor reference=\(expectedWidth)")
let passes = abs(FleetType.scaled(6) - 10.12) < 0.001 && abs(FleetType.scaled(11) - 10.12) < 0.001 && abs(FleetType.scaled(11.5) - 10.58) < 0.001 && abs(measured - expectedWidth) < 0.001
print(passes ? "PASS: owner-selected 10.12pt drawn floor retained" : "FAIL: owner-selected font contract changed")
exit(passes ? 0 : 1)
