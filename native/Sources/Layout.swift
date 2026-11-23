import Foundation
import CoreGraphics

struct BoardLayout {
    static let gap: CGFloat = 0
    let tile: CGFloat
    let size: CGSize
    init(difficulty: Difficulty, viewport: CGSize) {
        let width = max(1, viewport.width - 4), height = max(1, viewport.height - 4)
        let columns = CGFloat(difficulty.columns), rows = CGFloat(difficulty.rows)
        tile = min(width / columns, height / rows)
        size = CGSize(width: width, height: height)
    }
}
struct GameWindowLayout {
    static func minimumContentSize(for difficulty: Difficulty) -> CGSize {
        // A readable board and the two fixed control rows must fit without scrolling.
        CGSize(width: max(300, difficulty.columns * 20 + 40), height: difficulty.rows * 20 + 158)
    }
    static func frame(difficulty: Difficulty, current: CGRect, visible: CGRect) -> CGRect {
        let preferred: CGSize
        switch difficulty {
        case .easy: preferred = CGSize(width: 360, height: 500)
        case .medium: preferred = CGSize(width: 520, height: 660)
        case .hard: preferred = CGSize(width: 940, height: 660)
        }
        let area = visible.insetBy(dx: 12, dy: 12)
        let size = CGSize(width: min(preferred.width, area.width), height: min(preferred.height, area.height))
        let x = min(max(current.midX - size.width / 2, area.minX), area.maxX - size.width)
        let y = min(max(current.maxY - size.height, area.minY), area.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
