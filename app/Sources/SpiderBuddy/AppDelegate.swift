import AppKit

/// Chunk 1: a single pet window hanging from the top edge of the active screen.
/// The web starts at the screen's physical top (crossing the menu bar); he hangs below the menu bar.
/// Plays the top-hang loop: settle, slide down the web, then idle with random accents.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scale: CGFloat = 2
    private let hangAnchorX = 25          // web anchor column in top-hang frames (draw_hang.py ANCHOR)
    // Web length below the menu bar, in sprite pixels (1 sprite pixel = `scale` points on screen).
    private let webStart = 4              // before the drop at launch
    private let webTarget = 30            // after it: his resting height. Tune this, then rebuild.

    private let library = SpriteLibrary()
    private var window: PetWindow!
    private var view: SpriteView!
    private var statusItem: NSStatusItem!
    private var screen: NSScreen!         // the active screen: the one with keyboard focus
    private var hang: [Sprite] = []
    private var tingle: Sprite?

    private enum Phase {
        case settle(ticks: Int)
        case drop
        case idle(ticks: Int)
        case accent(frame: Int, ticks: Int)   // hang_02..04: head tilts, sway
        case tingle(ticks: Int)                // temporary click test (pickup arrives in chunk 3)
    }
    private var phase: Phase = .settle(ticks: 8)
    private lazy var webLength = webStart

    func applicationDidFinishLaunching(_ notification: Notification) {
        hang = library.frames("top-hang")
        tingle = library.frames("pickup").first
        guard hang.count >= 5 else {
            NSLog("SpiderBuddy: expected 5 top-hang frames, found \(hang.count)")
            NSApp.terminate(nil)
            return
        }

        screen = activeScreen()

        window = PetWindow()
        view = SpriteView(scale: scale)
        view.onMouseDown = { [weak self] in self?.phase = .tingle(ticks: 6) }
        window.contentView = view
        setUpStatusItem()

        render()
        window.orderFrontRegardless()

        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(tick),
                             userInfo: nil, repeats: true)
        Timer.scheduledTimer(timeInterval: 1.0 / 30, target: self, selector: #selector(updateMousePassthrough),
                             userInfo: nil, repeats: true)
    }

    // MARK: - Animation

    @objc private func tick() {
        // follow the active screen; he appears there as-is (the web drop plays only at launch)
        screen = activeScreen()

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
        case .tingle(let n):
            phase = n > 1 ? .tingle(ticks: n - 1) : randomIdle()
        }
        render()
    }

    /// NSScreen.main is the screen with keyboard focus (whose menu bar is active).
    private func activeScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private func randomIdle() -> Phase {
        .idle(ticks: Int.random(in: 20...60))   // 2-6 s at 10 fps
    }

    private func render() {
        let sprite: Sprite
        var anchorX = hangAnchorX
        switch phase {
        case .settle, .idle: sprite = hang[0]
        case .drop: sprite = hang[1]
        case .accent(let frame, _): sprite = hang[frame]
        case .tingle:
            guard let tingle else { return }
            sprite = tingle
            anchorX = tingle.width / 2
        }

        // web from the screen's physical top, across the menu bar (0 pt when it is hidden),
        // so he always hangs below it; centred on the screen
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let webHeight = menuBar + CGFloat(webLength) * scale
        let size = view.size(for: sprite, webHeight: webHeight)
        let origin = NSPoint(x: (screen.frame.midX - CGFloat(anchorX) * scale).rounded(),
                             y: screen.frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.show(sprite, webHeight: webHeight, anchorX: anchorX)
    }

    // MARK: - Clicks

    /// Clicks go through the window except over opaque sprite pixels.
    @objc private func updateMousePassthrough() {
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
