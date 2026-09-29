import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let pet = PetController(library: SpriteLibrary()) else {
            NSApp.terminate(nil)
            return
        }
        self.pet = pet
        setUpStatusItem()
        pet.start()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕷️"
        let menu = NSMenu()
        let title = NSMenuItem(title: "Spider Buddy", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spider Buddy", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
