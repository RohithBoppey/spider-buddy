import AppKit
import Sparkle

/// In-app updates via Sparkle. Checks automatically (at launch when due, daily, and after the
/// Mac wakes), and on demand from the menu. The update window is Sparkle's standard one:
/// release notes plus Install Update / Remind Me Later / Skip This Version.
/// Feed and public key: SUFeedURL / SUPublicEDKey in Info.plist.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// After waking, check only if the last check is at least this old.
    private let wakeCheckInterval: TimeInterval = 60 * 60

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    private var updater: SPUUpdater { controller.updater }

    /// Settings > General > "Check for updates automatically".
    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Menu: Check for Updates…
    @objc func checkForUpdates(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(sender)
    }

    @objc private func didWake() {
        guard updater.automaticallyChecksForUpdates, updater.canCheckForUpdates else { return }
        if let last = updater.lastUpdateCheckDate, Date().timeIntervalSince(last) < wakeCheckInterval { return }
        updater.checkForUpdatesInBackground()
    }

    // MARK: - SPUStandardUserDriverDelegate

    // A menu-bar app has no Dock icon to badge, so Sparkle should show scheduled updates itself
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Bring the update window in front of other apps when it appears.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate { NSApp.activate(ignoringOtherApps: true) }
    }
}
