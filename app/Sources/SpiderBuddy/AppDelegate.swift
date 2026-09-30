import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var pet: PetController?
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var hideItem: NSMenuItem!
    private var bubblesItem: NSMenuItem!
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let pet = PetController(library: SpriteLibrary()) else {
            NSApp.terminate(nil)
            return
        }
        self.pet = pet
        SpeechBubble.registerFont()
        setUpStatusItem()
        pet.start()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Spidey's eyes as a template image: macOS tints it for light and dark menu bars
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            icon.accessibilityDescription = "Spider Buddy"
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "🕷️"
        }

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Spider Buddy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        pauseItem = item("Pause", #selector(togglePause), key: "p")
        hideItem = item("Hide Spider Buddy", #selector(toggleHidden), key: "h")
        menu.addItem(pauseItem)
        menu.addItem(hideItem)

        let sendTo = NSMenuItem(title: "Send to", action: nil, keyEquivalent: "")
        let edges = NSMenu()
        for (name, tag) in [("Top", 0), ("Bottom", 1), ("Left", 2), ("Right", 3)] {
            let edge = item(name, #selector(sendTo(_:)))
            edge.tag = tag
            edges.addItem(edge)
        }
        sendTo.submenu = edges
        menu.addItem(sendTo)

        bubblesItem = item("Speech Bubbles", #selector(toggleBubbles))
        menu.addItem(bubblesItem)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("About Spider Buddy", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spider Buddy", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Refreshes checkmarks and titles each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let pet else { return }
        pauseItem.state = pet.isPaused ? .on : .off
        hideItem.title = pet.isHiddenByUser ? "Show Spider Buddy" : "Hide Spider Buddy"
        bubblesItem.state = Settings.shared.bubblesEnabled ? .on : .off
    }

    @objc private func togglePause() {
        guard let pet else { return }
        pet.setPaused(!pet.isPaused)
    }

    @objc private func toggleHidden() {
        guard let pet else { return }
        pet.setHidden(!pet.isHiddenByUser)
    }

    @objc private func sendTo(_ sender: NSMenuItem) {
        let edges: [PetController.Edge] = [.top, .bottom, .left, .right]
        pet?.send(to: edges[sender.tag])
    }

    @objc private func toggleBubbles() {
        Settings.shared.bubblesEnabled.toggle()
        pet?.bubblesSettingChanged()
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Spider Buddy",
            .credits: NSAttributedString(
                string: "Your friendly neighborhood desktop pet.\nSprites and character © Marvel. Personal project.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}
