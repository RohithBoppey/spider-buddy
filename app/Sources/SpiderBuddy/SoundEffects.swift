import AVFoundation

/// Sound effects, one file each in Resources/Sounds/<name>.wav (credits in CREDITS.md).
enum Sfx: String, CaseIterable {
    case thwip      // web shot: attached to the top edge, or zipping onto a wall
    case stretch    // sliding down the web
    case grab       // picked up
    case release    // let go
    case fall       // falling to the bottom edge
    case land       // landing there
    case tingle     // spider-sense, on a click
}

/// Plays sound effects at the Settings > Sound volume. A missing file is silently skipped.
final class SoundEffects {
    static let shared = SoundEffects()

    private var players: [Sfx: AVAudioPlayer] = [:]

    private init() {
        for sfx in Sfx.allCases {
            guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "wav", subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sfx] = player
        }
    }

    /// True when `sfx` has a sound file.
    func has(_ sfx: Sfx) -> Bool { players[sfx] != nil }

    /// Plays `sfx` from the start. `ambient` sounds (things he does on his own, like the
    /// idle yo-yo) also need Settings > Sound > idle sounds.
    func play(_ sfx: Sfx, ambient: Bool = false) {
        let settings = Settings.shared
        guard settings.sfxEnabled, !ambient || settings.sfxAmbient, let player = players[sfx] else { return }
        player.volume = Float(settings.sfxVolume)
        player.currentTime = 0
        player.play()
    }
}
