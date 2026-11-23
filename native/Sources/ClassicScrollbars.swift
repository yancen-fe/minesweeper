import AppKit
import SwiftUI

/// Keep AppKit's scrolling, tracking and accessibility; only paint the classic surface.
final class ClassicScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 12 }
    override init(frame: NSRect) { super.init(frame: frame); focusRingType = .none; controlSize = .small }
    required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none; controlSize = .small }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        // Legacy text views otherwise paint a white system gutter behind the custom knob.
        drawKnobSlot(in: bounds, highlight: false)
        drawKnob()
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor(calibratedWhite: 0.79, alpha: 1).setFill()
        slotRect.fill()
        NSColor(calibratedWhite: 0.66, alpha: 1).setStroke()
        let edge = NSBezierPath()
        if bounds.height >= bounds.width {
            edge.move(to: NSPoint(x: slotRect.minX + 0.5, y: slotRect.minY)); edge.line(to: NSPoint(x: slotRect.minX + 0.5, y: slotRect.maxY))
        } else {
            edge.move(to: NSPoint(x: slotRect.minX, y: slotRect.maxY - 0.5)); edge.line(to: NSPoint(x: slotRect.maxX, y: slotRect.maxY - 0.5))
        }
        edge.lineWidth = 1; edge.stroke()
    }
    override func drawKnob() {
        let rect = rect(for: .knob).insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        NSColor(calibratedWhite: hitPart == .knob ? 0.67 : 0.75, alpha: 1).setFill(); rect.fill()
        let top = isFlipped ? rect.minY + 0.5 : rect.maxY - 0.5
        let bottom = isFlipped ? rect.maxY - 0.5 : rect.minY + 0.5
        let light = NSBezierPath(), dark = NSBezierPath()
        light.move(to: NSPoint(x: rect.minX + 0.5, y: bottom)); light.line(to: NSPoint(x: rect.minX + 0.5, y: top)); light.line(to: NSPoint(x: rect.maxX, y: top))
        dark.move(to: NSPoint(x: rect.maxX - 0.5, y: top)); dark.line(to: NSPoint(x: rect.maxX - 0.5, y: bottom)); dark.line(to: NSPoint(x: rect.minX, y: bottom))
        light.lineWidth = 1; dark.lineWidth = 1
        NSColor.white.setStroke(); light.stroke()
        NSColor(calibratedWhite: 0.48, alpha: 1).setStroke(); dark.stroke()
    }
    static func apply(to scrollView: NSScrollView) {
        if !(scrollView.verticalScroller is ClassicScroller) {
            scrollView.hasVerticalScroller = true
            scrollView.verticalScroller = ClassicScroller(frame: .zero)
        }
        if scrollView.scrollerStyle != .legacy { scrollView.scrollerStyle = .legacy }
        if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
    }
}

extension View {
    func classicScrollbars() -> some View {
        scrollIndicators(.visible).background(ClassicScrollProbe().accessibilityHidden(true))
    }
}

/// Match the scroll view underneath this modifier in this window only.
/// SwiftUI owns the content and offset throughout; no hosting view or scroll container is replaced.
private struct ClassicScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.schedule() }
    final class Probe: NSView {
        private var scheduled = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); schedule() }
        override func layout() { super.layout(); schedule() }
        func schedule() {
            guard !scheduled, window != nil else { return }; scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.scheduled = false
                guard self.bounds.width > 0, self.bounds.height > 0 else { return }
                let anchor = self.convert(self.bounds, to: nil)
                var ancestor = self.superview
                while let root = ancestor {
                    let matches = self.scrollViews(in: root).filter { candidate in
                        guard candidate.window === self.window else { return false }
                        let frame = candidate.convert(candidate.bounds, to: nil)
                        return frame.intersection(anchor).width >= min(frame.width, anchor.width) - 2
                            && frame.intersection(anchor).height >= min(frame.height, anchor.height) - 2
                            && abs(frame.midX - anchor.midX) < 3 && abs(frame.midY - anchor.midY) < 3
                    }
                    if let scroll = matches.first { ClassicScroller.apply(to: scroll); return }
                    ancestor = root.superview
                }
            }
        }
        private func scrollViews(in root: NSView) -> [NSScrollView] {
            if let scroll = root as? NSScrollView { return [scroll] }
            return root.subviews.flatMap { scrollViews(in: $0) }
        }
    }
}
