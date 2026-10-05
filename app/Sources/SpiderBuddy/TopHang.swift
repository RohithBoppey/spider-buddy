import CoreGraphics

/// Top edge: hanging upside down on a web from the screen's physical top, below the menu bar.
/// Settles, slides down the web, then idles: random head tilts and sways, and every so often
/// climbs a little way up the web or slides a little way down it (yo-yo), and now and then
/// climbs all the way up to crawl along the ceiling (PetController takes over at the top).
struct TopHang {
    static let anchorX = 25          // web anchor column in top-hang frames (draw_hang.py ANCHOR)
    // Web length below the menu bar, in sprite pixels (1 sprite pixel = `scale` points on screen).
    static let webStart = 4          // before a drop
    static var webTarget: Int { Settings.shared.webLength.pixels }   // after it: his resting height
    // Yo-yo on the web. Tune these, then rebuild.
    static let yoyoChance = 0.4                  // when an idle stretch ends; otherwise a tilt/sway
    static let yoyoDistances: ClosedRange<Int> = 4...12   // sprite pixels per move
    static let yoyoRange = 12                    // stays within webTarget ± this
    static let ceilingChance = 0.125             // when an idle stretch ends: climb up to the ceiling

    enum Phase {
        case settle(ticks: Int)
        case drop
        case idle(ticks: Int)
        case accent(frame: Int, ticks: Int)   // hang_02..04: head tilts, sway
        case yoyo(target: Int, ticks: Int)    // moving 1 px per tick toward a new web length
        case climb(ticks: Int)                // all the way up, 1 px per tick, through the menu bar to the screen's top
    }

    var x: CGFloat                   // screen x (points) of the web
    var phase: Phase
    var webLength = TopHang.webStart
    /// Web length at the screen's physical top, above the menu bar (0 or negative; set by
    /// PetController, which knows the menu bar's height): where a climb ends.
    var ceilingLength = 0

    /// Starts short on the web and drops to the resting height after `settleTicks`.
    init(x: CGFloat, settleTicks: Int) {
        self.x = x
        phase = .settle(ticks: settleTicks)
    }

    var isDropping: Bool {
        if case .drop = phase { return true }
        return false
    }

    var isYoyoing: Bool {
        if case .yoyo = phase { return true }
        return false
    }

    var isClimbing: Bool {
        if case .climb = phase { return true }
        return false
    }

    /// Climbed all the way up: time to crawl along the ceiling.
    var reachedCeiling: Bool { isClimbing && webLength <= ceilingLength }

    /// Index into the top-hang frames for the current phase.
    var frameIndex: Int {
        switch phase {
        case .settle, .idle: return 0
        case .drop: return 1
        case .accent(let frame, _): return frame
        case .yoyo(let target, let ticks):
            // sliding down: loose grip; climbing up: alternate grips, hand over hand
            return target > webLength ? 1 : (ticks / 2) % 2
        case .climb(let ticks):
            return (ticks / 2) % 2   // hand over hand
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
            if n > 1 {
                phase = .idle(ticks: n - 1)
            } else if Double.random(in: 0..<1) < Self.ceilingChance {
                phase = .climb(ticks: 0)
            } else if Double.random(in: 0..<1) < Self.yoyoChance {
                phase = .yoyo(target: yoyoTarget(), ticks: 0)
            } else {
                phase = .accent(frame: Int.random(in: 2...4), ticks: 6)
            }
        case .accent(let frame, let n):
            phase = n > 1 ? .accent(frame: frame, ticks: n - 1) : Self.randomIdle()
        case .yoyo(let target, let ticks):
            webLength += target > webLength ? 1 : -1
            phase = webLength == target ? Self.randomIdle() : .yoyo(target: target, ticks: ticks + 1)
        case .climb(let ticks):
            webLength = max(webLength - 1, ceilingLength)
            phase = .climb(ticks: ticks + 1)
        }
    }

    /// A new web length a few pixels up or down, kept near the resting height.
    private func yoyoTarget() -> Int {
        let low = Self.webTarget - Self.yoyoRange, high = Self.webTarget + Self.yoyoRange
        let distance = Int.random(in: Self.yoyoDistances)
        let up = webLength - distance, down = webLength + distance
        let options = [up, down].filter { (low...high).contains($0) }
        return options.randomElement() ?? Self.webTarget
    }

    /// Moves to a new resting height (Settings > Web length changed) by sliding along the web.
    mutating func settleAtRestingHeight() {
        switch phase {
        case .idle, .accent, .yoyo:
            if webLength != Self.webTarget { phase = .yoyo(target: Self.webTarget, ticks: 0) }
        case .settle, .drop, .climb:
            break   // the drop already ends at the resting height; a climb carries on to the ceiling
        }
    }

    private static func randomIdle() -> Phase {
        // 2-6 s at 10 fps, scaled by Settings > Energy
        .idle(ticks: max(1, Int(Double(Int.random(in: 20...60)) * Settings.shared.energy.pause)))
    }
}
