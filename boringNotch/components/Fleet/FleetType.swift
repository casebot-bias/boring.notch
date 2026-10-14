import AppKit
import CoreText
import SwiftUI

/// The Fleet panel's type: SF Pro for words, JetBrains Mono for data. The three bundled faces are
/// registered once per process; if that fails the views fall back to the system monospaced font and
/// say so in one log line.
enum FleetType {
    enum Weight { case regular, medium, bold }

    private static let bundledFaces = ["JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"]

    /// Memoised result of the one-time registration. `nil` until `registerBundledFonts` has run.
    private static var registered: Bool?
    private static var loggedFallback = false

    /// Registers `JetBrainsMono-{Regular,Medium,Bold}.ttf` from the given bundle (looked up in the
    /// bundle root and in a `Fonts` subdirectory), once per process. Returns true when the regular
    /// face is available afterwards.
    @discardableResult
    static func registerBundledFonts(in bundle: Bundle = .main) -> Bool {
        if let cached = registered { return cached }

        for face in bundledFaces {
            guard let url = bundle.url(forResource: face, withExtension: "ttf")
                ?? bundle.url(forResource: face, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            // "Already registered" is expected on re-launch paths and is deliberately ignored.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            error?.release()
        }

        let available = NSFont(name: postScriptName(for: .regular), size: 11) != nil
        registered = available
        return available
    }

    /// The data font at `size`: JetBrains Mono when registered, otherwise the system monospaced font.
    static func mono(size: CGFloat, weight: Weight = .regular) -> Font {
        if registerBundledFonts(), NSFont(name: postScriptName(for: weight), size: size) != nil {
            return .custom(postScriptName(for: weight), size: size)
        }
        logFallbackOnce()
        return .system(size: size, weight: fontWeight(weight), design: .monospaced)
    }

    /// The PostScript name `mono(size:)` resolves to: "JetBrainsMono-Regular"/"-Medium"/"-Bold"
    /// when registered, otherwise the system monospaced font's name. Tests pin the regular name.
    static var resolvedMonoPostScriptName: String {
        registerBundledFonts()
            ? postScriptName(for: .regular)
            : NSFont.monospacedSystemFont(ofSize: 11, weight: .regular).fontName
    }

    /// True when registration failed and the system monospaced font is in use.
    static var didFallBack: Bool {
        !registerBundledFonts()
    }

    /// The rendered width of `text` at `size`: the closed row measures its speed reading against
    /// this, so the fit rule matches what the view renders. Same face as `mono(size:weight:)`.
    static func monoWidth(text: String, size: CGFloat, weight: Weight = .regular) -> CGFloat {
        let font: NSFont
        if registerBundledFonts(), let face = NSFont(name: postScriptName(for: weight), size: size) {
            font = face
        } else {
            logFallbackOnce()
            font = NSFont.monospacedSystemFont(ofSize: size, weight: nsFontWeight(weight))
        }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func postScriptName(for weight: Weight) -> String {
        switch weight {
        case .regular: return "JetBrainsMono-Regular"
        case .medium: return "JetBrainsMono-Medium"
        case .bold: return "JetBrainsMono-Bold"
        }
    }

    private static func fontWeight(_ weight: Weight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .bold: return .bold
        }
    }

    private static func nsFontWeight(_ weight: Weight) -> NSFont.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .bold: return .bold
        }
    }

    private static func logFallbackOnce() {
        guard !loggedFallback else { return }
        loggedFallback = true
        NSLog("[fleet] JetBrains Mono unavailable, falling back to the system monospaced font")
    }
}
