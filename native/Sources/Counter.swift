import AppKit
import SwiftUI

struct NativeCounter: NSViewRepresentable {
    let value: Int
    let title: String
    func makeNSView(context: Context) -> CounterSurface { CounterSurface() }
    func updateNSView(_ view: CounterSurface, context: Context) {
        view.setValue(value)
        view.setAccessibilityLabel(title == "用时" ? "用时 \(GameDuration.text(value))" : "\(title) \(value) 颗雷")
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CounterSurface, context: Context) -> CGSize? { CounterSurface.displaySize(for: value) }
}
final class CounterSurface: NSView {
    private var value = 0
    private static let segments = [[0,1,2,3,4,5], [1,2], [0,1,6,4,3], [0,1,2,3,6], [5,6,1,2], [0,5,6,2,3], [0,5,4,3,2,6], [0,1,2], [0,1,2,3,4,5,6], [0,1,2,3,5,6]]
    override var isOpaque: Bool { true }
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; clipsToBounds = true
        layer?.isOpaque = true; layer?.backgroundColor = NSColor.black.cgColor
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    convenience init() { self.init(frame: NSRect(x: 0, y: 0, width: 60, height: 34)) }
    required init?(coder: NSCoder) { nil }
    static func displaySize(for value: Int) -> CGSize {
        CGSize(width: 60 + max(0, digits(min(99999, max(0, value))).count - 3) * 18, height: 34)
    }
    override var intrinsicContentSize: NSSize { Self.displaySize(for: value) }
    func setValue(_ value: Int) {
        let clipped = min(99999, max(0, value))
        guard clipped != self.value else { return }
        let old = Self.digits(self.value), new = Self.digits(clipped)
        self.value = clipped
        if old.count != new.count { invalidateIntrinsicContentSize(); needsDisplay = true; return }
        for index in new.indices where old[index] != new[index] {
            setNeedsDisplay(NSRect(x: CGFloat(index) * 18 + 3, y: 0, width: 20, height: 34))
        }
    }
    private static func digits(_ value: Int) -> [Int] { String(repeating: "0", count: max(0, 3 - String(value).count)).appending(String(value)).compactMap { $0.wholeNumberValue } }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: dirtyRect.intersection(bounds)).addClip()
        NSColor.black.setFill(); dirtyRect.fill()
        NSGraphicsContext.current?.shouldAntialias = true
        let origins: [CGPoint] = [.init(x:1,y:0), .init(x:11,y:2), .init(x:11,y:14), .init(x:1,y:24), .init(x:0,y:14), .init(x:0,y:2), .init(x:1,y:12)]
        for (index, digit) in Self.digits(value).enumerated() {
            for segment in 0..<7 {
                let origin = origins[segment]
                let horizontal = [0,3,6].contains(segment)
                let rect = NSRect(x: origin.x + CGFloat(index) * 18 + 5, y: origin.y + 3,
                                  width: horizontal ? 12 : 3, height: horizontal ? 3 : 12)
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                (Self.segments[digit].contains(segment) ? NSColor(calibratedRed: 1, green: 0.03, blue: 0, alpha: 1) : NSColor(calibratedRed: 0.075, green: 0, blue: 0, alpha: 1)).setFill()
                path.fill()
            }
        }
    }
}
