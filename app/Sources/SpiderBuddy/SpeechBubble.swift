import AppKit
import CoreText

/// The lines he says, from Resources/lines.txt (one per line; # comments and blanks ignored).
enum SpeechLines {
    static let all: [String] = {
        guard let url = Bundle.main.url(forResource: "lines", withExtension: "txt")
                ?? URL(string: "file://" + FileManager.default.currentDirectoryPath + "/Resources/lines.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["Hey!"] }
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.isEmpty ? ["Hey!"] : lines
    }()
}

/// Pixel-style speech bubble in its own click-through window, with a stepped tail
/// pointing at a spot (his face) from a gap away.
final class SpeechBubble: NSPanel {
    /// Where the bubble sits relative to the face.
    enum Side { case left, right, above }

    /// A small pixel icon drawn before the text (the pixel font has no emoji).
    enum Icon { case clock, pause, play }

    // Tune these, then rebuild.
    static var usePixelFont: Bool { Settings.shared.bubbleFont == .pixel }

    /// Makes the bundled pixel font available to this process (bubbles and the Settings preview).
    static func registerFont() {
        if let url = Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    static let gapBeside: CGFloat = 22   // points from the face to the tail tip, bubble beside the face
    static let gapAbove: CGFloat = 20    // ... bubble above the face
    static let maxTextWidth: CGFloat = 150   // speech lines wrap here; the timer sets its own (wideText)

    private let bubbleView = BubbleView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = bubbleView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var text: String {
        get { bubbleView.text }
        set { if newValue != bubbleView.text { bubbleView.text = newValue } }
    }

    var icon: Icon? {
        get { bubbleView.icon }
        set { if newValue != bubbleView.icon { bubbleView.icon = newValue } }
    }

    /// Shown instead of `icon` while the pointer is over a clickable bubble: what a click does.
    var hoverIcon: Icon? {
        get { bubbleView.hoverIcon }
        set { if newValue != bubbleView.hoverIcon { bubbleView.hoverIcon = newValue } }
    }

    /// Text size in points; nil = the standard bubble size.
    var fontSize: CGFloat? {
        get { bubbleView.fontSize }
        set { if newValue != bubbleView.fontSize { bubbleView.fontSize = newValue } }
    }

    /// Lets one-line content (the timer readout with its label) run wider than speech lines before wrapping.
    var wideText: Bool {
        get { bubbleView.wideText }
        set { if newValue != bubbleView.wideText { bubbleView.wideText = newValue } }
    }

    /// Set to make the bubble clickable (the timer); nil = clicks pass through, as for speech.
    var onClick: (() -> Void)? {
        get { bubbleView.onClick }
        set {
            bubbleView.onClick = newValue
            ignoresMouseEvents = newValue == nil
            if newValue == nil { bubbleView.endHover() }   // stops receiving mouseExited
        }
    }

    /// Places the bubble on `side` of `face` (screen points), flipping sides or sliding it
    /// so it stays inside `bounds` (the screen's visible area).
    func show(pointingAt face: NSPoint, side preferred: Side, within bounds: NSRect) {
        let (frame, side, tailAt) = Self.placement(box: bubbleView.boxSize(), pointingAt: face, side: preferred, within: bounds)
        bubbleView.configure(side: side, tailAt: tailAt)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    /// Window frame for a bubble whose box (without the tail) is `box`, on `preferred` side of
    /// `face`, flipped or slid to stay inside `bounds`; plus the side used and where the tail
    /// meets the box (view coordinates, y down). Shared with InputBubble.
    static func placement(box: CGSize, pointingAt face: NSPoint, side preferred: Side,
                          within bounds: NSRect) -> (frame: NSRect, side: Side, tailAt: CGFloat) {
        let tail = BubbleView.tailExtent
        var side = preferred
        if side == .right && face.x + Self.gapBeside + tail + box.width > bounds.maxX { side = .left }
        if side == .left && face.x - Self.gapBeside - tail - box.width < bounds.minX { side = .right }

        var frame = NSRect.zero
        switch side {
        case .right, .left:
            frame.size = CGSize(width: box.width + tail, height: box.height)
            frame.origin.x = side == .right ? face.x + Self.gapBeside : face.x - Self.gapBeside - frame.width
            frame.origin.y = min(max(face.y - box.height / 2, bounds.minY), bounds.maxY - box.height)
        case .above:
            frame.size = CGSize(width: box.width, height: box.height + tail)
            frame.origin.x = min(max(face.x - box.width / 3, bounds.minX), bounds.maxX - box.width)
            frame.origin.y = min(face.y + Self.gapAbove, bounds.maxY - frame.height)
        }
        frame = frame.integral
        // tail position along its edge (view coordinates, y down), aimed at the face
        let tailAt: CGFloat
        switch side {
        case .right, .left: tailAt = frame.maxY - face.y
        case .above: tailAt = face.x - frame.minX
        }
        return (frame, side, tailAt)
    }

    func hide() {
        orderOut(nil)
        bubbleView.endHover()   // no mouseExited arrives once the window is gone
    }
}

/// Draws the bubble: dark outline, white fill, stepped corners and tail, pixel text.
final class BubbleView: NSView {
    static let tailLength: CGFloat = 8
    private static let outline: CGFloat = 2
    /// Tail plus its outline: how far the tail reaches past the box.
    static let tailExtent: CGFloat = tailLength + outline
    static let padding: CGFloat = 6
    static let ink = NSColor(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1)

    var text = "" { didSet { needsDisplay = true } }
    var icon: SpeechBubble.Icon? { didSet { needsDisplay = true } }
    var hoverIcon: SpeechBubble.Icon? { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }
    /// The icon to draw now: the click's action while hovered, otherwise the state.
    private var shownIcon: SpeechBubble.Icon? { isHovering && onClick != nil ? hoverIcon ?? icon : icon }
    var fontSize: CGFloat? { didSet { needsDisplay = true } }
    var wideText = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var side = SpeechBubble.Side.right
    private var tailAt: CGFloat = 0

    override var isFlipped: Bool { true }

    // Text attributes are made once per font and size, and text is measured only when it
    // changes: the timer bubble moves and redraws ~10 times a second, and building fonts and
    // laying out text that often crashed inside CoreText (2026-10-04, v1.2 development).
    private static var attributesCache: [String: [NSAttributedString.Key: Any]] = [:]
    private var measured: (key: String, size: CGSize)?

    private var fontKey: String { "\(SpeechBubble.usePixelFont ? "pixel" : "system")-\(fontSize ?? 8)" }
    private var maxTextWidth: CGFloat { wideText ? SpeechBubble.maxTextWidth * 2.5 : SpeechBubble.maxTextWidth }

    private var attributes: [NSAttributedString.Key: Any] {
        let key = fontKey
        if let cached = Self.attributesCache[key] { return cached }
        let size = fontSize ?? 8
        let font = SpeechBubble.usePixelFont ? NSFont(name: "PressStart2P-Regular", size: size) : nil
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font != nil ? 4 : 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: size * 11 / 8, weight: .regular),
            .foregroundColor: Self.ink,
            .paragraphStyle: paragraph.copy(),
        ]
        Self.attributesCache[key] = attributes
        return attributes
    }

    private func textSize() -> CGSize {
        let key = fontKey + "\u{0}\(maxTextWidth)\u{0}" + text
        if let measured, measured.key == key { return measured.size }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        let size = CGSize(width: ceil(rect.width), height: ceil(rect.height))
        measured = (key, size)
        return size
    }

    /// Icon side length in points: 8 icon pixels, as tall as a capital letter of the pixel font.
    private var iconSize: CGFloat { icon == nil ? 0 : (fontSize ?? 8) }
    private var iconGap: CGFloat { icon == nil ? 0 : (fontSize ?? 8) * 0.75 }

    /// The box without the tail.
    func boxSize() -> CGSize {
        let t = textSize()
        return CGSize(width: iconSize + iconGap + t.width + 2 * Self.padding,
                      height: max(t.height, iconSize) + 2 * Self.padding)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the app is never active while you hover him
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard onClick != nil else { return }
        isHovering = true
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    func endHover() {
        guard isHovering else { return }
        isHovering = false
        NSCursor.pop()
    }

    /// 8x8 pixel icons, rows top to bottom.
    private static let iconPixels: [SpeechBubble.Icon: [String]] = [
        .clock: ["..####..",
                 ".#....#.",
                 "#...#..#",
                 "#...#..#",
                 "#...###.",
                 "#......#",
                 ".#....#.",
                 "..####.."],
        .play:  ["........",
                 ".##.....",
                 ".####...",
                 ".######.",
                 ".######.",
                 ".####...",
                 ".##.....",
                 "........"],
        .pause: ["........",
                 ".##..##.",
                 ".##..##.",
                 ".##..##.",
                 ".##..##.",
                 ".##..##.",
                 ".##..##.",
                 "........"],
    ]

    private func drawIcon(_ icon: SpeechBubble.Icon, at origin: CGPoint) {
        guard let rows = Self.iconPixels[icon] else { return }
        let px = iconSize / 8
        Self.ink.setFill()
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "#" {
                NSRect(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px, width: px, height: px).fill()
            }
        }
    }

    func configure(side: SpeechBubble.Side, tailAt: CGFloat) {
        guard side != self.side || tailAt != self.tailAt else { return }   // moving alone needs no redraw
        self.side = side
        self.tailAt = tailAt
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = Self.box(size: boxSize(), side: side)
        Self.drawFrame(box: box, side: side, tailAt: tailAt)

        NSGraphicsContext.current?.shouldAntialias = !SpeechBubble.usePixelFont   // crisp pixel glyphs
        let t = textSize()
        let contentHeight = max(t.height, iconSize)
        if let icon = shownIcon {
            drawIcon(icon, at: CGPoint(x: box.minX + Self.padding, y: box.minY + Self.padding + (contentHeight - iconSize) / 2))
        }
        (text as NSString).draw(
            with: NSRect(x: box.minX + Self.padding + iconSize + iconGap, y: box.minY + Self.padding + (contentHeight - t.height) / 2,
                         width: t.width, height: t.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    /// Where the box sits in the view (y down): beside the tail.
    static func box(size: CGSize, side: SpeechBubble.Side) -> CGRect {
        var box = CGRect(origin: .zero, size: size)
        if side == .right { box.origin.x = tailExtent }   // tail on the left, pointing left at the face
        return box                                        // .left: tail on the right; .above: tail below
    }

    /// The outline, paper, stepped corners and tail, in a flipped view.
    static func drawFrame(box: CGRect, side: SpeechBubble.Side, tailAt: CGFloat) {
        let o = outline
        // tail position along its edge, kept clear of the stepped corners
        let steps = 4, step = tailLength / CGFloat(steps)
        let along: CGFloat = side == .above ? box.width : box.height
        let at = min(max(tailAt, 9), along - 9)

        // outline pass (grow = o), then paper pass (grow = 0) on top
        for (color, grow) in [(ink, o), (NSColor.white, 0)] {
            color.setFill()
            let inset = o - grow   // 0 for the outline, o for the paper
            // box with stepped (pixel) corners
            NSRect(x: box.minX + o, y: box.minY + inset, width: box.width - 2 * o, height: box.height - 2 * inset).fill()
            NSRect(x: box.minX + inset, y: box.minY + o, width: box.width - 2 * inset, height: box.height - 2 * o).fill()
            // stepped tail, narrowing towards the tip; the paper pass overlaps the box outline to open the joint
            for i in 0..<steps {
                let half = CGFloat(steps - i) * 1.5 + grow
                switch side {
                case .right:
                    let x = box.minX - CGFloat(i + 1) * step
                    NSRect(x: x - grow, y: at - half, width: step + grow + o, height: 2 * half).fill()
                case .left:
                    let x = box.maxX + CGFloat(i) * step
                    NSRect(x: x - o, y: at - half, width: step + o + grow, height: 2 * half).fill()
                case .above:
                    let y = box.maxY + CGFloat(i) * step
                    NSRect(x: at - half, y: y - o, width: 2 * half, height: step + o + grow).fill()
                }
            }
        }
    }
}
