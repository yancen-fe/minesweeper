import AppKit
import SwiftUI

enum Palette {
    static let paper = Color(white: 0.75)
    static let ink = Color(white: 0.05)
    static let muted = Color(white: 0.28)
    static let blue = Color(red: 0, green: 0, blue: 0.65)
    static let line = Color(white: 0.5)
    static let success = Color(red: 0, green: 0.35, blue: 0)
    static let danger = Color(red: 0.8, green: 0, blue: 0)
    static let bed = Color(white: 0.75)
}

struct BoardRenderState {
    let field: Minefield
    let blocked: Bool
}

struct NativeBoard: NSViewRepresentable {
    let field: Minefield
    let tileSize: CGFloat
    let blocked: Bool
    let animateChanges: Bool
    let revealOnPress: Bool
    let roundedNumbers: Bool
    let triangleFlags: Bool
    let smallFlags: Bool
    var flagImage: NSImage? = nil
    var mineImage: NSImage? = nil
    let hint: Int?
    let reveal: (Int) -> BoardRenderState
    let flag: (Int) -> BoardRenderState
    let pause: () -> Void
    func makeNSView(context: Context) -> BoardSurface { BoardSurface(field: field, tileSize: tileSize) }
    func updateNSView(_ view: BoardSurface, context: Context) {
        view.roundedNumbers = roundedNumbers; view.triangleFlags = triangleFlags; view.smallFlags = smallFlags
        view.revealOnPress = revealOnPress
        view.flagImage = flagImage; view.mineImage = mineImage
        view.onReveal = reveal; view.onFlag = flag; view.onPause = pause
        view.update(field: field, tileSize: tileSize, blocked: blocked, hint: hint, animateChanges: animateChanges)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BoardSurface, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.boardSize.width, height: proposal.height ?? nsView.boardSize.height)
    }
}

/// One native surface, synchronously repainted as a complete frame to keep resize and input updates coherent.
final class BoardSurface: NSView {
    private var field: Minefield
    private var blocked = false
    private var hint: Int?
    private var pressed: Int?
    private var dragging = false
    private var chorded = false
    private var focused = 0
    private var elements: [BoardCellElement] = []
    var roundedNumbers = true { didSet { if oldValue != roundedNumbers { needsDisplay = true } } }
    var triangleFlags = true { didSet { if oldValue != triangleFlags { needsDisplay = true } } }
    var smallFlags = true { didSet { if oldValue != smallFlags { needsDisplay = true } } }
    var flagImage: NSImage? { didSet { if oldValue !== flagImage { needsDisplay = true } } }
    var mineImage: NSImage? { didSet { if oldValue !== mineImage { needsDisplay = true } } }
    var revealOnPress = true
    var onReveal: ((Int) -> BoardRenderState)?
    var onFlag: ((Int) -> BoardRenderState)?
    var onPause: (() -> Void)?
    private let gap: CGFloat = BoardLayout.gap
    private var side: CGFloat
    var boardSize: CGSize {
        CGSize(width: CGFloat(field.difficulty.columns) * side + CGFloat(field.difficulty.columns - 1) * gap,
               height: CGFloat(field.difficulty.rows) * side + CGFloat(field.difficulty.rows - 1) * gap)
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    init(field: Minefield, tileSize: CGFloat) {
        self.field = field; self.side = tileSize
        _ = BoardTypography.registered
        super.init(frame: .zero)
        focusRingType = .none
        wantsLayer = true; clipsToBounds = true; layer?.masksToBounds = true
        layer?.isOpaque = true
        layer?.backgroundColor = NSColor(Palette.bed).cgColor
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("雷区")
        elements = field.cells.indices.map { BoardCellElement(board: self, index: $0) }
        setAccessibilityChildren(elements)
    }
    required init?(coder: NSCoder) { nil }
    func update(field: Minefield, tileSize: CGFloat, blocked: Bool, hint: Int?, animateChanges: Bool = false) {
        let gridChanged = self.field.difficulty != field.difficulty
        let resized = side != tileSize || gridChanged
        let endedChanged = self.field.ended != field.ended
        let interactionChanged = self.blocked != blocked
        let oldPressed = pressed, oldHint = self.hint
        var changed: [Int] = []
        if !resized {
            changed = field.cells.indices.filter { i in
                let old = self.field.cells[i], new = field.cells[i]
                return old.open != new.open || old.mark != new.mark || (new.open && old.number != new.number)
            }
        }
        self.field = field; self.hint = hint; self.side = tileSize
        if gridChanged {
            if animateChanges && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let transition = CATransition()
                transition.type = .fade; transition.duration = 0.14
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer?.add(transition, forKey: "difficulty-change")
            }
            dragging = false; pressed = nil; chorded = false; focused = 0
            elements = field.cells.indices.map { BoardCellElement(board: self, index: $0) }
            setAccessibilityChildren(elements)
        } else if interactionChanged {
            dragging = false; pressed = nil
        }
        self.blocked = blocked
        if interactionChanged || resized || endedChanged {
            for element in elements { element.setAccessibilityEnabled(!blocked && !field.ended) }
        }
        if resized || endedChanged {
            needsDisplay = true
        } else {
            if !changed.isEmpty { needsDisplay = true }
            if oldPressed != pressed { invalidate(oldPressed); invalidate(pressed) }
            if oldHint != hint { invalidate(oldHint); invalidate(hint) }
        }
    }
    private func applyReveal(_ index: Int) {
        guard let state = onReveal?(index) else { return }
        // Keep unopened tiles raised while the verified board is generated.
        update(field: state.field, tileSize: side, blocked: state.blocked, hint: nil)
        displayIfNeeded()
    }
    private func applyFlag(_ index: Int) {
        guard let state = onFlag?(index) else { return }
        update(field: state.field, tileSize: side, blocked: state.blocked, hint: nil)
        displayIfNeeded()
    }
    private var cellSize: CGSize {
        CGSize(width: bounds.width > 0 ? bounds.width / CGFloat(field.difficulty.columns) : side,
               height: bounds.height > 0 ? bounds.height / CGFloat(field.difficulty.rows) : side)
    }
    func rect(for index: Int) -> NSRect {
        NSRect(x: CGFloat(index % field.difficulty.columns) * cellSize.width, y: CGFloat(index / field.difficulty.columns) * cellSize.height, width: cellSize.width, height: cellSize.height)
    }
    private func index(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return nil }
        let column = Int(point.x / cellSize.width), row = Int(point.y / cellSize.height)
        guard row < field.difficulty.rows, column < field.difficulty.columns else { return nil }
        // Gaps belong to the closest tile, avoiding tiny dead zones between cells.
        return row * field.difficulty.columns + column
    }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }
    private func invalidate(_ index: Int?) {
        guard let index, field.cells.indices.contains(index) else { return }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard !blocked, !field.ended, let index = index(at: event) else { return }
        window?.makeFirstResponder(self)
        invalidate(focused); focused = index
        if event.modifierFlags.contains(.control) { applyFlag(index); return }
        chorded = false
        if revealOnPress {
            dragging = false; pressed = nil
            applyReveal(index)
        } else {
            dragging = true; pressed = index; invalidate(index)
            displayIfNeeded()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging, !blocked else { return }
        let next = index(at: event)
        if pressed != next { invalidate(pressed); pressed = next; invalidate(pressed) }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        let target = index(at: event)
        invalidate(pressed); pressed = nil; dragging = false
        if !blocked, !chorded, let target { applyReveal(target) }
        chorded = false
    }
    override func rightMouseDown(with event: NSEvent) {
        guard !blocked, !field.ended, let index = index(at: event) else { return }
        if dragging {
            chorded = true
            if field.cells[index].open { applyReveal(index) }
        } else { applyFlag(index) }
    }
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, !blocked, let index = index(at: event), field.cells[index].open else { return }
        applyReveal(index)
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "p" { onPause?(); return }
        guard !blocked else { return }
        let offsets: [UInt16: Int] = [123: -1, 124: 1, 125: field.difficulty.columns, 126: -field.difficulty.columns]
        if let offset = offsets[event.keyCode] {
            let next = focused + offset
            guard field.cells.indices.contains(next), abs(offset) != 1 || next / field.difficulty.columns == focused / field.difficulty.columns else { return }
            invalidate(focused); focused = next; invalidate(focused)
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f": applyFlag(focused)
        case " ", "\r": applyReveal(focused)
        default: super.keyDown(with: event)
        }
    }
    override func becomeFirstResponder() -> Bool { invalidate(focused); return true }
    override func resignFirstResponder() -> Bool { invalidate(focused); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor(Palette.bed).setFill(); bounds.fill()
        for index in field.cells.indices { drawCell(index) }
    }
    private var tileFont: NSFont {
        BoardTypography.font(size: side * 0.76, rounded: roundedNumbers)
    }
    private func drawCell(_ index: Int) {
        let cell = field.cells[index], rect = rect(for: index)
        let mine = field.ended && cell.mine, wrong = field.ended && cell.flagged && !cell.mine
        let adjacentPress = pressed.map { field.cells[$0].open && field.adjacency[$0].contains(index) && !cell.open && !cell.flagged } ?? false
        let down = !cell.flagged && (pressed == index || adjacentPress)
        let flat = cell.open || mine || down
        let background: NSColor = field.exploded == index ? .red : NSColor(calibratedWhite: 0.75, alpha: 1)
        background.setFill(); rect.fill()
        if flat {
            NSColor(calibratedWhite: 0.5, alpha: 1).setStroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.65
            grid.move(to: NSPoint(x: rect.minX + 0.35, y: rect.maxY)); grid.line(to: NSPoint(x: rect.minX + 0.35, y: rect.minY + 0.35)); grid.line(to: NSPoint(x: rect.maxX, y: rect.minY + 0.35)); grid.stroke()
        } else {
            let t: CGFloat = side >= 30 ? 2.5 : 2
            NSColor.white.setFill()
            let light = NSBezierPath()
            light.move(to: rect.origin)
            light.line(to: NSPoint(x: rect.maxX, y: rect.minY)); light.line(to: NSPoint(x: rect.maxX-t, y: rect.minY+t))
            light.line(to: NSPoint(x: rect.minX+t, y: rect.minY+t)); light.line(to: NSPoint(x: rect.minX+t, y: rect.maxY-t))
            light.line(to: NSPoint(x: rect.minX, y: rect.maxY)); light.close(); light.fill()
            NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
            let dark = NSBezierPath()
            dark.move(to: NSPoint(x: rect.maxX, y: rect.minY)); dark.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            dark.line(to: NSPoint(x: rect.minX, y: rect.maxY)); dark.line(to: NSPoint(x: rect.minX+t, y: rect.maxY-t))
            dark.line(to: NSPoint(x: rect.maxX-t, y: rect.maxY-t)); dark.line(to: NSPoint(x: rect.maxX-t, y: rect.minY+t)); dark.close(); dark.fill()
        }
        if cell.flagged {
            if let flagImage {
                drawIcon(flagImage, in: rect, fraction: smallFlags ? 0.55 : 0.72)
            } else {
            // Snap every edge to backing pixels so the pennant stays crisp at any window size.
            let scale = window?.backingScaleFactor ?? 2
            let unit = side * (smallFlags ? 0.55 : 0.72) / 16
            let ox = rect.midX - 8 * unit, oy = rect.midY - 8 * unit
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: ((ox + x * unit) * scale).rounded() / scale,
                        y: ((oy + y * unit) * scale).rounded() / scale)
            }
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                let a = point(x, y), b = point(x+w, y+h)
                NSRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y).fill()
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.shouldAntialias = false
            NSColor.black.setFill()
            block(9, 1, 2, 12); block(6, 12, 7, 2); block(3, 14, 12, 2)
            NSColor(calibratedRed: 0.88, green: 0.05, blue: 0.06, alpha: 1).setFill()
            NSGraphicsContext.current?.shouldAntialias = true
            let pennant = NSBezierPath()
            pennant.move(to: point(9, 1))
            if triangleFlags {
                pennant.line(to: point(2, 5)); pennant.line(to: point(9, 9))
            } else {
                pennant.line(to: point(2, 3)); pennant.line(to: point(2, 8)); pennant.line(to: point(9, 6))
            }
            pennant.close(); pennant.fill()
            NSGraphicsContext.restoreGraphicsState()
            }
        } else if mine {
            if let mineImage {
                drawIcon(mineImage, in: rect, fraction: 0.72)
            } else {
            let radius = side * 0.245, center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)).fill()
            NSColor.black.setStroke(); let rays = NSBezierPath(); rays.lineWidth = max(1.5, side * 0.075)
            rays.lineCapStyle = .round; rays.lineJoinStyle = .round
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                rays.move(to: NSPoint(x: center.x+cos(angle)*radius*0.84, y: center.y+sin(angle)*radius*0.84))
                rays.line(to: NSPoint(x: center.x+cos(angle)*side*0.31, y: center.y+sin(angle)*side*0.31))
            }
            rays.stroke(); NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x-radius*0.57, y: center.y-radius*0.62, width: radius*0.48, height: radius*0.40)).fill()
            }
        } else if cell.questioned && !cell.open {
            BoardTypography.draw("?", in: rect, font: tileFont, color: .black)
        } else if cell.open && cell.number > 0 {
            let colors: [NSColor] = [.black, .init(calibratedRed:0.12,green:0,blue:1,alpha:1), .init(calibratedRed:0,green:0.5,blue:0,alpha:1), .red, .init(calibratedRed:0,green:0,blue:0.5,alpha:1), .init(calibratedRed:0.5,green:0,blue:0,alpha:1), .init(calibratedRed:0,green:0.5,blue:0.5,alpha:1), .black, .darkGray]
            BoardTypography.draw(String(cell.number), in: rect, font: tileFont, color: colors[cell.number])
        }
        if wrong {
            NSColor.red.setStroke(); let cross = NSBezierPath(); cross.lineWidth = 2
            cross.move(to: NSPoint(x: rect.minX+4, y: rect.minY+4)); cross.line(to: NSPoint(x: rect.maxX-4, y: rect.maxY-4))
            cross.move(to: NSPoint(x: rect.minX+4, y: rect.maxY-4)); cross.line(to: NSPoint(x: rect.maxX-4, y: rect.minY+4)); cross.stroke()
        }

    }
    private func drawIcon(_ image: NSImage, in rect: NSRect, fraction: CGFloat) {
        let scale = side * fraction / max(image.size.width, image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    func cellLabel(_ index: Int) -> String {
        let cell = field.cells[index]
        let text = field.ended && cell.flagged && !cell.mine ? "插旗错误，这里没有雷" : cell.flagged ? "已插旗" : field.ended && cell.mine ? "地雷" : cell.questioned ? "可疑，问号标记" : cell.open ? cell.number > 0 ? "周围 \(cell.number) 颗雷" : "空白" : "未翻开"
        return "第 \(index / field.difficulty.columns + 1) 行，第 \(index % field.difficulty.columns + 1) 列，\(text)"
    }
    func cellFrame(_ index: Int) -> NSRect { window?.convertToScreen(convert(rect(for: index), to: nil)) ?? .zero }
    func accessibleReveal(_ index: Int) -> Bool {
        guard !blocked else { return false }
        focused = index; applyReveal(index); return true
    }
    func accessibleFlag(_ index: Int) -> Bool {
        guard !blocked else { return false }
        applyFlag(index); return true
    }
}
final class BoardCellElement: NSAccessibilityElement {
    weak var board: BoardSurface?
    let index: Int
    init(board: BoardSurface, index: Int) {
        self.board = board; self.index = index
        super.init()
        setAccessibilityRole(.button); setAccessibilityParent(board); setAccessibilityEnabled(true)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "切换标记", handler: { [weak board] in MainActor.assumeIsolated { board?.accessibleFlag(index) ?? false } })])
    }
    override func accessibilityLabel() -> String? {
        let board = board, index = index
        return MainActor.assumeIsolated { board?.cellLabel(index) }
    }
    override func accessibilityFrame() -> NSRect {
        let board = board, index = index
        return MainActor.assumeIsolated { board?.cellFrame(index) ?? .zero }
    }
    override func accessibilityPerformPress() -> Bool {
        let board = board, index = index
        return MainActor.assumeIsolated { board?.accessibleReveal(index) ?? false }
    }
}
