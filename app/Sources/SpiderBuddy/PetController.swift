import AppKit

/// Owns the pet window and decides what he does: hang from the top edge, crawl along the
/// bottom edge, dangle while dragged, fall to the bottom. Also follows the active display and
/// hides over full-screen videos and games.
final class PetController {
    private let scale: CGFloat = 2
    private let dragThreshold: CGFloat = 4   // points the cursor must move before a click becomes a drag
    private let gravity: CGFloat = 2500      // points/s², for the fall to the bottom edge

    private let window = PetWindow()
    private let view: SpriteView
    private let indicator = IndicatorWindow()

    private let hang: [Sprite]               // hang_00..04
    private let tingle: Sprite               // 087
    private let dangle: [Sprite]             // 102, 103
    private let crouch: [Bool: Sprite]       // 088, keyed by facing right
    private let crawlCycle: [Bool: [Sprite]] // 089..097, keyed by facing right

    private indirect enum Mode {
        case top(TopHang)
        case bottom(BottomCrawl)
        case held(ticks: Int)
        case falling                          // window animating down to the bottom edge
        case tingle(ticks: Int, resume: Mode) // quick click: spider-sense, then carry on
    }
    private var mode: Mode
    private var screen: NSScreen              // screen he is on
    private var lastActiveID: CGDirectDisplayID?   // display with keyboard focus at the last check
    private var hiddenForFullscreen = false
    private var mouseDownAt: NSPoint?         // set while the button is held on him

    init?(library: SpriteLibrary) {
        let hang = library.frames("top-hang")
        let pickup = library.frames("pickup")          // 087 tingle, 102/103 dangling
        let crawl = library.frames("bottom-crawl")     // 088 crouch, then the crawl cycle
        guard hang.count >= 5, pickup.count >= 3, crawl.count >= 2,
              crawl.allSatisfy({ $0.anchor != nil }) else {
            NSLog("SpiderBuddy: missing frames (top-hang \(hang.count), pickup \(pickup.count), bottom-crawl \(crawl.count))")
            return nil
        }
        self.hang = hang
        tingle = pickup[0]
        dangle = Array(pickup[1...2])
        let crouchRight = crawl.first { $0.name == "088" } ?? crawl[0]
        let cycleRight = crawl.filter { $0 !== crouchRight }
        crouch = [true: crouchRight, false: crouchRight.mirrored()]
        crawlCycle = [true: cycleRight, false: cycleRight.map { $0.mirrored() }]

        view = SpriteView(scale: scale)
        screen = NSScreen.main ?? NSScreen.screens[0]
        lastActiveID = screen.displayID
        mode = .top(TopHang(x: screen.frame.midX, settleTicks: 8))

        view.onMouseDown = { [weak self] in self?.mouseDown() }
        view.onMouseDragged = { [weak self] in self?.mouseDragged() }
        view.onMouseUp = { [weak self] in self?.mouseUp() }
        window.contentView = view
    }

    func start() {
        render()
        window.orderFrontRegardless()
        // .common mode keeps them running while a menu is open or the mouse is held
        schedule(every: 0.1, #selector(tick))
        schedule(every: 1.0 / 30, #selector(updateMousePassthrough))
        schedule(every: 0.5, #selector(checkFullscreen))
    }

    private func schedule(every interval: TimeInterval, _ selector: Selector) {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Animation

    @objc private func tick() {
        followActiveScreen()
        mode = advanced(mode)
        render()
    }

    private func advanced(_ mode: Mode) -> Mode {
        switch mode {
        case .top(var top):
            top.tick()
            return .top(top)
        case .bottom(var bottom):
            bottom.tick(bounds: crawlBounds(on: screen))
            return .bottom(bottom)
        case .held(let n):
            return .held(ticks: n + 1)
        case .falling:
            return .falling
        case .tingle(let n, let resume):
            return n > 1 ? .tingle(ticks: n - 1, resume: resume) : resume
        }
    }

    private func render() {
        guard !hiddenForFullscreen else { return }
        switch mode {
        case .top(let top):
            layoutHanging(hang[top.frameIndex], anchorX: TopHang.anchorX, x: top.x, webLength: top.webLength)
        case .bottom(let bottom):
            let sprite = bottom.isCrouching
                ? crouch[bottom.facingRight]!
                : crawlCycle[bottom.facingRight]![bottom.cycleIndex]
            layoutOnGround(sprite, anchor: sprite.anchor!, x: bottom.x, lift: bottom.lift)
        case .held(let n):
            // spider-sense for the first moment, then dangle from the cursor
            layoutHeld(n < 3 ? tingle : dangle[(n / 2) % 2])
        case .falling:
            break
        case .tingle(_, let resume):
            switch resume {
            case .top(let top):
                layoutHanging(tingle, anchorX: tingle.width / 2, x: top.x, webLength: top.webLength)
            case .bottom(let bottom):
                layoutOnGround(tingle, anchor: CGPoint(x: tingle.width / 2, y: tingle.height), x: bottom.x, lift: 0)
            default:
                break
            }
        }
    }

    /// On the web: from the screen's physical top, across the menu bar (0 pt when hidden).
    private func layoutHanging(_ sprite: Sprite, anchorX: Int, x: CGFloat, webLength: Int) {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let webHeight = menuBar + CGFloat(webLength) * scale
        let size = view.size(for: sprite, webHeight: webHeight)
        let origin = NSPoint(x: (x - CGFloat(anchorX) * scale).rounded(), y: screen.frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: webHeight, anchorX: anchorX)
    }

    /// On the bottom edge: the sprite's anchor (bottom row) at screen x, `lift` points up.
    private func layoutOnGround(_ sprite: Sprite, anchor: CGPoint, x: CGFloat, lift: CGFloat) {
        let size = view.size(for: sprite, webHeight: 0)
        let origin = NSPoint(x: (x - anchor.x * scale).rounded(),
                             y: screen.frame.minY + (CGFloat(sprite.height) - anchor.y) * scale + lift)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: 0, anchorX: 0)
    }

    /// Held by the hands: the sprite's top-centre sits on the cursor, no web.
    private func layoutHeld(_ sprite: Sprite) {
        window.setFrame(heldFrame(for: sprite, at: NSEvent.mouseLocation), display: false)
        view.show(sprite, webHeight: 0, anchorX: 0)
    }

    private func heldFrame(for sprite: Sprite, at mouse: NSPoint) -> NSRect {
        let size = view.size(for: sprite, webHeight: 0)
        return NSRect(origin: NSPoint(x: (mouse.x - size.width / 2).rounded(), y: (mouse.y - size.height).rounded()),
                      size: size)
    }

    // MARK: - Pick up and drop

    private var isHeld: Bool {
        if case .held = mode { return true }
        return false
    }

    private var isFalling: Bool {
        if case .falling = mode { return true }
        return false
    }

    private func mouseDown() {
        guard !isFalling else { return }
        mouseDownAt = NSEvent.mouseLocation
    }

    private func mouseDragged() {
        guard let start = mouseDownAt else { return }
        if !isHeld {
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) >= dragThreshold else { return }
            mode = .held(ticks: 0)
        }
        render()
        let mouse = NSEvent.mouseLocation
        let target = screenUnderMouse()
        let top = nearestEdgeIsTop(mouse, on: target)
        let x = top ? clampedHangX(mouse.x, on: target) : clampedCrawlX(mouse.x, on: target)
        indicator.show(x: x, atTop: top, on: target)
    }

    private func mouseUp() {
        guard mouseDownAt != nil else { return }
        mouseDownAt = nil
        guard isHeld else {
            // quick click: short spider-sense, then back to whatever he was doing
            if case .tingle = mode { return }
            mode = .tingle(ticks: 4, resume: mode)
            render()
            return
        }
        indicator.hide()
        let mouse = NSEvent.mouseLocation
        screen = screenUnderMouse()
        lastActiveID = (NSScreen.main ?? screen).displayID   // stay here until the active display changes
        if nearestEdgeIsTop(mouse, on: screen) {
            // web attaches to the top edge straight above the release point, then he drops
            mode = .top(TopHang(x: clampedHangX(mouse.x, on: screen), settleTicks: 3))
            render()
        } else {
            fall(to: clampedCrawlX(mouse.x, on: screen), from: mouse)
        }
    }

    /// Falls straight down from the cursor to the bottom edge, then lands in a crouch.
    private func fall(to x: CGFloat, from mouse: NSPoint) {
        let sprite = dangle[1]
        let start = heldFrame(for: sprite, at: mouse)
        var end = start
        end.origin.y = screen.frame.minY
        let height = start.minY - end.minY
        mode = .falling
        view.show(sprite, webHeight: 0, anchorX: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = height > 0 ? TimeInterval(sqrt(2 * height / gravity)) : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.mode = .bottom(BottomCrawl(x: x, cycleCount: self.crawlCycle[true]!.count))
            self.render()
        })
    }

    private func nearestEdgeIsTop(_ point: NSPoint, on screen: NSScreen) -> Bool {
        screen.frame.maxY - point.y <= point.y - screen.frame.minY
    }

    /// Keeps the whole hanging sprite on screen.
    private func clampedHangX(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let left = CGFloat(TopHang.anchorX) * scale
        let right = CGFloat(hang[0].width - TopHang.anchorX) * scale
        return min(max(x, screen.frame.minX + left), screen.frame.maxX - right)
    }

    private func clampedCrawlX(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let bounds = crawlBounds(on: screen)
        return min(max(x, bounds.lowerBound), bounds.upperBound)
    }

    /// Head-anchor range that keeps every crawl frame, either way round, fully on screen.
    private func crawlBounds(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let frames = crawlCycle[true]! + [crouch[true]!]
        let reach = frames.map { max($0.anchor!.x, CGFloat($0.width) - $0.anchor!.x) }.max() ?? 0
        let margin = reach * scale
        return (screen.frame.minX + margin)...(screen.frame.maxX - margin)
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen
    }

    // MARK: - Screens

    /// Moves him only when the active display (keyboard focus) changes, keeping his edge and
    /// relative position; a screen you dropped him on keeps him until you focus another display.
    private func followActiveScreen() {
        guard !isHeld, !isFalling, let active = NSScreen.main else { return }
        guard active.displayID != lastActiveID else { return }
        lastActiveID = active.displayID
        guard active.displayID != screen.displayID else { return }
        let old = screen
        screen = active
        mode = relocated(mode, from: old, to: active)
    }

    private func relocated(_ mode: Mode, from old: NSScreen, to new: NSScreen) -> Mode {
        func moved(_ x: CGFloat) -> CGFloat {
            new.frame.minX + (x - old.frame.minX) / old.frame.width * new.frame.width
        }
        switch mode {
        case .top(var top):
            top.x = clampedHangX(moved(top.x), on: new)
            return .top(top)
        case .bottom(var bottom):
            bottom.x = clampedCrawlX(moved(bottom.x), on: new)
            return .bottom(bottom)
        case .tingle(let n, let resume):
            return .tingle(ticks: n, resume: relocated(resume, from: old, to: new))
        case .held, .falling:
            return mode
        }
    }

    /// Hides him while a full-screen video or game covers his screen (not editors, terminals, ...).
    @objc private func checkFullscreen() {
        let hide = !isHeld && !isFalling && FullscreenDetector.isFullscreenVideoOrGame(on: screen)
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        if hide {
            window.orderOut(nil)
        } else {
            render()
            window.orderFrontRegardless()
        }
    }

    // MARK: - Clicks

    /// Clicks go through the window except over opaque sprite pixels.
    @objc private func updateMousePassthrough() {
        guard !isHeld, mouseDownAt == nil else { return }   // never drop the mouse mid-drag
        let mouse = NSEvent.mouseLocation
        var overSprite = false
        if window.frame.contains(mouse) {
            overSprite = view.hitsSprite(window.convertPoint(fromScreen: mouse))
        }
        if window.ignoresMouseEvents == overSprite {
            window.ignoresMouseEvents = !overSprite
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
