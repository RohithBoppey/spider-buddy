import CoreGraphics

/// Bottom edge: crawls along the screen's bottom in short bursts, pausing in a crouch between
/// them (sometimes for long), often turning around, with a tiny jitter. Lands in a crouch first.
/// Also drives the ceiling crawl (same motion, frames flipped upside down).
struct BottomCrawl {
    // Tune these, then rebuild.
    static let speeds: ClosedRange<CGFloat> = 32...48          // points per second while crawling
    static let burstDistances: ClosedRange<CGFloat> = 60...240  // points crawled before pausing
    static let shortPauses: ClosedRange<Int> = 10...30          // ticks (0.1 s): 1-3 s
    static let longPauses: ClosedRange<Int> = 50...100          // 5-10 s
    static let longPauseChance = 0.3
    static let turnChance = 0.4                                  // after each pause
    static let strideLength: CGFloat = 5     // points travelled per animation frame; speed / stride = limb pace
    static let tickSeconds: CGFloat = 0.1

    enum Phase {
        case landing(ticks: Int)     // crouch (088) after falling
        case crawl
        case rest(ticks: Int)        // crouch (088) between bursts
    }

    var x: CGFloat                   // screen x (points) of the head anchor
    var facingRight = Bool.random()
    var phase: Phase = .landing(ticks: 5)
    var cycleIndex = 0               // position in the crawl cycle
    var lift: CGFloat = 0            // jitter: points above the ground for this frame
    private(set) var bursts = 0      // bursts finished so far
    private var speed = BottomCrawl.randomSpeed()
    private var remaining = CGFloat.random(in: BottomCrawl.burstDistances)
    private var travelled: CGFloat = 0
    private let cycleCount: Int

    init(x: CGFloat, cycleCount: Int) {
        self.x = x
        self.cycleCount = max(cycleCount, 1)
    }

    var isCrouching: Bool {
        if case .crawl = phase { return false }
        return true
    }

    var isResting: Bool {
        if case .rest = phase { return true }
        return false
    }

    /// `bounds`: the head anchor's allowed x range on this screen.
    mutating func tick(bounds: ClosedRange<CGFloat>) {
        switch phase {
        case .landing(let n):
            phase = n > 1 ? .landing(ticks: n - 1) : .crawl
        case .rest(let n):
            if n > 1 {
                phase = .rest(ticks: n - 1)
            } else {
                startBurst()
            }
        case .crawl:
            crawl(bounds: bounds)
        }
    }

    // Settings > Energy scales speed and pauses.
    private static func randomSpeed() -> CGFloat {
        CGFloat.random(in: speeds) * Settings.shared.energy.speed
    }

    private static func scaledPause(_ ticks: Int) -> Int {
        max(1, Int(Double(ticks) * Settings.shared.energy.pause))
    }

    private mutating func startBurst() {
        if Double.random(in: 0..<1) < Self.turnChance { facingRight.toggle() }
        speed = Self.randomSpeed()
        remaining = CGFloat.random(in: Self.burstDistances)
        phase = .crawl
    }

    private mutating func crawl(bounds: ClosedRange<CGFloat>) {
        let step = speed * Self.tickSeconds
        x += facingRight ? step : -step
        travelled += step
        remaining -= step
        while travelled >= Self.strideLength {
            travelled -= Self.strideLength
            cycleIndex = (cycleIndex + 1) % cycleCount
            lift = Int.random(in: 0..<6) == 0 ? 1 : 0   // occasional 1 pt jitter
        }

        // turn around at the screen's corners
        if x <= bounds.lowerBound || x >= bounds.upperBound {
            x = min(max(x, bounds.lowerBound), bounds.upperBound)
            facingRight = x <= bounds.lowerBound
        }

        if remaining <= 0 {
            bursts += 1
            let long = Double.random(in: 0..<1) < Self.longPauseChance
            phase = .rest(ticks: Self.scaledPause(Int.random(in: long ? Self.longPauses : Self.shortPauses)))
            lift = 0
        }
    }
}
