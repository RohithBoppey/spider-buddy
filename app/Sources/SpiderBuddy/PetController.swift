import AppKit

/// Owns the pet window and decides what he does: hang from the top edge, crawl along the
/// bottom edge, cling to and climb the left/right walls, dangle while dragged, fall or zip to
/// an edge when dropped. Also follows the active display and hides over full-screen videos and games.
final class PetController {
    private let scale: CGFloat = 2
    private let dragThreshold: CGFloat = 4   // points the cursor must move before a click becomes a drag
    private let gravity: CGFloat = 2500      // points/s², for the fall to the bottom edge
    private let zipSeconds: TimeInterval = 0.25   // sideways zip onto a wall
    // Speech bubbles. Tune these, then rebuild.
    private let bubbleEvery: ClosedRange<Int> = 300...600   // ticks (0.1 s) between lines: 30-60 s
    private let bubbleShowTicks = 50                        // 5 s on screen

    private let window = PetWindow()
    private let view: SpriteView
    private let indicator = IndicatorWindow()
    private let bubble = SpeechBubble()

    private enum Edge { case top, bottom, left, right }

    /// A wall frame set for one wall and one climbing direction.
    private struct WallKey: Hashable {
        let onRight: Bool
        let goingUp: Bool
    }

    private let hang: [Sprite]                     // hang_00..04
    private let tingle: [Bool: Sprite]             // 087, keyed by facing right
    private let dangle: [Sprite]                   // 102, 103
    private let crouch: [Bool: Sprite]             // 088, keyed by facing right
    private let crawlCycle: [Bool: [Sprite]]       // 089..097, keyed by facing right
    private let wallReady: [Bool: Sprite]          // 018, keyed by on the right wall
    private let wallTransition: [WallKey: [Sprite]] // 129..131
    private let wallCycle: [WallKey: [Sprite]]     // 132..141

    private indirect enum Mode {
        case top(TopHang)
        case bottom(BottomCrawl)
        case wall(WallCling)
        case held(ticks: Int)
        case flying                           // window animating to an edge (fall or zip)
        case tingle(ticks: Int, resume: Mode) // quick click: spider-sense, then carry on
    }
    private var mode: Mode
    private var screen: NSScreen              // screen he is on
    private var lastActiveID: CGDirectDisplayID?   // display with keyboard focus at the last check
    private var hiddenForFullscreen = false
    private var mouseDownAt: NSPoint?         // set while the button is held on him
    private var shown: (sprite: Sprite, origin: NSPoint)?   // what is on screen now, for the face
    private lazy var ticksToBubble = Int.random(in: bubbleEvery)
    private var bubbleTicksLeft = 0           // > 0 while a bubble is showing

    init?(library: SpriteLibrary) {
        let hang = library.frames("top-hang")
        let pickup = library.frames("pickup")          // 087 tingle, 102/103 dangling
        let crawl = library.frames("bottom-crawl")     // 088 crouch, then the crawl cycle
        let ready = library.frames("wall-ready")       // 018, native on the right wall
        let climb = library.frames("wall-crawl")       // 129..131 transition, 132..141 cycle; native left wall
        guard hang.count >= 5, pickup.count >= 3, crawl.count >= 2, ready.count >= 1, climb.count >= 4,
              (crawl + ready + climb).allSatisfy({ $0.anchor != nil }) else {
            NSLog("SpiderBuddy: missing frames or anchors (top-hang \(hang.count), pickup \(pickup.count), "
                  + "bottom-crawl \(crawl.count), wall-ready \(ready.count), wall-crawl \(climb.count))")
            return nil
        }
        self.hang = hang
        tingle = [true: pickup[0], false: pickup[0].mirrored()]
        dangle = Array(pickup[1...2])
        let crouchRight = crawl.first { $0.name == "088" } ?? crawl[0]
        let cycleRight = crawl.filter { $0 !== crouchRight }
        crouch = [true: crouchRight, false: crouchRight.mirrored()]
        crawlCycle = [true: cycleRight, false: cycleRight.map { $0.mirrored() }]

        wallReady = [true: ready[0], false: ready[0].mirrored()]
        let transitionLeft = Array(climb.prefix(3)), cycleLeft = Array(climb.dropFirst(3))
        func variants(_ frames: [Sprite]) -> [WallKey: [Sprite]] {
            [WallKey(onRight: false, goingUp: true): frames,
             WallKey(onRight: false, goingUp: false): frames.map { $0.flippedVertically() },
             WallKey(onRight: true, goingUp: true): frames.map { $0.mirrored() },
             WallKey(onRight: true, goingUp: false): frames.map { $0.mirrored().flippedVertically() }]
        }
        wallTransition = variants(transitionLeft)
        wallCycle = variants(cycleLeft)

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
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// A display was connected, disconnected or rearranged: if his screen is gone, move him
    /// to the active one, keeping his edge and relative position.
    @objc private func screensChanged() {
        guard !NSScreen.screens.contains(where: { $0.displayID == screen.displayID }) else { return }
        let old = screen
        screen = NSScreen.main ?? NSScreen.screens[0]
        lastActiveID = screen.displayID
        if isHeld || isFlying { return }
        mode = relocated(mode, from: old, to: screen)
        hideBubble()
        render()
    }

    private func schedule(every interval: TimeInterval, _ selector: Selector) {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Animation

    @objc private func tick() {
        followActiveScreen()
        // on the bottom and walls he stays put while he is talking; on the web he carries on
        if !(bubbleTicksLeft > 0 && isOnBottomOrWall) {
            mode = advanced(mode)
        }
        render()
        updateBubble()
    }

    private func advanced(_ mode: Mode) -> Mode {
        switch mode {
        case .top(var top):
            top.tick()
            return .top(top)
        case .bottom(var bottom):
            bottom.tick(bounds: crawlBounds(on: screen))
            return .bottom(bottom)
        case .wall(var wall):
            wall.tick(bounds: wallBounds(on: screen))
            return .wall(wall)
        case .held(let n):
            return .held(ticks: n + 1)
        case .flying:
            return .flying
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
        case .wall(let wall):
            let sprite = wallSprite(for: wall)
            layoutOnWall(sprite, anchor: sprite.anchor!, onRight: wall.onRight, y: wall.y)
        case .held(let n):
            // spider-sense for the first moment, then dangle from the cursor
            layoutHeld(n < 3 ? tingle[true]! : dangle[(n / 2) % 2])
        case .flying:
            break
        case .tingle(_, let resume):
            switch resume {
            case .top(let top):
                let sprite = tingle[true]!
                layoutHanging(sprite, anchorX: sprite.width / 2, x: top.x, webLength: top.webLength)
            case .bottom(let bottom):
                let sprite = tingle[true]!
                layoutOnGround(sprite, anchor: CGPoint(x: sprite.width / 2, y: sprite.height), x: bottom.x, lift: 0)
            case .wall(let wall):
                // facing away from the wall, back against it
                let sprite = tingle[!wall.onRight]!
                let anchor = CGPoint(x: wall.onRight ? CGFloat(sprite.width) : 0, y: CGFloat(sprite.height) / 2)
                layoutOnWall(sprite, anchor: anchor, onRight: wall.onRight, y: wall.y)
            default:
                break
            }
        }
    }

    private func wallSprite(for wall: WallCling) -> Sprite {
        let key = WallKey(onRight: wall.onRight, goingUp: wall.goingUp)
        switch wall.phase {
        case .ready: return wallReady[wall.onRight]!
        case .into(let step), .outOf(let step): return wallTransition[key]![step]
        case .climb: return wallCycle[key]![wall.cycleIndex]
        }
    }

    /// On the web: from the screen's physical top, across the menu bar (0 pt when hidden).
    private func layoutHanging(_ sprite: Sprite, anchorX: Int, x: CGFloat, webLength: Int) {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let webHeight = menuBar + CGFloat(webLength) * scale
        let size = view.size(for: sprite, webHeight: webHeight)
        let origin = NSPoint(x: (x - CGFloat(anchorX) * scale).rounded(), y: screen.frame.maxY - size.height)
        place(sprite, origin: origin, size: size, webHeight: webHeight, anchorX: anchorX)
    }

    /// On the bottom edge: the sprite's anchor (bottom row) at screen x, `lift` points up.
    private func layoutOnGround(_ sprite: Sprite, anchor: CGPoint, x: CGFloat, lift: CGFloat) {
        let origin = NSPoint(x: (x - anchor.x * scale).rounded(),
                             y: screen.frame.minY + (CGFloat(sprite.height) - anchor.y) * scale + lift)
        place(sprite, origin: origin)
    }

    /// On a wall: the sprite's anchor (its wall-side edge, at eye height) on the screen edge at y.
    private func layoutOnWall(_ sprite: Sprite, anchor: CGPoint, onRight: Bool, y: CGFloat) {
        let wallX = onRight ? screen.frame.maxX : screen.frame.minX
        let origin = NSPoint(x: (wallX - anchor.x * scale).rounded(),
                             y: (y - (CGFloat(sprite.height) - anchor.y) * scale).rounded())
        place(sprite, origin: origin)
    }

    /// Held by the hands: the sprite's top-centre sits on the cursor, no web.
    private func layoutHeld(_ sprite: Sprite) {
        let frame = heldFrame(for: sprite, at: NSEvent.mouseLocation)
        place(sprite, origin: frame.origin)
    }

    private func place(_ sprite: Sprite, origin: NSPoint, size: CGSize? = nil,
                       webHeight: CGFloat = 0, anchorX: Int = 0) {
        let size = size ?? view.size(for: sprite, webHeight: 0)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: webHeight, anchorX: anchorX)
        shown = (sprite, origin)
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

    private var isFlying: Bool {
        if case .flying = mode { return true }
        return false
    }

    private func mouseDown() {
        guard !isFlying else { return }
        mouseDownAt = NSEvent.mouseLocation
        hideBubble()
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
        indicator.show(at: landingPoint(for: nearestEdge(mouse, on: target), mouse: mouse, on: target), on: target)
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
        switch nearestEdge(mouse, on: screen) {
        case .top:
            // web attaches to the top edge straight above the release point, then he drops
            mode = .top(TopHang(x: clampedHangX(mouse.x, on: screen), settleTicks: 3))
            render()
        case .bottom:
            fall(to: clampedCrawlX(mouse.x, on: screen), from: mouse)
        case .left:
            zip(toRightWall: false, from: mouse)
        case .right:
            zip(toRightWall: true, from: mouse)
        }
    }

    /// Falls straight down from the cursor to the bottom edge, then lands in a crouch.
    private func fall(to x: CGFloat, from mouse: NSPoint) {
        let sprite = dangle[1]
        let start = heldFrame(for: sprite, at: mouse)
        var end = start
        end.origin.y = screen.frame.minY
        let height = start.minY - end.minY
        fly(sprite, to: end, seconds: height > 0 ? TimeInterval(sqrt(2 * height / gravity)) : 0, easing: .easeIn) {
            [weak self] in
            guard let self else { return }
            self.mode = .bottom(BottomCrawl(x: x, cycleCount: self.crawlCycle[true]!.count))
        }
    }

    /// Zips sideways from the cursor onto a wall, then holds the ready pose there.
    private func zip(toRightWall onRight: Bool, from mouse: NSPoint) {
        let sprite = dangle[1]
        let start = heldFrame(for: sprite, at: mouse)
        var end = start
        end.origin.x = onRight ? screen.frame.maxX - start.width : screen.frame.minX
        let y = clampedWallY(start.midY, on: screen)
        fly(sprite, to: end, seconds: zipSeconds, easing: .easeOut) { [weak self] in
            guard let self else { return }
            self.mode = .wall(WallCling(onRight: onRight, y: y,
                                        transitionCount: self.wallTransition.values.first!.count,
                                        cycleCount: self.wallCycle.values.first!.count))
        }
    }

    /// Animates the window to `end` showing `sprite`, then hands over to `landed` and renders.
    private func fly(_ sprite: Sprite, to end: NSRect, seconds: TimeInterval,
                     easing: CAMediaTimingFunctionName, landed: @escaping () -> Void) {
        mode = .flying
        shown = nil
        hideBubble()
        view.show(sprite, webHeight: 0, anchorX: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = seconds
            context.timingFunction = CAMediaTimingFunction(name: easing)
            window.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            landed()
            self?.render()
        })
    }

    private func nearestEdge(_ point: NSPoint, on screen: NSScreen) -> Edge {
        let f = screen.frame
        let distances: [(Edge, CGFloat)] = [
            (.top, f.maxY - point.y), (.bottom, point.y - f.minY),
            (.left, point.x - f.minX), (.right, f.maxX - point.x),
        ]
        return distances.min { $0.1 < $1.1 }!.0
    }

    /// Where the indicator dot goes: the spot on that edge he will land at.
    private func landingPoint(for edge: Edge, mouse: NSPoint, on screen: NSScreen) -> NSPoint {
        let f = screen.frame
        switch edge {
        case .top: return NSPoint(x: clampedHangX(mouse.x, on: screen), y: f.maxY)
        case .bottom: return NSPoint(x: clampedCrawlX(mouse.x, on: screen), y: f.minY)
        case .left: return NSPoint(x: f.minX, y: clampedWallY(mouse.y, on: screen))
        case .right: return NSPoint(x: f.maxX, y: clampedWallY(mouse.y, on: screen))
        }
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

    private func clampedWallY(_ y: CGFloat, on screen: NSScreen) -> CGFloat {
        let bounds = wallBounds(on: screen)
        return min(max(y, bounds.lowerBound), bounds.upperBound)
    }

    /// Head-anchor range that keeps every crawl frame, either way round, fully on screen.
    private func crawlBounds(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let frames = crawlCycle[true]! + [crouch[true]!]
        let reach = frames.map { max($0.anchor!.x, CGFloat($0.width) - $0.anchor!.x) }.max() ?? 0
        let margin = reach * scale
        return (screen.frame.minX + margin)...(screen.frame.maxX - margin)
    }

    /// Eye-anchor range that keeps every wall frame, head up or down, below the menu bar
    /// and above the bottom edge.
    private func wallBounds(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let frames = wallReady.values.map { $0 } + wallTransition.values.flatMap { $0 } + wallCycle.values.flatMap { $0 }
        let above = frames.map { $0.anchor!.y }.max() ?? 0
        let below = frames.map { CGFloat($0.height) - $0.anchor!.y }.max() ?? 0
        let low = screen.frame.minY + below * scale
        let high = max(low, screen.visibleFrame.maxY - above * scale)
        return low...high
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen
    }

    // MARK: - Screens

    /// Moves him only when the active display (keyboard focus) changes, keeping his edge and
    /// relative position; a screen you dropped him on keeps him until you focus another display.
    private func followActiveScreen() {
        guard !isHeld, !isFlying, let active = NSScreen.main else { return }
        guard active.displayID != lastActiveID else { return }
        lastActiveID = active.displayID
        guard active.displayID != screen.displayID else { return }
        let old = screen
        screen = active
        mode = relocated(mode, from: old, to: active)
    }

    private func relocated(_ mode: Mode, from old: NSScreen, to new: NSScreen) -> Mode {
        func movedX(_ x: CGFloat) -> CGFloat {
            new.frame.minX + (x - old.frame.minX) / old.frame.width * new.frame.width
        }
        func movedY(_ y: CGFloat) -> CGFloat {
            new.frame.minY + (y - old.frame.minY) / old.frame.height * new.frame.height
        }
        switch mode {
        case .top(var top):
            top.x = clampedHangX(movedX(top.x), on: new)
            return .top(top)
        case .bottom(var bottom):
            bottom.x = clampedCrawlX(movedX(bottom.x), on: new)
            return .bottom(bottom)
        case .wall(var wall):
            wall.y = clampedWallY(movedY(wall.y), on: new)
            return .wall(wall)
        case .tingle(let n, let resume):
            return .tingle(ticks: n, resume: relocated(resume, from: old, to: new))
        case .held, .flying:
            return mode
        }
    }

    /// Hides him while a full-screen video or game covers his screen (not editors, terminals, ...).
    @objc private func checkFullscreen() {
        let hide = !isHeld && !isFlying && FullscreenDetector.isFullscreenVideoOrGame(on: screen)
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        if hide {
            window.orderOut(nil)
            hideBubble()
        } else {
            render()
            window.orderFrontRegardless()
        }
    }

    // MARK: - Speech bubbles

    private var isOnBottomOrWall: Bool {
        switch mode {
        case .bottom, .wall: return true
        default: return false
        }
    }

    /// Top edge: anytime he is on the web. Bottom and walls: only while stationary.
    private var canSpeak: Bool {
        switch mode {
        case .top: return true
        case .bottom(let bottom): if case .rest = bottom.phase { return true }
        case .wall(let wall): if case .ready = wall.phase { return true }
        default: break
        }
        return false
    }

    /// Which side of his face the bubble goes: away from walls, above him on the bottom edge.
    private var bubbleSide: SpeechBubble.Side {
        switch mode {
        case .bottom: return .above
        case .wall(let wall): return wall.onRight ? .left : .right
        default: return .right
        }
    }

    private func updateBubble() {
        guard !hiddenForFullscreen else { return }
        if bubbleTicksLeft > 0 {
            if bubbleTicksLeft == 1 {
                hideBubble()
            } else {
                bubbleTicksLeft -= 1
                positionBubble()   // follows him on the web
            }
            return
        }
        if ticksToBubble > 0 { ticksToBubble -= 1 }
        guard ticksToBubble == 0, canSpeak else { return }   // when due, waits for him to be stationary
        bubble.text = SpeechLines.all.randomElement() ?? "Hey!"
        bubbleTicksLeft = bubbleShowTicks
        positionBubble()
    }

    private func positionBubble() {
        guard let (sprite, origin) = shown, let face = sprite.face else { return }
        let point = NSPoint(x: origin.x + face.x * scale, y: origin.y + (CGFloat(sprite.height) - face.y) * scale)
        bubble.show(pointingAt: point, side: bubbleSide, within: screen.visibleFrame)
    }

    private func hideBubble() {
        guard bubbleTicksLeft > 0 else { return }
        bubbleTicksLeft = 0
        ticksToBubble = Int.random(in: bubbleEvery)
        bubble.hide()
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
