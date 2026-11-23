import AppKit
import Foundation

@main struct RenderingChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            if !value() { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); fatalError(message) }
        }
        func bitmap(_ size: CGSize) -> NSBitmapImageRep {
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32)!
        }
        func paint(_ view: NSView, into image: NSBitmapImageRep, damage: CGRect? = nil) {
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: image)!.cgContext
            context.translateBy(x: 0, y: CGFloat(image.pixelsHigh)); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            view.draw(damage ?? view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        func cellPixels(_ image: NSBitmapImageRep, rect: CGRect) -> Data {
            var data = Data()
            for y in Int(rect.minY)..<Int(rect.maxY) {
                data.append(image.bitmapData!.advanced(by: y * image.bytesPerRow + Int(rect.minX) * 4), count: Int(rect.width) * 4)
            }
            return data
        }
        func bytes(_ image: NSBitmapImageRep) -> Data { Data(bytes: image.bitmapData!, count: image.bytesPerRow * image.pixelsHigh) }
        let fixedWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        for target in [CGRect(x: 0, y: 0, width: 360, height: 500), CGRect(x: 0, y: 0, width: 940, height: 660), CGRect(x: 0, y: 0, width: 520, height: 660), CGRect(x: 0, y: 0, width: 360, height: 500)] {
            FixedWindowSizing.unlock(fixedWindow)
            fixedWindow.setFrame(target, display: false)
            FixedWindowSizing.lock(fixedWindow, frame: target)
            check(fixedWindow.minSize == target.size && fixedWindow.maxSize == target.size, "Each mode locks its exact frame after expansion or shrink")
            check(!fixedWindow.styleMask.contains(.resizable), "Manual window resizing is disabled")
            check(fixedWindow.collectionBehavior.contains(.fullScreenNone), "Fixed-size modes do not enter full screen")
            check(fixedWindow.standardWindowButton(.zoomButton)?.isEnabled != true, "Window zoom is disabled")
        }
        var field = Minefield(.easy)
        let view = BoardSurface(field: field, tileSize: 28)
        view.frame = CGRect(origin: .zero, size: view.boardSize)
        check(BoardTypography.font(size: 20, rounded: true).fontName == "Fredoka-SemiBold", "Bundled reference rounded font is registered without fallback")
        let canvas = bitmap(view.boardSize)
        paint(view, into: canvas)
        let before = bytes(canvas)
        field.flag(0)
        view.update(field: field, tileSize: 28, blocked: false, hint: nil)
        paint(view, into: canvas, damage: view.rect(for: 0))
        let flagged = bytes(canvas)
        check(before != flagged, "Flag changes the requested cell")
        for y in 0..<canvas.pixelsHigh {
            for x in 28..<canvas.pixelsWide {
                let offset = y * canvas.bytesPerRow + x * 4
                check(before[offset..<offset+4] == flagged[offset..<offset+4], "Partial redraw must not erase neighboring cells")
            }
        }
        let complete = bitmap(view.boardSize); paint(view, into: complete)
        check(bytes(complete) == flagged, "Partial redraw equals a complete redraw")
        view.update(field: field, tileSize: 28, blocked: true, hint: nil)
        let paused = bitmap(view.boardSize); paint(view, into: paused)
        check(bytes(paused) == flagged, "Paused board retains exactly the same visible pixels")
        let frozen = field.cells
        view.onReveal = { _ in fatalError("Paused input reached model") }
        view.onFlag = { _ in fatalError("Paused flag reached model") }
        check(!view.accessibleReveal(1) && !view.accessibleFlag(1), "Pause blocks both actions")
        check(field.cells == frozen, "Paused board is unchanged")
        view.update(field: field, tileSize: 28, blocked: false, hint: nil)
        let resumed = bitmap(view.boardSize); paint(view, into: resumed)
        check(bytes(resumed) == flagged, "Resume does not blank the board")
        field.flag(0)
        view.update(field: field, tileSize: 28, blocked: false, hint: nil)
        let questioned = bitmap(view.boardSize); paint(view, into: questioned)
        check(bytes(questioned) != flagged, "Question mark replaces the flag visually")
        check(view.cellLabel(0).contains("问号"), "Question mark has an accessible label")
        field.flag(0)
        view.update(field: field, tileSize: 28, blocked: false, hint: nil)
        let unmarked = bitmap(view.boardSize); paint(view, into: unmarked)
        check(bytes(unmarked) == before, "Third right click restores the unmarked cell")
        let identity = ObjectIdentifier(view)
        for level in [Difficulty.hard, .easy, .medium, .hard, .easy] {
            view.update(field: Minefield(level), tileSize: 24, blocked: false, hint: nil)
            view.frame.size = view.boardSize
            check(ObjectIdentifier(view) == identity, "Difficulty switch reuses the drawing surface")
            check(view.accessibilityChildren()?.count == level.rows * level.columns, "Accessible cells match the new difficulty")
            let image = bitmap(view.boardSize); paint(view, into: image)
            check(bytes(image).contains(where: { $0 != 0 }), "New board is rendered")
        }
        // Exercise native handlers without posting input to the user's desktop.
        var inputField = Minefield(.easy)
        let input = BoardSurface(field: inputField, tileSize: 28)
        input.frame.size = input.boardSize
        var reveals: [Int] = [], marks = 0
        input.onReveal = { index in
            reveals.append(index); inputField.cells[index].open = true
            return BoardRenderState(field: inputField, blocked: false)
        }
        input.onFlag = { index in
            marks += 1; inputField.flag(index)
            return BoardRenderState(field: inputField, blocked: false)
        }
        func event(_ type: NSEvent.EventType, x: CGFloat = 14, y: CGFloat = 14, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: input.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: modifiers,
                               timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        input.mouseDown(with: event(.leftMouseDown))
        check(reveals.count == 1, "Default input reveals during mouse down")
        input.mouseUp(with: event(.leftMouseUp))
        check(reveals.count == 1, "Mouse up never repeats an immediate reveal")
        input.revealOnPress = false
        input.mouseDown(with: event(.leftMouseDown, x: 42))
        check(reveals.count == 1, "Release setting waits while mouse is held")
        input.mouseDragged(with: event(.leftMouseDragged, x: 70))
        input.mouseUp(with: event(.leftMouseUp, x: 70))
        check(reveals == [0, 2], "Release setting opens the tile under release after dragging")
        input.mouseDown(with: event(.leftMouseDown, x: 42))
        input.mouseUp(with: event(.leftMouseUp, x: -10))
        check(reveals.count == 2, "Dragging outside cancels in release mode")
        input.revealOnPress = true
        input.rightMouseDown(with: event(.rightMouseDown, x: 42))
        check(marks == 1 && input.cellLabel(1).contains("已插旗"), "Right press places a flag immediately")
        input.mouseDown(with: event(.leftMouseDown, x: 42, modifiers: .control))
        input.mouseUp(with: event(.leftMouseUp, x: 42))
        check(marks == 2 && reveals.count == 2 && input.cellLabel(1).contains("问号"), "Control click marks without a later reveal")
        input.update(field: inputField, tileSize: 28, blocked: true, hint: nil)
        input.mouseDown(with: event(.leftMouseDown)); input.rightMouseDown(with: event(.rightMouseDown))
        check(reveals.count == 2 && marks == 2, "Paused board blocks both mouse-down actions")
        var optionsField = Minefield(.easy)
        optionsField.cells[0].open = true; optionsField.cells[0].number = 2; optionsField.flag(1)
        let optionsView = BoardSurface(field: optionsField, tileSize: 28)
        optionsView.frame.size = optionsView.boardSize
        let defaultsImage = bitmap(optionsView.boardSize); paint(optionsView, into: defaultsImage)
        let defaultsBytes = bytes(defaultsImage)
        optionsView.smallFlags = false
        let largeFlagImage = bitmap(optionsView.boardSize); paint(optionsView, into: largeFlagImage)
        check(bytes(largeFlagImage) != defaultsBytes, "Flag size preference updates the rendered flag")
        optionsView.triangleFlags = false
        let squareFlagImage = bitmap(optionsView.boardSize); paint(optionsView, into: squareFlagImage)
        check(bytes(squareFlagImage) != bytes(largeFlagImage), "Flag shape preference changes the pennant")
        optionsView.roundedNumbers = false
        let classicNumberImage = bitmap(optionsView.boardSize); paint(optionsView, into: classicNumberImage)
        check(bytes(classicNumberImage) != bytes(squareFlagImage), "Number preference switches between rounded font and classic font")
        optionsView.smallFlags = true; optionsView.triangleFlags = true; optionsView.roundedNumbers = true
        let restoredOptions = bitmap(optionsView.boardSize); paint(optionsView, into: restoredOptions)
        check(bytes(restoredOptions) == defaultsBytes, "Returning to defaults restores the same board without restarting the game")
        check(optionsView.cellLabel(1).contains("已插旗"), "Appearance preferences preserve the flagged cell")
        let custom = NSImage(size: NSSize(width: 24, height: 12), flipped: true) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        optionsView.flagImage = custom
        let customFlag = bitmap(optionsView.boardSize); paint(optionsView, into: customFlag)
        check(bytes(customFlag) != defaultsBytes, "Custom flag replaces the built-in pennant")
        optionsView.flagImage = nil
        let resetFlag = bitmap(optionsView.boardSize); paint(optionsView, into: resetFlag)
        check(bytes(resetFlag) == defaultsBytes, "Resetting a custom flag restores exact default pixels")
        optionsField.phase = .lost; optionsField.cells[2].mine = true
        optionsView.update(field: optionsField, tileSize: 28, blocked: false, hint: nil)
        let defaultMine = bitmap(optionsView.boardSize); paint(optionsView, into: defaultMine)
        optionsView.mineImage = custom
        let customMine = bitmap(optionsView.boardSize); paint(optionsView, into: customMine)
        check(bytes(defaultMine) != bytes(customMine), "Custom mine is rendered after a loss")
        check(cellPixels(defaultMine, rect: optionsView.rect(for: 1)) == cellPixels(customMine, rect: optionsView.rect(for: 1)), "Wrong flags never render the mine icon")
        check(optionsView.cellLabel(1).contains("这里没有雷"), "Wrong flag accessibility explicitly identifies a safe cell")
        optionsView.flagImage = custom
        let wrongCustomFlag = bitmap(optionsView.boardSize); paint(optionsView, into: wrongCustomFlag)
        check(cellPixels(customMine, rect: optionsView.rect(for: 1)) != cellPixels(wrongCustomFlag, rect: optionsView.rect(for: 1)), "Wrong flags retain the selected flag icon with a cross")
        optionsView.flagImage = nil
        optionsView.mineImage = nil
        let resetMine = bitmap(optionsView.boardSize); paint(optionsView, into: resetMine)
        check(bytes(resetMine) == bytes(defaultMine), "Resetting a mine restores default rendering including wrong-flag crosses")
        let counter = CounterSurface()
        counter.setValue(98)
        let oldCounter = bitmap(counter.bounds.size); paint(counter, into: oldCounter)
        counter.setValue(99)
        let newCounter = bitmap(counter.bounds.size); paint(counter, into: newCounter)
        let oldBytes = bytes(oldCounter), newBytes = bytes(newCounter)
        check(oldBytes != newBytes, "Counter changes when the value changes")
        for y in 0..<34 {
            for x in 0..<40 {
                let offset = y * oldCounter.bytesPerRow + x * 4
                check(oldBytes[offset..<offset+4] == newBytes[offset..<offset+4], "Unchanged counter digits remain stable")
            }
        }
        for (value, width) in [(999, 60), (1000, 78), (9999, 78), (10000, 96), (99999, 96), (100000, 96), (0, 60)] {
            counter.setValue(value)
            check(counter.intrinsicContentSize.width == CGFloat(width), "Counter expands to at most five digits and resets")
            counter.frame.size = counter.intrinsicContentSize
            let image = bitmap(counter.bounds.size); paint(counter, into: image)
            check(bytes(image).contains(where: { $0 > 100 }), "Expanded digits are actually rendered")
        }
        counter.setValue(100000); counter.frame.size = counter.intrinsicContentSize
        let capped = bitmap(counter.bounds.size); paint(counter, into: capped)
        counter.setValue(99999)
        let maxCounter = bitmap(counter.bounds.size); paint(counter, into: maxCounter)
        check(bytes(capped) == bytes(maxCounter), "Five-digit display caps at 99999")
        let waiting = BoardSurface(field: Minefield(.easy), tileSize: 28)
        waiting.frame.size = waiting.boardSize
        let unopened = bitmap(waiting.bounds.size); paint(waiting, into: unopened)
        waiting.onReveal = { _ in BoardRenderState(field: Minefield(.easy), blocked: true) }
        check(waiting.accessibleReveal(0), "First reveal requests generation")
        let generating = bitmap(waiting.bounds.size); paint(waiting, into: generating)
        check(bytes(unopened) == bytes(generating), "Generation never displays a blank pressed tile")
        input.frame.size = CGSize(width: 378, height: 225)
        input.update(field: inputField, tileSize: 25, blocked: false, hint: nil)
        check(input.rect(for: 80).maxX == 378 && input.rect(for: 80).maxY == 225, "Scaled grid reaches every edge of its container")
        input.rightMouseDown(with: event(.rightMouseDown, x: 377, y: 224))
        check(input.cellLabel(80).contains("已插旗"), "Scaled bottom-right tile remains clickable")
        var expert = Minefield(.hard); expert.reveal(255)
        view.update(field: expert, tileSize: 28, blocked: false, hint: nil)
        view.frame.size = view.boardSize
        let expertImage = bitmap(view.boardSize)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<40 { paint(view, into: expertImage) }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) / 40 * 1000
        print("Expert complete-frame repaint average: \(milliseconds) ms")
        print("PASS: \(assertions) rendering checks — coherent repaint, visible pause/resume, persistent board surface, and stable counter digits")
    }
}
