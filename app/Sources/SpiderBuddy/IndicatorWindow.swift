import AppKit
import QuartzCore

/// Small dot on the screen's top edge showing where the web will attach on release.
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

    /// Centres the dot horizontally on `x`, touching the top edge of `screen`.
    func show(x: CGFloat, on screen: NSScreen) {
        setFrameOrigin(NSPoint(x: (x - Self.diameter / 2).rounded(), y: screen.frame.maxY - Self.diameter))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
