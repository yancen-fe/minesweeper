import AppKit

@MainActor enum FixedWindowSizing {
    static func unlock(_ window: NSWindow) {
        // Only programmatic difficulty transitions may change the frame.
        window.minSize = .zero
        window.maxSize = CGSize(width: 10000, height: 10000)
    }
    static func lock(_ window: NSWindow, frame: CGRect) {
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = frame.size
        window.maxSize = frame.size
    }
}
