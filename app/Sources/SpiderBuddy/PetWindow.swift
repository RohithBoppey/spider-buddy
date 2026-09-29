import AppKit

/// Borderless, transparent panel that floats over other apps on every desktop.
final class PetWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // above the Dock, so he stays visible when crawling in front of it
        level = .statusBar
        // every desktop, never in Cmd-Tab / Mission Control cycling. No .fullScreenAuxiliary:
        // that keeps him out of full-screen spaces (videos, games).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // clicks pass through until the cursor is over an opaque sprite pixel (see AppDelegate)
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
