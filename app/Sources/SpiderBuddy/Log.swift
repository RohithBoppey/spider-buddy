import AppKit
import os

/// Diagnostics for display bugs. Debug level, so it costs nothing unless streamed:
///   log stream --level debug --predicate 'subsystem == "local.spiderbuddy"'
enum Log {
    static let fullscreen = Logger(subsystem: "local.spiderbuddy", category: "fullscreen")
    static let display = Logger(subsystem: "local.spiderbuddy", category: "display")
}

extension NSScreen {
    /// Short description for logs: "id=1 frame=(0,0,1512,982) visible=(0,0,1512,945)".
    var logDescription: String {
        "id=\(displayID.map(String.init) ?? "?") frame=\(frame.logDescription) visible=\(visibleFrame.logDescription)"
    }
}

extension CGRect {
    var logDescription: String {
        "(\(Int(minX)),\(Int(minY)),\(Int(width)),\(Int(height)))"
    }
}
