import CoreGraphics

/// Left/right edge: holds a still ready pose against the wall, and every few seconds climbs
/// a short way up or down, always head-first (climbing down uses the frames flipped head-down).
struct WallCling {
    // Tune these, then rebuild.
    static let speeds: ClosedRange<CGFloat> = 30...45          // points per second while climbing
    static let climbDistances: ClosedRange<CGFloat> = 120...350 // points per climb
    static let readyTicks: ClosedRange<Int> = 15...40           // ticks (0.1 s) in the ready pose: 1.5-4 s
    static let strideLength: CGFloat = 5    // points travelled per climbing frame; speed / stride = limb pace
    static let tickSeconds: CGFloat = 0.1

    enum Phase {
        case ready(ticks: Int)
        case into(step: Int)         // crouch-to-climb transition, frame `step` of 0..<transitionCount
        case climb
        case outOf(step: Int)        // the transition played backwards, back to ready
    }

    let onRight: Bool                // which wall
    var y: CGFloat                   // screen y (points) of the eye anchor
    var phase: Phase = .ready(ticks: WallCling.randomReadyTicks())
    var goingUp = true               // climbing direction; also whether he is head-up
    var cycleIndex = 0
    private var speed = WallCling.randomSpeed()
    private var remaining: CGFloat = 0
    private var travelled: CGFloat = 0
    private let transitionCount: Int
    private let cycleCount: Int

    init(onRight: Bool, y: CGFloat, transitionCount: Int, cycleCount: Int) {
        self.onRight = onRight
        self.y = y
        self.transitionCount = max(transitionCount, 1)
        self.cycleCount = max(cycleCount, 1)
    }

    /// `bounds`: the eye anchor's allowed y range on this wall.
    mutating func tick(bounds: ClosedRange<CGFloat>) {
        switch phase {
        case .ready(let n):
            if n > 1 {
                phase = .ready(ticks: n - 1)
            } else {
                startClimb(bounds: bounds)
            }
        case .into(let step):
            phase = step + 1 < transitionCount ? .into(step: step + 1) : .climb
        case .climb:
            climb(bounds: bounds)
        case .outOf(let step):
            phase = step > 0 ? .outOf(step: step - 1) : .ready(ticks: Self.randomReadyTicks())
        }
    }

    // Settings > Energy scales speed and rests.
    private static func randomSpeed() -> CGFloat {
        CGFloat.random(in: speeds) * Settings.shared.energy.speed
    }

    private static func randomReadyTicks() -> Int {
        max(1, Int(Double(Int.random(in: readyTicks)) * Settings.shared.energy.pause))
    }

    private mutating func startClimb(bounds: ClosedRange<CGFloat>) {
        remaining = CGFloat.random(in: Self.climbDistances)
        speed = Self.randomSpeed()
        // random direction, unless there isn't room that way
        let roomUp = bounds.upperBound - y, roomDown = y - bounds.lowerBound
        goingUp = roomUp < 20 ? false : roomDown < 20 ? true : Bool.random()
        cycleIndex = 0
        phase = .into(step: 0)
    }

    private mutating func climb(bounds: ClosedRange<CGFloat>) {
        let step = speed * Self.tickSeconds
        y += goingUp ? step : -step
        travelled += step
        remaining -= step
        while travelled >= Self.strideLength {
            travelled -= Self.strideLength
            cycleIndex = (cycleIndex + 1) % cycleCount
        }
        let hitLimit = y <= bounds.lowerBound || y >= bounds.upperBound
        y = min(max(y, bounds.lowerBound), bounds.upperBound)
        if remaining <= 0 || hitLimit {
            phase = .outOf(step: transitionCount - 1)
        }
    }
}
