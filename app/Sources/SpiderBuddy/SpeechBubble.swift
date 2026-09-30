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
    static let maxTextWidth: CGFloat = 150

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
        set { bubbleView.text = newValue }
    }

    /// Places the bubble on `side` of `face` (screen points), flipping sides or sliding it
    /// so it stays inside `bounds` (the screen's visible area).
    func show(pointingAt face: NSPoint, side preferred: Side, within bounds: NSRect) {
        let box = bubbleView.boxSize()
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
        bubbleView.configure(side: side, tailAt: tailAt)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

/// Draws the bubble: dark outline, white fill, stepped corners and tail, pixel text.
private final class BubbleView: NSView {
    static let tailLength: CGFloat = 8
    private static let outline: CGFloat = 2
    /// Tail plus its outline: how far the tail reaches past the box.
    static let tailExtent: CGFloat = tailLength + outline
    private static let padding: CGFloat = 6
    private static let ink = NSColor(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1)

    var text = "" { didSet { needsDisplay = true } }
    private var side = SpeechBubble.Side.right
    private var tailAt: CGFloat = 0

    override var isFlipped: Bool { true }

    private static var font: NSFont {
        if SpeechBubble.usePixelFont, let font = NSFont(name: "PressStart2P-Regular", size: 8) { return font }
        return NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = SpeechBubble.usePixelFont ? 4 : 3
        return [.font: Self.font, .foregroundColor: Self.ink, .paragraphStyle: paragraph]
    }

    private func textSize() -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: SpeechBubble.maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// The box without the tail.
    func boxSize() -> CGSize {
        let t = textSize()
        return CGSize(width: t.width + 2 * Self.padding, height: t.height + 2 * Self.padding)
    }

    func configure(side: SpeechBubble.Side, tailAt: CGFloat) {
        self.side = side
        self.tailAt = tailAt
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let o = Self.outline, reach = Self.tailExtent
        var box = CGRect(origin: .zero, size: boxSize())
        switch side {
        case .right: box.origin.x = reach    // tail on the left, pointing left at the face
        case .left: box.origin.x = 0         // tail on the right
        case .above: box.origin.y = 0        // tail below
        }

        // tail position along its edge, kept clear of the stepped corners
        let steps = 4, step = Self.tailLength / CGFloat(steps)
        let along: CGFloat = side == .above ? box.width : box.height
        let at = min(max(tailAt, 9), along - 9)

        // outline pass (grow = o), then paper pass (grow = 0) on top
        for (color, grow) in [(Self.ink, o), (NSColor.white, 0)] {
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

        NSGraphicsContext.current?.shouldAntialias = !SpeechBubble.usePixelFont   // crisp pixel glyphs
        let t = textSize()
        (text as NSString).draw(
            with: NSRect(x: box.minX + Self.padding, y: box.minY + Self.padding, width: t.width, height: t.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}
