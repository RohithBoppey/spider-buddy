import AppKit

/// Owns the pet window and decides what he does: hang from the top edge, crawl along the
/// bottom edge, cling to and climb the left/right walls, dangle while dragged, fall or zip to
/// an edge when dropped. Also follows the active display and hides over full-screen videos and games.
final class PetController {
    private var scale = Settings.shared.size.scale
    private let dragThreshold: CGFloat = 4   // points the cursor must move before a click becomes a drag
    private let gravity: CGFloat = 2500      // points/s², for the fall to the bottom edge
    private let zipSeconds: TimeInterval = 0.25   // sideways zip onto a wall
    private let doubleClickSeconds: TimeInterval = 0.3   // a single click waits this long for a second one
    // Speech bubbles. Tune these, then rebuild.
    private var bubbleEvery: ClosedRange<Int> { Settings.shared.bubbleFrequency.ticks }   // Settings > Speech
    private let bubbleShowTicks = 50                        // 5 s on screen
    private let timeUpTicks = 300                           // "Time's up!" stays 30 s on screen unless dismissed

    private let window = PetWindow()
    private let view: SpriteView
    private let indicator = IndicatorWindow()
    private let bubble = SpeechBubble()
    private let input = InputBubble()         // hub > Timer > Custom…: he holds still while it is open
    /// Countdown or stopwatch shown in his bubble (hub > Timer).
    let timer = BuddyTimer()
    private var timeUpShownTicks = 0          // how long "Time's up!" has been on screen
    private var timeUpTingleDue = false       // finished while he was out of sight: tingle once he is back
    private var alarmTicksLeft = 0            // > 0 while the alarm repeats (also while he is hidden)
    private let alarmTicks = 300              // 30 s
    /// The alarm restarts every 3 s, or back to back if the sound is longer (a loop).
    private lazy var alarmEveryTicks = max(30, Int((SoundEffects.shared.duration(.timerDone) * 10).rounded()))

    enum Edge { case top, bottom, left, right }

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
    private var pendingActive: (id: CGDirectDisplayID, ticks: Int)?   // a newly focused display, not yet trusted
    private let followDelayTicks = 8          // 0.8 s: focus hopping between windows (iTerm panes) is ignored
    private var hiddenForFullscreen = false
    private(set) var isPaused = false         // menu: Pause
    private(set) var isHiddenByUser = false   // menu: Hide Spider Buddy
    private var mouseDownAt: NSPoint?         // set while the button is held on him
    private var shown: (sprite: Sprite, origin: NSPoint)?   // what is on screen now, for the face
    private lazy var ticksToBubble = Int.random(in: bubbleEvery)
    private var bubbleTicksLeft = 0           // > 0 while a bubble is showing
    private var bubbleIsRandom = false        // a random line (not one he says because you asked)
    private var pendingClick: Timer?          // a single click, waiting to see if a second one follows
    private var pendingBubbleClick: Timer?    // the same, for a click on the timer bubble
    private var isHubOpen = false             // right-click hub showing: he holds still beside it
    private var webDropSoundDue = false       // you put him on the top edge: stretch sound when he slides down

    /// Right-click (or ctrl-click) on him: show the hub for this event, anchored to `view`.
    /// Called synchronously; he stays frozen until it returns.
    var onHubRequested: ((NSEvent, NSView) -> Void)?

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
        view.onRightClick = { [weak self] event in self?.rightClicked(event) }
        Notifier.shared.onTimerFinishedClicked = { [weak self] in self?.dismissTimeUp() }
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
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    /// A display was connected, disconnected or rearranged: if his screen is gone, move him
    /// to the active one, keeping his edge and relative position.
    @objc private func screensChanged() {
        Log.display.debug("screens changed: \(NSScreen.screens.map(\.logDescription).joined(separator: " | "), privacy: .public)")
        guard !NSScreen.screens.contains(where: { $0.displayID == screen.displayID }) else { return }
        let old = screen
        screen = NSScreen.main ?? NSScreen.screens[0]
        lastActiveID = screen.displayID
        pendingActive = nil
        Log.display.debug("his screen is gone, moving to \(self.screen.logDescription, privacy: .public)")
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
        // on the bottom and walls he stays put while he is talking; on the web he carries on.
        // Paused: frozen in place (but still draggable, and a click's tingle still plays out).
        if (!isPaused || isHeld || isTingling) && !isHubOpen && !input.isOpen && !(bubbleTicksLeft > 0 && isOnBottomOrWall) {
            let old = mode
            mode = advanced(mode)
            playWebSounds(from: old, to: mode)
        }
        render()
        updateBubble()
    }

    // MARK: - Menu actions

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { hideBubble() }
    }

    func setHidden(_ hidden: Bool) {
        isHiddenByUser = hidden
        if hidden {
            window.orderOut(nil)
            indicator.hide()
            hideBubble()
        } else if !hiddenForFullscreen {
            render()
            window.orderFrontRegardless()
        }
    }

    /// Call after Settings.bubblesEnabled changes. Only random lines stop; things he says
    /// because you asked (say) stay.
    func bubblesSettingChanged() {
        if !Settings.shared.bubblesEnabled && bubbleIsRandom { hideBubble() }
    }

    /// Applies Settings window changes live (any UserDefaults write lands here, so it is idempotent).
    @objc private func settingsChanged() {
        bubblesSettingChanged()
        let newScale = Settings.shared.size.scale
        if newScale != scale {
            scale = newScale
            view.scale = newScale
            // re-clamp to the new edge limits on the same screen
            if !isHeld && !isFlying { mode = relocated(mode, from: screen, to: screen) }
        }
        if case .top(var top) = mode {
            top.settleAtRestingHeight()
            mode = .top(top)
        }
        if ticksToBubble > bubbleEvery.upperBound { ticksToBubble = Int.random(in: bubbleEvery) }
        render()
        if bubbleTicksLeft > 0 { positionBubble() }   // new font or size
    }

    /// Moves him to the middle of an edge of his screen, landing as if dropped there.
    func send(to edge: Edge) {
        guard !isHeld, !isFlying else { return }
        hideBubble()
        let f = screen.frame
        let from = NSPoint(x: f.midX, y: f.midY + 80)
        switch edge {
        case .top:
            attachWeb(x: clampedHangX(f.midX, on: screen))
        case .bottom:
            fall(to: clampedCrawlX(f.midX, on: screen), from: from)
        case .left:
            zip(toRightWall: false, from: from)
        case .right:
            zip(toRightWall: true, from: from)
        }
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
        guard !hiddenForFullscreen, !isHiddenByUser else { return }
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

    private var isTingling: Bool {
        if case .tingle = mode { return true }
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
            cancelPendingClick()
            SoundEffects.shared.play(.grab)
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
            quickClicked()
            return
        }
        indicator.hide()
        SoundEffects.shared.play(.release)
        let mouse = NSEvent.mouseLocation
        screen = screenUnderMouse()
        lastActiveID = (NSScreen.main ?? screen).displayID   // stay here until the active display changes
        pendingActive = nil
        Log.display.debug("dropped at (\(Int(mouse.x)),\(Int(mouse.y))) on \(self.screen.logDescription, privacy: .public), edge \(String(describing: self.nearestEdge(mouse, on: self.screen)), privacy: .public)")
        switch nearestEdge(mouse, on: screen) {
        case .top:
            // web attaches to the top edge straight above the release point, then he drops
            attachWeb(x: clampedHangX(mouse.x, on: screen))
        case .bottom:
            fall(to: clampedCrawlX(mouse.x, on: screen), from: mouse)
        case .left:
            zip(toRightWall: false, from: mouse)
        case .right:
            zip(toRightWall: true, from: mouse)
        }
    }

    /// Shoots a web to the top edge above `x`; he slides down it after a moment.
    private func attachWeb(x: CGFloat) {
        mode = .top(TopHang(x: x, settleTicks: 3))
        SoundEffects.shared.play(.thwip)
        webDropSoundDue = true
        render()
    }

    /// Web sounds: the slide down after you put him on the top edge, and (if allowed) his idle yo-yo.
    private func playWebSounds(from old: Mode, to new: Mode) {
        guard case .top(let before) = old, case .top(let after) = new,
              !hiddenForFullscreen, !isHiddenByUser else { return }
        if after.isDropping && !before.isDropping {
            if webDropSoundDue { SoundEffects.shared.play(.stretch) }
            webDropSoundDue = false
        } else if after.isYoyoing && !before.isYoyoing {
            SoundEffects.shared.play(.stretch, ambient: true)
        }
    }

    /// Falls straight down from the cursor to the bottom edge, then lands in a crouch.
    private func fall(to x: CGFloat, from mouse: NSPoint) {
        let sprite = dangle[1]
        let start = heldFrame(for: sprite, at: mouse)
        var end = start
        end.origin.y = screen.frame.minY
        let height = start.minY - end.minY
        SoundEffects.shared.play(.fall)
        fly(sprite, to: end, seconds: height > 0 ? TimeInterval(sqrt(2 * height / gravity)) : 0, easing: .easeIn) {
            [weak self] in
            guard let self else { return }
            SoundEffects.shared.play(.land)
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
        SoundEffects.shared.play(.thwip)
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
    /// A new active display must stay active for `followDelayTicks` first, so focus briefly
    /// hopping to another display (iTerm split panes, a window spanning both) doesn't move him.
    private func followActiveScreen() {
        guard Settings.shared.followActiveDisplay, !isHeld, !isFlying,
              let active = NSScreen.main, let activeID = active.displayID else { return }
        guard activeID != lastActiveID else {
            if pendingActive != nil {
                Log.display.debug("focus came back to display \(activeID, privacy: .public) before the delay; staying")
                pendingActive = nil
            }
            return
        }
        if pendingActive?.id != activeID {
            Log.display.debug("active display now \(active.logDescription, privacy: .public); waiting")
            pendingActive = (activeID, 0)
        }
        pendingActive!.ticks += 1
        guard pendingActive!.ticks >= followDelayTicks else { return }
        pendingActive = nil
        lastActiveID = activeID
        guard activeID != screen.displayID else { return }
        let old = screen
        screen = active
        mode = relocated(mode, from: old, to: active)
        Log.display.debug("followed to \(active.logDescription, privacy: .public) from \(old.logDescription, privacy: .public), mode \(String(describing: self.mode), privacy: .public)")
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
        let match = isHeld || isFlying ? nil : FullscreenDetector.match(on: screen)
        let hide = match != nil
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        if let match {
            Log.fullscreen.debug("hiding: \(match, privacy: .public) covers \(self.screen.logDescription, privacy: .public)")
        } else {
            Log.fullscreen.debug("showing again on \(self.screen.logDescription, privacy: .public)")
        }
        Log.fullscreen.debug("system windows: \(FullscreenDetector.systemWindowsDescription(), privacy: .public)")
        if hide {
            window.orderOut(nil)
            hideBubble()
        } else if !isHiddenByUser {
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

    /// Shows `text` in his bubble now, even with random lines turned off or while paused.
    /// Takes the timer's place for a moment; the timer comes back after.
    func say(_ text: String) {
        guard !hiddenForFullscreen, !isHiddenByUser else { return }
        styleBubble(text)
        bubbleIsRandom = false
        bubbleTicksLeft = bubbleShowTicks
        positionBubble()
    }

    private func styleBubble(_ text: String, icon: SpeechBubble.Icon? = nil, hoverIcon: SpeechBubble.Icon? = nil,
                             fontSize: CGFloat? = nil, onClick: (() -> Void)? = nil) {
        bubble.text = text
        bubble.icon = icon
        bubble.hoverIcon = hoverIcon
        bubble.fontSize = fontSize
        bubble.wideText = onClick != nil   // the timer: readout and label on one line
        bubble.onClick = onClick
    }

    /// One bubble, by priority: a line he is saying (say or random), then the timer, then
    /// (only with no timer) a new random line when one is due.
    private func updateBubble() {
        if timer.checkFinished() {
            Notifier.shared.timerFinished(description: timer.description ?? "", note: timer.note)
            alarmTicksLeft = alarmTicks
            timerFinished()
        }
        if alarmTicksLeft > 0 {
            if alarmTicksLeft % alarmEveryTicks == 0 { SoundEffects.shared.play(.timerDone) }
            alarmTicksLeft -= 1
        }
        guard !hiddenForFullscreen, !isHiddenByUser else { return }
        if input.isOpen {   // the typing bubble takes his bubble's place
            bubble.hide()
            return
        }
        if bubbleTicksLeft > 0 {
            if bubbleTicksLeft == 1 {
                hideBubble()
            } else {
                bubbleTicksLeft -= 1
                positionBubble()   // follows him on the web
            }
            return
        }
        if timer.isActive || timer.isFinished {
            showTimerBubble()
            return
        }
        guard !isPaused, Settings.shared.bubblesEnabled else { return }
        if ticksToBubble > 0 { ticksToBubble -= 1 }
        guard ticksToBubble == 0, canSpeak else { return }   // when due, waits for him to be stationary
        styleBubble(SpeechLines.all.randomElement() ?? "Hey!")
        bubbleIsRandom = true
        bubbleTicksLeft = bubbleShowTicks
        positionBubble()
    }

    private func positionBubble() {
        guard let face = facePoint() else { return }
        bubble.show(pointingAt: face, side: bubbleSide, within: screen.visibleFrame)
    }

    /// His face on screen, where bubbles point.
    private func facePoint() -> NSPoint? {
        guard let (sprite, origin) = shown, let face = sprite.face else { return nil }
        return NSPoint(x: origin.x + face.x * scale, y: origin.y + (CGFloat(sprite.height) - face.y) * scale)
    }

    /// Ends the line he is saying and hides the bubble; a running timer shows again next tick.
    private func hideBubble() {
        if bubbleTicksLeft > 0 {
            bubbleTicksLeft = 0
            ticksToBubble = Int.random(in: bubbleEvery)
        }
        bubble.hide()
    }

    // MARK: - Timer

    func startTimer(seconds: TimeInterval, label: String? = nil, note: String? = nil) {
        alarmTicksLeft = 0
        SoundEffects.shared.stop(.timerDone)
        Notifier.shared.clearTimerFinished()
        Notifier.shared.requestPermission()
        timer.start(seconds: seconds, label: label, note: note)
        SoundEffects.shared.play(.timerStart)
        hideBubble()
    }

    func startStopwatch(note: String? = nil) {
        alarmTicksLeft = 0
        SoundEffects.shared.stop(.timerDone)
        timer.startStopwatch(note: note)
        SoundEffects.shared.play(.timerStart)
        hideBubble()
    }

    /// Pause or resume, with the same tock as starting.
    func toggleTimerPause() {
        guard timer.isActive else { return }
        timer.togglePause()
        SoundEffects.shared.play(.timerStart)
    }

    /// Opens the typing bubble next to him for a custom timer ("45m", "1:30", "@3pm", ...).
    func askForTimer() {
        guard !isHeld, !isFlying, !hiddenForFullscreen, !isHiddenByUser, let face = facePoint() else { return }
        cancelPendingClick()
        hideBubble()
        input.onSubmit = { [weak self] text in self?.submitTimer(text) ?? true }
        input.onClose = nil
        input.show(placeholder: "25m, 1:30, @3pm #study", hint: "Enter to start · Esc to cancel",
                   pointingAt: face, side: bubbleSide, within: screen.visibleFrame)
    }

    private func submitTimer(_ text: String) -> Bool {
        guard let (result, note) = DurationParser.parseEntry(text) else {
            input.showError("Try 45m, 1:30 or @3pm, then #label")
            return false
        }
        switch result {
        case .countdown(let seconds):
            startTimer(seconds: seconds, note: note)
            Settings.shared.addRecentTimer(seconds)
        case .until(let seconds, let label):
            startTimer(seconds: seconds, label: label, note: note)
        case .stopwatch:
            startStopwatch(note: note)
        }
        return true
    }

    /// Double-click on the timer bubble: add, change or (left empty) remove its label.
    private func editTimerNote() {
        guard timer.isActive, !isHeld, !isFlying, let face = facePoint() else { return }
        cancelPendingClick()
        bubble.hide()
        input.onSubmit = { [weak self] text in
            self?.timer.note = DurationParser.cleanNote(text)
            return true
        }
        input.onClose = nil
        input.show(placeholder: "Label, like study", hint: "Enter to save · empty removes · Esc to cancel",
                   text: timer.note ?? "", allowsEmpty: true,
                   pointingAt: face, side: bubbleSide, within: screen.visibleFrame)
    }

    /// One click on the timer bubble pauses or resumes, two edit its label; the single click
    /// waits `doubleClickSeconds` to tell them apart.
    private func timerBubbleClicked() {
        if pendingBubbleClick != nil {
            pendingBubbleClick?.invalidate()
            pendingBubbleClick = nil
            editTimerNote()
            return
        }
        let timer = Timer(timeInterval: doubleClickSeconds, repeats: false) { [weak self] _ in
            self?.pendingBubbleClick = nil
            self?.toggleTimerPause()
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingBubbleClick = timer
    }

    /// The label as the bubble shows it: up to 14 characters.
    private var shortNote: String? {
        guard let note = timer.note else { return nil }
        return note.count > 14 ? note.prefix(13).trimmingCharacters(in: .whitespaces) + "…" : note
    }

    func stopTimer() {
        timer.stop()
        bubble.hide()
    }

    /// The timer readout, following him on every edge while he carries on (he does not stop
    /// for it the way he does for lines). Out of the way while he is held or flying.
    private func showTimerBubble() {
        guard !isHeld, !isFlying else {
            bubble.hide()
            return
        }
        let size = Settings.shared.timerSize.fontSize
        if timer.isFinished {
            if timeUpTingleDue { timerFinished() }
            timeUpShownTicks += 1
            if timeUpShownTicks >= timeUpTicks {
                dismissTimeUp()
                return
            }
            // always the largest size, whatever the timer size setting: it has to be noticed
            let largest = TimerSize.allCases.map(\.fontSize).max()
            let text = shortNote.map { "Time's up!\n\($0)" } ?? "Time's up!"
            styleBubble(text, icon: .clock, fontSize: largest) { [weak self] in self?.dismissTimeUp() }
        } else {
            // hovering shows what a click does: pause a running timer, resume a paused one
            let separator = Settings.shared.timerLabelLayout.separator   // label beside or under the time
            let text = shortNote.map { timer.display + separator + $0 } ?? timer.display
            styleBubble(text, icon: timer.isPaused ? .pause : .clock,
                        hoverIcon: timer.isPaused ? .play : .pause, fontSize: size) {
                [weak self] in self?.timerBubbleClicked()
            }
        }
        positionBubble()
    }

    /// A countdown just ran out: spider-sense tingle (now, or once he is back on screen);
    /// the bubble says so.
    private func timerFinished() {
        timeUpShownTicks = 0
        guard !hiddenForFullscreen, !isHiddenByUser, !isHeld, !isFlying, !isTingling else {
            timeUpTingleDue = true
            return
        }
        timeUpTingleDue = false
        mode = .tingle(ticks: 8, resume: mode)
        render()
    }

    private func dismissTimeUp() {
        guard timer.isFinished else { return }
        alarmTicksLeft = 0
        SoundEffects.shared.stop(.timerDone)
        Notifier.shared.clearTimerFinished()
        timeUpTingleDue = false
        timer.stop()
        bubble.hide()
    }

    // MARK: - Clicks

    /// A click without a drag. Waits `doubleClickSeconds` for a second one: one click is the
    /// spider-sense tingle, two are a double-click.
    private func quickClicked() {
        if pendingClick != nil {
            cancelPendingClick()
            doubleClicked()
            return
        }
        let timer = Timer(timeInterval: doubleClickSeconds, repeats: false) { [weak self] _ in
            self?.pendingClick = nil
            self?.singleClicked()
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingClick = timer
    }

    private func cancelPendingClick() {
        pendingClick?.invalidate()
        pendingClick = nil
    }

    /// Short spider-sense, then back to whatever he was doing.
    private func singleClicked() {
        guard !isHeld, !isFlying else { return }
        if timer.isFinished {   // the click acknowledges "Time's up!"
            dismissTimeUp()
            return
        }
        if case .tingle = mode { return }
        mode = .tingle(ticks: 4, resume: mode)
        SoundEffects.shared.play(.tingle)
        render()
    }

    /// Reserved for Ask AI (v2.0); a teaser until then.
    private func doubleClicked() {
        say("Ask me anything... soon!")
    }

    private func rightClicked(_ event: NSEvent) {
        guard !isHeld, !isFlying else { return }
        cancelPendingClick()
        hideBubble()
        isHubOpen = true
        onHubRequested?(event, view)
        isHubOpen = false
    }

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

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
