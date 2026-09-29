import AppKit
import QuartzCore

/// Small dot on a screen edge showing where he will land on release.
final class IndicatorWindow: NSPanel {
    private static let diameter: CGFloat = 10

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let dot = CALayer()
        dot.frame = NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        dot.cornerRadius = Self.diameter / 2
        dot.backgroundColor = SpriteView.webColor
        dot.borderColor = CGColor(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1)
        dot.borderWidth = 2
        let view = NSView()
        view.layer = CALayer()
        view.wantsLayer = true
        view.layer?.addSublayer(dot)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the dot at `point` on an edge of `screen`, nudged inside so it touches that edge.
    func show(at point: NSPoint, on screen: NSScreen) {
        let f = screen.frame, r = Self.diameter / 2
        let x = min(max(point.x, f.minX + r), f.maxX - r)
        let y = min(max(point.y, f.minY + r), f.maxY - r)
        setFrameOrigin(NSPoint(x: (x - r).rounded(), y: (y - r).rounded()))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
