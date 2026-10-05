import UserNotifications

/// macOS notifications for the timer, so a finished timer is noticed even when he is hidden
/// (full-screen video) or you are looking elsewhere. Settings > Timer turns them off.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    /// Called on the main thread when you click the "Time's up!" notification.
    var onTimerFinishedClicked: (() -> Void)?

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Asks for permission the first time (macOS shows its prompt once; later calls do nothing).
    /// Called when a timer starts, not at launch, so the prompt makes sense when it appears.
    func requestPermission() {
        guard Settings.shared.timerNotify else { return }
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                Log.timer.debug("notification permission failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Log.timer.debug("notification permission granted: \(granted, privacy: .public)")
            }
        }
    }

    /// "Time's up!" with which timer it was ("Time's up! — study"). Silent: the alarm sound plays separately.
    func timerFinished(description: String, note: String?) {
        guard Settings.shared.timerNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = note.map { "Time's up! — \($0)" } ?? "Time's up!"
        content.body = "Your \(description) timer has finished."
        let request = UNNotificationRequest(identifier: "timer-finished", content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Log.timer.debug("notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Clears a delivered "Time's up!" once it is dismissed on screen.
    func clearTimerFinished() {
        center.removeDeliveredNotifications(withIdentifiers: ["timer-finished"])
    }

    /// Shows the banner even though Spider Buddy counts as the app in front for its own notifications.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// Clicking the "Time's up!" banner (or its entry in Notification Centre) acknowledges it,
    /// like clicking his bubble: the alarm stops.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == "timer-finished" {
            DispatchQueue.main.async { self.onTimerFinishedClicked?() }
        }
        completionHandler()
    }
}
