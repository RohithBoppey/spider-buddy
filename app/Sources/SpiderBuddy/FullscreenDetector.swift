import AppKit
import CoreGraphics

/// Detects a full-screen video or game on a screen, so he can hide there.
/// Editors, terminals etc. in full screen do not count: he stays visible over them.
/// Window bounds and owners are readable without Screen Recording permission.
enum FullscreenDetector {
    /// Video players and browsers (full screen in a browser is almost always a video).
    /// Any installed browser is also detected automatically; this list is a fallback.
    static let hidingApps: Set<String> = [
        // video players
        "org.videolan.vlc", "com.colliderli.iina", "io.mpv", "com.apple.QuickTimePlayerX",
        "com.apple.TV", "com.netflix.Netflix", "com.amazon.aiv.AIVApp", "com.disney.disneyplus",
        "tv.plex.desktop", "com.firecore.infuse",
        // browsers
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "app.zen-browser.zen", "ai.perplexity.comet",
    ]

    private static var isHidingApp: [pid_t: Bool] = [:]   // per-process cache

    static func isFullscreenVideoOrGame(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // CG window bounds use a top-left origin on the primary display; NSScreen uses bottom-left
        let f = screen.frame
        let target = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        // on a notched display, full-screen windows stop below the notch
        let notch = screen.safeAreaInsets.top

        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,                 // normal app windows
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let coversScreen = abs(b.minX - target.minX) < 1 && abs(b.width - target.width) < 1
                && abs(b.maxY - target.maxY) < 1 && b.height >= target.height - notch - 1
            if coversScreen && hidesPet(pid) {
                return true
            }
        }
        return false
    }

    /// Apps from the list, any installed browser, and apps that declare themselves video or games.
    private static func hidesPet(_ pid: pid_t) -> Bool {
        if let cached = isHidingApp[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        var hides = false
        if let id = app?.bundleIdentifier, hidingApps.contains(id) {
            hides = true
        } else if let url = app?.bundleURL {
            if browserURLs().contains(url.standardizedFileURL) {
                hides = true
            } else if let category = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String {
                // public.app-category.video, public.app-category.games and the game sub-genres
                hides = category.contains("games") || category.hasSuffix(".video")
            }
        }
        isHidingApp[pid] = hides
        return hides
    }

    /// Apps macOS can open web links with, i.e. installed browsers.
    private static func browserURLs() -> Set<URL> {
        guard let web = URL(string: "https://example.com") else { return [] }
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: web).map(\.standardizedFileURL))
    }
}
