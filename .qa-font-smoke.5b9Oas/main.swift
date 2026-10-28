import AppKit
import SwiftUI
let samples: [(CGFloat, CGFloat)] = [(6, 11), (11, 11), (11.5, 11), (12.5, 11.5), (15, 13.8)]
for (base, expected) in samples { print("base=\(base) rendered=\(FleetType.scaled(base)) expected=\(expected)") }
let host = NSHostingView(rootView: Text("Fleet floor").font(FleetType.size(11)))
let measured = FleetType.monoWidth(text: "Fleet floor", size: 11)
let font = NSFont(name: "JetBrainsMono-Regular", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
let expectedWidth = ("Fleet floor" as NSString).size(withAttributes: [.font: font]).width
print("word-font hosting size=\(host.fittingSize); mono measured=\(measured), 11pt reference=\(expectedWidth)")
let passes = samples.allSatisfy { abs(FleetType.scaled($0.0) - $0.1) < 0.0001 } && abs(measured - expectedWidth) < 0.0001
print(passes ? "PASS: QA rendered floor is 11pt and measurement matches" : "FAIL: QA rendered-floor contract violated")
exit(passes ? 0 : 1)
