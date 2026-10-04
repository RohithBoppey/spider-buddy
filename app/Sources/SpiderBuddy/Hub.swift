import AppKit

/// What the hub (right-click on him) offers, kept apart from how it is drawn: today a native
/// menu (HubMenu); a custom pixel bar can later draw the same items.
enum HubItem {
    case action(String, () -> Void)
    case toggle(String, isOn: Bool, () -> Void)
    case submenu(String, [HubItem])
    case comingSoon(String)                   // greyed out until the feature ships
    case separator
}

/// Shows hub items as a native context menu at the click.
enum HubMenu {
    /// Blocks until the menu closes; the chosen item's action has run by then.
    static func popUp(_ items: [HubItem], with event: NSEvent, for view: NSView) {
        NSMenu.popUpContextMenu(menu(for: items), with: event, for: view)
    }

    private static func menu(for items: [HubItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item {
            case .action(let title, let run):
                menu.addItem(ClosureMenuItem(title, run))
            case .toggle(let title, let isOn, let run):
                let menuItem = ClosureMenuItem(title, run)
                menuItem.state = isOn ? .on : .off
                menu.addItem(menuItem)
            case .submenu(let title, let children):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.submenu = self.menu(for: children)
                menu.addItem(menuItem)
            case .comingSoon(let title):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let text = NSMutableAttributedString(string: title, attributes: [
                    .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.disabledControlTextColor,
                ])
                text.append(NSAttributedString(string: "   coming soon", attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
                menuItem.attributedTitle = text
                menuItem.isEnabled = false
                menu.addItem(menuItem)
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}

/// A menu item that runs a closure (the menu keeps the item, and so the closure, alive).
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func runAction() { run() }
}
