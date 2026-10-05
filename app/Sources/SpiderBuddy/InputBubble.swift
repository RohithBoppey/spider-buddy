import AppKit

/// A pixel speech bubble you type into (hub > Timer > Custom…; Ask AI later). It takes the
/// keyboard without activating the app, like Spotlight, so the app you are in stays in front.
/// Enter submits, Esc or clicking anywhere else closes it.
final class InputBubble: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
    /// Called with the text on Enter. Return false to keep the bubble open (after `showError`).
    var onSubmit: ((String) -> Bool)?
    /// Called once whenever the bubble closes, submitted or not.
    var onClose: (() -> Void)?

    private static let fieldWidth: CGFloat = 190
    private static let gap: CGFloat = 5          // between the field and the hint line
    private static let hintColor = NSColor(white: 0.45, alpha: 1)
    private static let errorColor = NSColor(red: 0.75, green: 0.1, blue: 0.15, alpha: 1)

    private let field = NSTextField()
    private let hint = NSTextField(labelWithString: "")
    private let frameView = FrameView()
    private var hintText = ""
    private var allowsEmpty = false
    private var chipButtons: [ChipView] = []
    private var onChip: ((String) -> Void)?
    private static let chipSpacing: CGFloat = 6
    private var outsideClicks: Any?   // global monitor while open: a click in another app closes it

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        delegate = self

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = BubbleView.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byClipping
        field.delegate = self
        hint.font = .systemFont(ofSize: 10)
        hint.lineBreakMode = .byTruncatingTail

        frameView.addSubview(field)
        frameView.addSubview(hint)
        contentView = frameView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isOpen: Bool { isVisible }

    /// Opens with `text` (selected, so typing replaces it), `placeholder` when empty, a row of
    /// clickable `chips` (quick picks, passed to `onChip`) and `hint` (keys to press) underneath,
    /// pointing at `face` like a speech bubble. Enter on an empty field submits "" with
    /// `allowsEmpty`, otherwise it just closes.
    func show(placeholder: String, hint hintText: String, text: String = "", allowsEmpty: Bool = false,
              chips: [String] = [], onChip: ((String) -> Void)? = nil,
              pointingAt face: NSPoint, side: SpeechBubble.Side, within bounds: NSRect) {
        let font = Self.font
        self.allowsEmpty = allowsEmpty
        field.font = font
        field.stringValue = text
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder, attributes: [.font: font, .foregroundColor: Self.hintColor])
        self.hintText = hintText
        setHint(hintText, color: Self.hintColor)

        self.onChip = onChip
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons = chips.map { chip in
            let button = ChipView(title: chip, font: Self.chipFont) { [weak self] in self?.onChip?(chip) }
            frameView.addSubview(button)
            return button
        }
        // only as many chips as fit on one line
        var used: CGFloat = 0
        chipButtons = chipButtons.filter { button in
            let fits = used + button.frame.width <= Self.fieldWidth
            if fits { used += button.frame.width + Self.chipSpacing } else { button.removeFromSuperview() }
            return fits
        }
        let chipsHeight = chipButtons.map(\.frame.height).max() ?? 0

        let fieldHeight = ceil(font.ascender - font.descender + font.leading) + 4
        let hintHeight = ceil(hint.intrinsicContentSize.height)
        let chipsRow = chipButtons.isEmpty ? 0 : chipsHeight + Self.gap
        let pad = BubbleView.padding
        let box = CGSize(width: Self.fieldWidth + 2 * pad,
                         height: fieldHeight + Self.gap + chipsRow + hintHeight + 2 * pad)
        let (frame, side, tailAt) = SpeechBubble.placement(box: box, pointingAt: face, side: side, within: bounds)
        frameView.configure(box: BubbleView.box(size: box, side: side), side: side, tailAt: tailAt)
        let inner = frameView.box.insetBy(dx: pad, dy: pad)
        field.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: fieldHeight)
        var x = inner.minX
        for button in chipButtons {
            button.setFrameOrigin(NSPoint(x: x, y: inner.minY + fieldHeight + Self.gap))
            x += button.frame.width + Self.chipSpacing
        }
        hint.frame = NSRect(x: inner.minX, y: inner.minY + fieldHeight + Self.gap + chipsRow,
                            width: inner.width, height: hintHeight)

        setFrame(frame, display: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        // Spider Buddy is never the active app, so clicking another app may not take the
        // keyboard from this panel (no windowDidResignKey): watch for those clicks too.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in self?.dismiss()
            }
        }
    }

    /// Keeps the bubble open with `message` in place of the hint; typing again restores it.
    func showError(_ message: String) {
        setHint(message, color: Self.errorColor)
    }

    func dismiss() {
        if let outsideClicks {
            NSEvent.removeMonitor(outsideClicks)
            self.outsideClicks = nil
        }
        guard isVisible else { return }
        orderOut(nil)
        onClose?()
    }

    private func setHint(_ text: String, color: NSColor) {
        hint.stringValue = text
        hint.textColor = color
    }

    /// The system font: easier to read and type in than the small pixel font (the frame stays pixel-style).
    private static var font: NSFont { .systemFont(ofSize: 13) }
    private static var chipFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .medium) }

    // MARK: - Keys and focus

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if (text.isEmpty && !allowsEmpty) || onSubmit?(text) ?? true { dismiss() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        setHint(hintText, color: Self.hintColor)   // an error goes away once you edit
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()   // clicked somewhere else
    }

    /// A quick pick under the field ("45m"), drawn to match the bubble: dark outline, light fill.
    /// (System pill buttons don't draw in this never-active panel.)
    private final class ChipView: NSView {
        private static let padX: CGFloat = 7, padY: CGFloat = 2
        private static let fill = NSColor(white: 0.9, alpha: 1)
        private let title: String
        private let attributes: [NSAttributedString.Key: Any]
        private let onClick: () -> Void

        init(title: String, font: NSFont, onClick: @escaping () -> Void) {
            self.title = title
            self.attributes = [.font: font, .foregroundColor: BubbleView.ink]
            self.onClick = onClick
            let text = (title as NSString).size(withAttributes: attributes)
            super.init(frame: NSRect(x: 0, y: 0, width: ceil(text.width) + 2 * Self.padX,
                                     height: ceil(text.height) + 2 * Self.padY))
            toolTip = "Start \(title)"
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func draw(_ dirtyRect: NSRect) {
            BubbleView.ink.setFill()
            bounds.fill()
            Self.fill.setFill()
            bounds.insetBy(dx: 1, dy: 1).fill()
            (title as NSString).draw(at: NSPoint(x: Self.padX, y: Self.padY), withAttributes: attributes)
        }
    }

    /// The bubble frame behind the field (same look as SpeechBubble).
    private final class FrameView: NSView {
        private(set) var box = CGRect.zero
        private var side = SpeechBubble.Side.right
        private var tailAt: CGFloat = 0

        override var isFlipped: Bool { true }

        func configure(box: CGRect, side: SpeechBubble.Side, tailAt: CGFloat) {
            self.box = box
            self.side = side
            self.tailAt = tailAt
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            BubbleView.drawFrame(box: box, side: side, tailAt: tailAt)
        }
    }
}
