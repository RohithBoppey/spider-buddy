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
        }
        // grouped Forms scroll, so they report no height of their own: size the window explicitly
        .frame(width: 480, height: 400)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.size) private var size = PetSize.normal
    @AppStorage(SettingsKey.energy) private var energy = Energy.normal
    @AppStorage(SettingsKey.webLength) private var webLength = WebLength.medium
    @AppStorage(SettingsKey.followActiveDisplay) private var followActiveDisplay = true

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
            } footer: {
                Text("Energy sets how fast he moves and how long he rests. Web length is how far he hangs below the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Picker("With more than one display", selection: $followActiveDisplay) {
                    Text("Follow the active display").tag(true)
                    Text("Stay on the display I leave him on").tag(false)
                }
                .pickerStyle(.radioGroup)
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

/// A static look-alike of the in-app bubble, to compare fonts.
private struct BubblePreview: View {
    let font: BubbleFont
    private let ink = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255)

    var body: some View {
        Text("Drink some water!")
            .font(font == .pixel ? .custom("PressStart2P-Regular", size: 8) : .system(size: 11, design: .monospaced))
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
