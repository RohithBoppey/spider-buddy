import CoreGraphics

/// Top edge: hanging upside down on a web from the screen's physical top, below the menu bar.
/// Settles, slides down the web, then idles with random head tilts and sways.
struct TopHang {
    static let anchorX = 25          // web anchor column in top-hang frames (draw_hang.py ANCHOR)
    // Web length below the menu bar, in sprite pixels (1 sprite pixel = `scale` points on screen).
    static let webStart = 4          // before a drop
    static let webTarget = 30        // after it: his resting height. Tune this, then rebuild.

    enum Phase {
        case settle(ticks: Int)
        case drop
        case idle(ticks: Int)
        case accent(frame: Int, ticks: Int)   // hang_02..04: head tilts, sway
    }

    var x: CGFloat                   // screen x (points) of the web
    var phase: Phase
    var webLength = TopHang.webStart

    /// Starts short on the web and drops to the resting height after `settleTicks`.
    init(x: CGFloat, settleTicks: Int) {
        self.x = x
        phase = .settle(ticks: settleTicks)
    }

    /// Index into the top-hang frames for the current phase.
    var frameIndex: Int {
        switch phase {
        case .settle, .idle: return 0
        case .drop: return 1
        case .accent(let frame, _): return frame
        }
    }

    mutating func tick() {
        switch phase {
        case .settle(let n):
            phase = n > 1 ? .settle(ticks: n - 1) : .drop
        case .drop:
            webLength = min(webLength + 2, Self.webTarget)
            if webLength == Self.webTarget { phase = Self.randomIdle() }
        case .idle(let n):
            phase = n > 1 ? .idle(ticks: n - 1) : .accent(frame: Int.random(in: 2...4), ticks: 6)
        case .accent(let frame, let n):
            phase = n > 1 ? .accent(frame: frame, ticks: n - 1) : Self.randomIdle()
        }
    }

    private static func randomIdle() -> Phase {
        .idle(ticks: Int.random(in: 20...60))   // 2-6 s at 10 fps
    }
}
