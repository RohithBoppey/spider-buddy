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
        _ = SessionStore.shared       // loads history and drops sessions older than 15 days
        pet.timer.onSessionEnded = { SessionStore.shared.record($0) }
        pet.onHubRequested = { [weak self] event, view in self?.showHub(with: event, for: view) }
        SpeechBubble.registerFont()
        _ = Updater.shared            // starts automatic update checks
        setUpStatusItem()
        pet.start()
    }

    /// A timer or stopwatch still running is saved as a complete session.
    func applicationWillTerminate(_ notification: Notification) {
        pet?.timer.endForQuit()
    }

    // MARK: - Hub (right-click on him)

    /// Pet actions (and Quit); Settings and updates live in the menu-bar menu.
    private func showHub(with event: NSEvent, for view: NSView) {
        guard let pet else { return }
        let edges: [(String, PetController.Edge)] = [("Top", .top), ("Bottom", .bottom), ("Left", .left), ("Right", .right)]
        let items: [HubItem] = [
            .submenu("Send to", edges.map { name, edge in .action(name) { pet.send(to: edge) } }),
            .toggle("Pause", isOn: pet.isPaused) { pet.setPaused(!pet.isPaused) },
            .toggle("Speech Bubbles", isOn: Settings.shared.bubblesEnabled) { [weak self] in self?.toggleBubbles() },
            .toggle("Sounds", isOn: Settings.shared.sfxEnabled) { Settings.shared.sfxEnabled.toggle() },
            .separator,
        ] + timerHubItems(pet) + [
            .comingSoon("Ask AI"),
            .separator,
            .action("Quit") { NSApp.terminate(nil) },
        ]
        HubMenu.popUp(items, with: event, for: view)
    }

    /// Timer… and Stopwatch when idle; Pause/Resume (with the time and label) and Stop while one runs.
    private func timerHubItems(_ pet: PetController) -> [HubItem] {
        let timer = pet.timer
        if timer.isActive {
            let kind = timer.total == nil ? "stopwatch" : "timer"
            let status = [timer.display, timer.note].compactMap { $0 }.joined(separator: " ")
            return [
                .action("\(timer.isPaused ? "Resume" : "Pause") \(kind) · \(status)") { pet.toggleTimerPause() },
                .action("Stop \(kind)") { pet.stopTimer() },
            ]
        }
        return [
            // after the menu has closed, so the typing bubble can take the keyboard
            .action("Timer…") { DispatchQueue.main.async { pet.askForTimer() } },
            .action("Stopwatch") { pet.startStopwatch() },
        ]
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

        menu.addItem(item("Show Analytics", #selector(showAnalytics)))

        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = Updater.shared
        menu.addItem(updates)
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

    @objc private func showAnalytics() {
        AnalyticsReport.show()
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Spider Buddy",
            .credits: NSAttributedString(
                string: "Your friendly neighborhood desktop pet.\nSprites and character © Marvel. Personal project.\n"
                    + "Sound effects by Kenney and artisticdude (CC0), foolboymedia (CC BY-NC 4.0) and thirsk (CC BY 4.0).",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}
