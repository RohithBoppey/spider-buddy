import AppKit

/// The pet hangs from the top edge of a screen on a web that starts at the screen's physical top
/// (crossing the menu bar); he hangs below the menu bar.
/// Hold-drag picks him up; releasing attaches the web to the top edge above the cursor and he drops.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scale: CGFloat = 2
    private let hangAnchorX = 25          // web anchor column in top-hang frames (draw_hang.py ANCHOR)
    // Web length below the menu bar, in sprite pixels (1 sprite pixel = `scale` points on screen).
    private let webStart = 4              // before a drop
    private let webTarget = 30            // after it: his resting height. Tune this, then rebuild.
    private let dragThreshold: CGFloat = 4   // points the cursor must move before a click becomes a drag

    private let library = SpriteLibrary()
    private var window: PetWindow!
    private var view: SpriteView!
    private let indicator = IndicatorWindow()
    private var statusItem: NSStatusItem!
    private var hang: [Sprite] = []
    private var tingle: Sprite!
    private var dangle: [Sprite] = []

    private var screen: NSScreen!         // screen he hangs on
    private var hangX: CGFloat = 0        // screen x (points) of the web
    private var lastActiveID: CGDirectDisplayID?   // display with keyboard focus at the last check
    private var hiddenForFullscreen = false

    private var mouseDownAt: NSPoint?     // set while the button is held on him

    private indirect enum Phase {
        case settle(ticks: Int)
        case drop
        case idle(ticks: Int)
        case accent(frame: Int, ticks: Int)       // hang_02..04: head tilts, sway
        case tingle(ticks: Int, resume: Phase)    // quick click: spider-sense, then carry on
        case held(ticks: Int)                     // being dragged
    }
    private var phase: Phase = .settle(ticks: 8)
    private lazy var webLength = webStart

    func applicationDidFinishLaunching(_ notification: Notification) {
        hang = library.frames("top-hang")
        let pickup = library.frames("pickup")     // 087 tingle, 102/103 dangling
        guard hang.count >= 5, pickup.count >= 3 else {
            NSLog("SpiderBuddy: missing frames (top-hang \(hang.count), pickup \(pickup.count))")
            NSApp.terminate(nil)
            return
        }
        tingle = pickup[0]
        dangle = Array(pickup[1...2])

        screen = activeScreen()
        lastActiveID = screen.displayID
        hangX = screen.frame.midX

        window = PetWindow()
        view = SpriteView(scale: scale)
        view.onMouseDown = { [weak self] in self?.mouseDown() }
        view.onMouseDragged = { [weak self] in self?.mouseDragged() }
        view.onMouseUp = { [weak self] in self?.mouseUp() }
        window.contentView = view
        setUpStatusItem()

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

        switch phase {
        case .settle(let n):
            phase = n > 1 ? .settle(ticks: n - 1) : .drop
        case .drop:
            webLength = min(webLength + 2, webTarget)
            if webLength == webTarget { phase = randomIdle() }
        case .idle(let n):
            phase = n > 1 ? .idle(ticks: n - 1) : .accent(frame: Int.random(in: 2...4), ticks: 6)
        case .accent(let frame, let n):
            phase = n > 1 ? .accent(frame: frame, ticks: n - 1) : randomIdle()
        case .tingle(let n, let resume):
            phase = n > 1 ? .tingle(ticks: n - 1, resume: resume) : resume
        case .held(let n):
            phase = .held(ticks: n + 1)
        }
        render()
    }

    private func randomIdle() -> Phase {
        .idle(ticks: Int.random(in: 20...60))   // 2-6 s at 10 fps
    }

    private func render() {
        guard !hiddenForFullscreen else { return }
        switch phase {
        case .settle, .idle: layoutHanging(hang[0], anchorX: hangAnchorX)
        case .drop: layoutHanging(hang[1], anchorX: hangAnchorX)
        case .accent(let frame, _): layoutHanging(hang[frame], anchorX: hangAnchorX)
        case .tingle: layoutHanging(tingle, anchorX: tingle.width / 2)
        case .held(let n):
            // spider-sense for the first moment, then dangle from the cursor
            layoutHeld(n < 3 ? tingle : dangle[(n / 2) % 2])
        }
    }

    /// On the web: from the screen's physical top, across the menu bar (0 pt when hidden).
    private func layoutHanging(_ sprite: Sprite, anchorX: Int) {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let webHeight = menuBar + CGFloat(webLength) * scale
        let size = view.size(for: sprite, webHeight: webHeight)
        let origin = NSPoint(x: (hangX - CGFloat(anchorX) * scale).rounded(),
                             y: screen.frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: webHeight, anchorX: anchorX)
    }

    /// Held by the hands: the sprite's top-centre sits on the cursor, no web.
    private func layoutHeld(_ sprite: Sprite) {
        let mouse = NSEvent.mouseLocation
        let size = view.size(for: sprite, webHeight: 0)
        let origin = NSPoint(x: (mouse.x - size.width / 2).rounded(), y: (mouse.y - size.height).rounded())
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: 0, anchorX: 0)
    }

    // MARK: - Pick up and drop

    private var isHeld: Bool {
        if case .held = phase { return true }
        return false
    }

    private func mouseDown() {
        mouseDownAt = NSEvent.mouseLocation
    }

    private func mouseDragged() {
        guard let start = mouseDownAt else { return }
        if !isHeld {
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) >= dragThreshold else { return }
            phase = .held(ticks: 0)
        }
        render()
        let target = screenUnderMouse()
        indicator.show(x: clampedHangX(NSEvent.mouseLocation.x, on: target), on: target)
    }

    private func mouseUp() {
        defer { mouseDownAt = nil }
        guard isHeld else {
            // quick click: short spider-sense, then back to whatever he was doing
            if case .tingle = phase { return }
            phase = .tingle(ticks: 4, resume: phase)
            render()
            return
        }
        indicator.hide()
        // attach the web to the top edge straight above the release point, then drop
        screen = screenUnderMouse()
        lastActiveID = activeScreen().displayID   // stay here until the active display changes
        hangX = clampedHangX(NSEvent.mouseLocation.x, on: screen)
        webLength = webStart
        phase = .settle(ticks: 3)
        render()
    }

    /// Keeps the whole hanging sprite on screen.
    private func clampedHangX(_ x: CGFloat, on screen: NSScreen) -> CGFloat {
        let left = CGFloat(hangAnchorX) * scale
        let right = CGFloat(hang[0].width - hangAnchorX) * scale
        return min(max(x, screen.frame.minX + left), screen.frame.maxX - right)
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen
    }

    // MARK: - Screens

    /// NSScreen.main is the screen with keyboard focus (whose menu bar is active).
    private func activeScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    /// Moves him only when the active display changes, keeping his relative position;
    /// a screen you dropped him on keeps him until you focus a different display.
    private func followActiveScreen() {
        guard !isHeld else { return }
        let active = activeScreen()
        guard active.displayID != lastActiveID else { return }
        lastActiveID = active.displayID
        guard active.displayID != screen.displayID else { return }
        let relative = (hangX - screen.frame.minX) / screen.frame.width
        screen = active
        hangX = clampedHangX(active.frame.minX + relative * active.frame.width, on: active)
    }

    /// Hides him while a full-screen video or game covers his screen (not editors, terminals, ...).
    @objc private func checkFullscreen() {
        let hide = !isHeld && FullscreenDetector.isFullscreenVideoOrGame(on: screen)
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

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕷️"
        let menu = NSMenu()
        let title = NSMenuItem(title: "Spider Buddy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spider Buddy", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
