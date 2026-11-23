import AppKit
import CoreText

/// A real rounded typeface; the font data and OFL license ship with the app.
@MainActor enum BoardTypography {
    static let registered: Bool = {
        let bundled = Bundle.main.url(forResource: "Fredoka", withExtension: "ttf", subdirectory: "Fonts")
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/Fonts/Fredoka.ttf")
        return CTFontManagerRegisterFontsForURL((bundled ?? development) as CFURL, .process, nil)
    }()
    static func font(size: CGFloat, rounded: Bool) -> NSFont {
        if rounded {
            _ = registered
            if let font = NSFont(name: "Fredoka-SemiBold", size: size) { return font }
            if let font = NSFont(name: "ArialRoundedMTBold", size: size) { return font }
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }
    static func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let text = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX - ink.midX, y: rect.midY + ink.midY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity; context.textPosition = .zero
        CTLineDraw(line, context)
    }
}
