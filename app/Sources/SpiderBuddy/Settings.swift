import CoreGraphics
import Foundation

/// UserDefaults keys, shared by `Settings` and the Settings window's @AppStorage bindings.
enum SettingsKey {
    static let bubblesEnabled = "bubblesEnabled"
    static let size = "size"
    static let energy = "energy"
    static let webLength = "webLength"
    static let followActiveDisplay = "followActiveDisplay"
    static let bubbleFrequency = "bubbleFrequency"
    static let bubbleFont = "bubbleFont"
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
            SettingsKey.followActiveDisplay: true,
            SettingsKey.bubbleFrequency: BubbleFrequency.normal.rawValue,
            SettingsKey.bubbleFont: BubbleFont.pixel.rawValue,
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

    /// Follow the display with keyboard focus (true) or stay on the one he was left on.
    var followActiveDisplay: Bool { defaults.bool(forKey: SettingsKey.followActiveDisplay) }

    private func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}
