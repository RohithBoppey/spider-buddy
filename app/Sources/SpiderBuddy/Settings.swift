import CoreGraphics
import Foundation

/// UserDefaults keys, shared by `Settings` and the Settings window's @AppStorage bindings.
enum SettingsKey {
    static let bubblesEnabled = "bubblesEnabled"
    static let size = "size"
    static let energy = "energy"
    static let webLength = "webLength"
    static let ceilingCrawl = "ceilingCrawl"
    static let followActiveDisplay = "followActiveDisplay"
    static let bubbleFrequency = "bubbleFrequency"
    static let bubbleFont = "bubbleFont"
    static let sfxEnabled = "sfxEnabled"
    static let sfxVolume = "sfxVolume"
    static let sfxAmbient = "sfxAmbient"
    static let timerSize = "timerSize"
    static let recentTimers = "recentTimers"
    static let lastTimerEntry = "lastTimerEntry"
    static let timerAlarm = "timerAlarm"
    static let timerNotify = "timerNotify"
    static let timerLabelLayout = "timerLabelLayout"
}

enum PetSize: String, CaseIterable, Identifiable {
    case small, normal, large
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Points per sprite pixel.
    var scale: CGFloat {
        switch self {
        case .small: return 1.5
        case .normal: return 2
        case .large: return 3
        }
    }
}

enum Energy: String, CaseIterable, Identifiable {
    case calm, normal, hyper
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Multiplies crawl and climb speeds.
    var speed: CGFloat {
        switch self {
        case .calm: return 0.7
        case .normal: return 1
        case .hyper: return 1.4
        }
    }
    /// Multiplies pauses and idle stretches.
    var pause: Double {
        switch self {
        case .calm: return 1.6
        case .normal: return 1
        case .hyper: return 0.6
        }
    }
}

enum WebLength: String, CaseIterable, Identifiable {
    case short, medium, long
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Resting web length below the menu bar, in sprite pixels.
    var pixels: Int {
        switch self {
        case .short: return 18
        case .medium: return 30
        case .long: return 45
        }
    }
}

enum BubbleFrequency: String, CaseIterable, Identifiable {
    case often, normal, rarely
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .often: return "every 15–30 s"
        case .normal: return "every 30–60 s"
        case .rarely: return "every 2–5 min"
        }
    }
    /// Ticks (0.1 s) between lines.
    var ticks: ClosedRange<Int> {
        switch self {
        case .often: return 150...300
        case .normal: return 300...600
        case .rarely: return 1200...3000
        }
    }
}

enum TimerSize: String, CaseIterable, Identifiable {
    case small, normal, large
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Timer bubble text size in points (the pixel font is designed for multiples of 8 px).
    var fontSize: CGFloat {
        switch self {
        case .small: return 8
        case .normal: return 10
        case .large: return 12
        }
    }
}

/// Where a timer's label goes in its bubble: beside the time, or on the line under it.
enum TimerLabelLayout: String, CaseIterable, Identifiable {
    case horizontal, vertical
    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Between the time and the label.
    var separator: String { self == .horizontal ? "  " : "\n" }
}

enum BubbleFont: String, CaseIterable, Identifiable {
    case pixel, system
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// User settings, saved in UserDefaults so they survive restarts.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            SettingsKey.bubblesEnabled: true,
            SettingsKey.size: PetSize.normal.rawValue,
            SettingsKey.energy: Energy.normal.rawValue,
            SettingsKey.webLength: WebLength.medium.rawValue,
            SettingsKey.ceilingCrawl: true,
            SettingsKey.followActiveDisplay: true,
            SettingsKey.bubbleFrequency: BubbleFrequency.normal.rawValue,
            SettingsKey.bubbleFont: BubbleFont.pixel.rawValue,
            SettingsKey.sfxEnabled: true,
            SettingsKey.sfxVolume: 0.4,
            SettingsKey.sfxAmbient: false,
            SettingsKey.timerSize: TimerSize.normal.rawValue,
            SettingsKey.timerAlarm: true,
            SettingsKey.timerNotify: true,
            SettingsKey.timerLabelLayout: TimerLabelLayout.horizontal.rawValue,
        ])
    }

    /// Random speech bubbles on or off.
    var bubblesEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.bubblesEnabled) }
        set { defaults.set(newValue, forKey: SettingsKey.bubblesEnabled) }
    }

    var size: PetSize { value(SettingsKey.size, .normal) }
    var energy: Energy { value(SettingsKey.energy, .normal) }
    var webLength: WebLength { value(SettingsKey.webLength, .medium) }
    var bubbleFrequency: BubbleFrequency { value(SettingsKey.bubbleFrequency, .normal) }
    var bubbleFont: BubbleFont { value(SettingsKey.bubbleFont, .pixel) }
    var timerSize: TimerSize { value(SettingsKey.timerSize, .normal) }
    var timerLabelLayout: TimerLabelLayout { value(SettingsKey.timerLabelLayout, .horizontal) }

    /// Sound effects on or off.
    var sfxEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.sfxEnabled) }
        set { defaults.set(newValue, forKey: SettingsKey.sfxEnabled) }
    }

    /// Sound effect volume, 0...1.
    var sfxVolume: Double { defaults.double(forKey: SettingsKey.sfxVolume) }

    /// Also play sounds for things he does on his own (the idle yo-yo on the web).
    var sfxAmbient: Bool { defaults.bool(forKey: SettingsKey.sfxAmbient) }

    /// Play the alarm when a timer ends (even with sound effects off).
    var timerAlarm: Bool { defaults.bool(forKey: SettingsKey.timerAlarm) }

    /// Post a macOS notification when a timer ends.
    var timerNotify: Bool { defaults.bool(forKey: SettingsKey.timerNotify) }

    /// Timer lengths in seconds, newest first: the chips in the Timer… bubble. "@3pm" times are not kept.
    var recentTimers: [TimeInterval] {
        defaults.array(forKey: SettingsKey.recentTimers) as? [TimeInterval] ?? []
    }

    func addRecentTimer(_ seconds: TimeInterval) {
        let recent = [seconds] + recentTimers.filter { $0 != seconds }
        defaults.set(Array(recent.prefix(3)), forKey: SettingsKey.recentTimers)
    }

    /// The last timer started from the Timer… bubble, as typed ("30m #study"): it opens pre-filled.
    var lastTimerEntry: String? {
        get { defaults.string(forKey: SettingsKey.lastTimerEntry) }
        set { defaults.set(newValue, forKey: SettingsKey.lastTimerEntry) }
    }

    /// On the top edge, now and then climb up and crawl along the top (true) or only hang.
    var ceilingCrawl: Bool { defaults.bool(forKey: SettingsKey.ceilingCrawl) }

    /// Follow the display with keyboard focus (true) or stay on the one he was left on.
    var followActiveDisplay: Bool { defaults.bool(forKey: SettingsKey.followActiveDisplay) }

    private func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}
