import AppKit
import QuartzCore

/// Draws one sprite frame with crisp scaled pixels, plus an optional web line
/// running from the top of the view down to the frame's web anchor.
/// Layout is in AppKit's native bottom-up coordinates: sprite at the bottom, web above it.
final class SpriteView: NSView {
    static let webColor = CGColor(red: 0xDE / 255, green: 0xDE / 255, blue: 0xDE / 255, alpha: 1)

    var scale: CGFloat
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private let spriteLayer = CALayer()
    private let webLayer = CALayer()
    private(set) var sprite: Sprite?

    init(scale: CGFloat) {
        self.scale = scale
        super.init(frame: .zero)
        let root = CALayer()
        layer = root
        wantsLayer = true
        spriteLayer.magnificationFilter = .nearest
        webLayer.backgroundColor = Self.webColor
        root.addSublayer(webLayer)
        root.addSublayer(spriteLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Size in points the view needs for this frame with `webHeight` points of web above it.
    func size(for sprite: Sprite, webHeight: CGFloat) -> CGSize {
        CGSize(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale + webHeight)
    }

    /// Shows `sprite` at the bottom of the view with a web line of `webHeight` points
    /// running from the view's top edge down to the sprite's web anchor column.
    func show(_ sprite: Sprite, webHeight: CGFloat, anchorX: Int) {
        self.sprite = sprite
        let spriteSize = CGSize(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit fades between frames
        spriteLayer.contents = sprite.image
        spriteLayer.frame = CGRect(origin: .zero, size: spriteSize)
        webLayer.frame = CGRect(x: CGFloat(anchorX) * scale, y: spriteSize.height,
                                width: scale, height: webHeight)
        webLayer.isHidden = webHeight <= 0
        CATransaction.commit()
    }

    /// True when `point` (window coordinates) is over an opaque sprite pixel.
    func hitsSprite(_ point: NSPoint) -> Bool {
        guard let sprite else { return false }
        let local = convert(point, from: nil)   // bottom-up; the sprite sits at y = 0
        let x = Int(floor(local.x / scale))
        let y = Int(floor((CGFloat(sprite.height) * scale - local.y) / scale))
        return sprite.isOpaque(x: x, y: y)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {   // ctrl-click = right-click
            onRightClick?(event)
            return
        }
        onMouseDown?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?()
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}
