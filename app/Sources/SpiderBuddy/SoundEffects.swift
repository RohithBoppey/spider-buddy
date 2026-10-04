import AVFoundation

/// Sound effects, one file each in Resources/Sounds/<name>.wav or .m4a (credits in CREDITS.md).
enum Sfx: String, CaseIterable {
    case thwip      // web shot: attached to the top edge, or zipping onto a wall
    case stretch    // sliding down the web
    case grab       // picked up
    case release    // let go
    case fall       // falling to the bottom edge
    case land       // landing there
    case tingle     // spider-sense, on a click
    case timerStart // a timer or stopwatch starts
    case timerDone  // the timer alarm (repeats while "Time's up!" shows)
}

/// Plays sound effects at the Settings > Sound volume. A missing file is silently skipped.
final class SoundEffects {
    static let shared = SoundEffects()

    private var players: [Sfx: AVAudioPlayer] = [:]

    private init() {
        for sfx in Sfx.allCases {
            guard let url = ["wav", "m4a"].lazy.compactMap({
                      Bundle.main.url(forResource: sfx.rawValue, withExtension: $0, subdirectory: "Sounds")
                  }).first,
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sfx] = player
        }
    }

    /// True when `sfx` has a sound file.
    func has(_ sfx: Sfx) -> Bool { players[sfx] != nil }

    /// Length of `sfx` in seconds (0 without a file).
    func duration(_ sfx: Sfx) -> TimeInterval { players[sfx]?.duration ?? 0 }

    /// Plays `sfx` from the start. `ambient` sounds (things he does on his own, like the
    /// idle yo-yo) also need Settings > Sound > idle sounds.
    /// The timer alarm ignores the Sounds on/off switch (it has its own, Settings > Timer).
    func play(_ sfx: Sfx, ambient: Bool = false) {
        let settings = Settings.shared
        let allowed = sfx == .timerDone ? settings.timerAlarm : settings.sfxEnabled
        guard allowed, !ambient || settings.sfxAmbient, let player = players[sfx] else { return }
        player.volume = Float(settings.sfxVolume)
        player.currentTime = 0
        player.play()
    }

    /// Cuts `sfx` off if it is playing (the alarm, once "Time's up!" is dismissed).
    func stop(_ sfx: Sfx) {
        players[sfx]?.stop()
    }
}
