import AppKit
import SwiftUI

/// The Settings window (menu bar > Settings…). Controls write straight to UserDefaults via
/// @AppStorage; the pet picks changes up live (PetController.settingsChanged).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SpeechSettings()
                .tabItem { Label("Speech", systemImage: "text.bubble") }
            SoundSettings()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            TimerSettings()
                .tabItem { Label("Timer", systemImage: "timer") }
        }
        // grouped Forms scroll, so they report no height of their own: size the window explicitly
        .frame(width: 480, height: 470)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.size) private var size = PetSize.normal
    @AppStorage(SettingsKey.energy) private var energy = Energy.normal
    @AppStorage(SettingsKey.webLength) private var webLength = WebLength.medium
    @AppStorage(SettingsKey.ceilingCrawl) private var ceilingCrawl = true
    @AppStorage(SettingsKey.followActiveDisplay) private var followActiveDisplay = true
    @State private var autoUpdate = Updater.shared.automaticallyChecks
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        Form {
            Section {
                Picker("Size", selection: $size) {
                    ForEach(PetSize.allCases) { Text($0.title).tag($0) }
                }
                Picker("Energy", selection: $energy) {
                    ForEach(Energy.allCases) { Text($0.title).tag($0) }
                }
                Picker("Web length", selection: $webLength) {
                    ForEach(WebLength.allCases) { Text($0.title).tag($0) }
                }
                Picker("On the top edge", selection: $ceilingCrawl) {
                    Text("Hang and crawl").tag(true)
                    Text("Only hang").tag(false)
                }
            } footer: {
                Text("Energy sets how fast he moves and how long he rests. Web length is how far he hangs below the menu bar. "
                     + "With Hang and crawl he now and then climbs up and crawls along the top edge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Picker("With more than one display", selection: $followActiveDisplay) {
                    Text("Follow the active display").tag(true)
                    Text("Stay on the display I leave him on").tag(false)
                }
                .pickerStyle(.radioGroup)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { Updater.shared.automaticallyChecks = $0 }
                HStack {
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { Updater.shared.checkForUpdates(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .pickerStyle(.segmented)
    }
}

private struct SpeechSettings: View {
    @AppStorage(SettingsKey.bubblesEnabled) private var bubblesEnabled = true
    @AppStorage(SettingsKey.bubbleFrequency) private var frequency = BubbleFrequency.normal
    @AppStorage(SettingsKey.bubbleFont) private var font = BubbleFont.pixel

    var body: some View {
        Form {
            Section {
                Toggle("Speech bubbles", isOn: $bubblesEnabled)
                Picker("How often", selection: $frequency) {
                    ForEach(BubbleFrequency.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!bubblesEnabled)
                Text(frequency.detail).font(.caption).foregroundStyle(.secondary)
                Picker("Font", selection: $font) {
                    ForEach(BubbleFont.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!bubblesEnabled)
            }
            Section("Preview") {
                HStack {
                    Spacer()
                    BubblePreview(font: font)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
        .pickerStyle(.segmented)
    }
}

private struct SoundSettings: View {
    @AppStorage(SettingsKey.sfxEnabled) private var enabled = true
    @AppStorage(SettingsKey.sfxVolume) private var volume = 0.4
    @AppStorage(SettingsKey.sfxAmbient) private var ambient = false

    var body: some View {
        Form {
            Section {
                Toggle("Sound effects", isOn: $enabled)
                HStack {
                    Slider(value: $volume, in: 0...1) { Text("Volume") } onEditingChanged: { editing in
                        if !editing { SoundEffects.shared.play(.thwip) }   // hear the new level
                    }
                    Button { SoundEffects.shared.play(.thwip) } label: { Image(systemName: "play.fill") }
                        .help("Play a sample")
                }
                .disabled(!enabled)
                if SoundEffects.shared.has(.stretch) {   // the idle sound; hidden until there is one
                    Toggle("Sounds while he idles on his web", isOn: $ambient)
                        .disabled(!enabled)
                }
            } footer: {
                Text("Sounds play when you drop him: the web shot, letting go, falling and landing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TimerSettings: View {
    @AppStorage(SettingsKey.timerSize) private var size = TimerSize.normal
    @AppStorage(SettingsKey.timerLabelLayout) private var layout = TimerLabelLayout.horizontal
    @AppStorage(SettingsKey.timerAlarm) private var alarm = true
    @AppStorage(SettingsKey.timerNotify) private var notify = true
    @AppStorage(SettingsKey.analyticsCountUnfinished) private var countUnfinished = false
    @State private var alarmPlaying = false

    var body: some View {
        Form {
            Section {
                Picker("Bubble size", selection: $size) {
                    ForEach(TimerSize.allCases) { Text($0.title).tag($0) }
                }
                Picker("Label", selection: $layout) {
                    ForEach(TimerLabelLayout.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Spacer()
                    BubblePreview(font: .pixel, text: "12:34" + layout.separator + "study", size: size.fontSize)
                    Spacer()
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Right-click him for Timer. Add a label as you type (30m #study), or double-click a running timer's bubble to edit it. \"Time's up!\" always shows at the largest size.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("When a timer ends") {
                HStack {
                    Toggle("Play alarm", isOn: $alarm)
                    Spacer()
                    Button {
                        if alarmPlaying {
                            SoundEffects.shared.stop(.timerDone)
                        } else {
                            SoundEffects.shared.play(.timerDone)
                            // back to ▶︎ when the sound ends by itself
                            DispatchQueue.main.asyncAfter(deadline: .now() + SoundEffects.shared.duration(.timerDone)) {
                                alarmPlaying = false
                            }
                        }
                        alarmPlaying.toggle()
                    } label: { Image(systemName: alarmPlaying ? "stop.fill" : "play.fill") }
                        .help(alarmPlaying ? "Stop" : "Play the alarm")
                        .disabled(!alarm)
                }
                Text("Plays for 30 seconds or until you dismiss it, even when other sounds are off. Volume: Sound tab.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("Show a notification", isOn: $notify)
                    Spacer()
                    Button("Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Section {
                Toggle("Count unfinished timers", isOn: $countUnfinished)
            } header: {
                Text("Analytics")
            } footer: {
                Text("When on, a timer you stop early counts for the time it ran. Stopwatches under \(Int(SessionStore.minStopwatchSeconds / 60)) minutes are never counted. History is kept for \(SessionStore.retentionDays) days. Open it from the menu bar: Show Analytics.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .pickerStyle(.segmented)
        .onDisappear {
            SoundEffects.shared.stop(.timerDone)
            alarmPlaying = false
        }
    }
}

/// A static look-alike of the in-app bubble, to compare fonts.
private struct BubblePreview: View {
    let font: BubbleFont
    var text = "Drink some water!"
    var size: CGFloat = 8
    private let ink = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255)

    var body: some View {
        Text(text)
            .font(font == .pixel ? .custom("PressStart2P-Regular", size: size) : .system(size: size * 11 / 8, design: .monospaced))
            .foregroundStyle(ink)
            .padding(6)
            .background(Color.white)
            .overlay(Rectangle().stroke(ink, lineWidth: 2))
    }
}

/// Owns the one Settings window and brings it forward (the app has no Dock icon).
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Spider Buddy Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
