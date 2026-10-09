import AppKit

/// "Show Analytics": writes today's sessions into a self-contained HTML page (data, Chart.js and
/// styles inline) and opens it in the browser. The page is a snapshot; clicking again makes a new one.
enum AnalyticsReport {
    /// What the page gets for each session: today's part of it only.
    private struct Row: Encodable {
        let tag: String?
        let kind: TimerSession.Kind
        let start: Double            // ms since 1970, for JS Date
        let end: Double
        let seconds: Double          // running time today, pauses excluded
        let pausedSeconds: Double
        let planned: Double?
        let completed: Bool
        let fromYesterday: Bool      // began before midnight; only today's part is counted
    }

    private struct Payload: Encodable {
        let generatedAt: Double
        let countUnfinished: Bool
        let minStopwatchMinutes: Int
        let sessions: [Row]
    }

    static func show() {
        do {
            let url = try write(sessions: SessionStore.shared.sessions, now: Date())
            NSWorkspace.shared.open(url)
        } catch {
            Log.timer.error("analytics report failed: \(error.localizedDescription)")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't open analytics"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Today's rows: sessions cut to midnight...now, timers stopped early left out unless the setting says so.
    private static func rows(_ sessions: [TimerSession], now: Date, calendar: Calendar = .current) -> [Row] {
        let dayStart = calendar.startOfDay(for: now)
        let countUnfinished = Settings.shared.analyticsCountUnfinished
        return sessions.compactMap { session in
            if session.kind == .timer && !session.completed && !countUnfinished { return nil }
            let today = session.segments.compactMap { segment -> TimerSession.Segment? in
                let start = max(segment.start, dayStart), end = min(segment.end, now)
                return end > start ? .init(start: start, end: end) : nil
            }
            guard let first = today.first, let last = today.last else { return nil }
            let seconds = today.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            return Row(tag: session.tag, kind: session.kind,
                       start: first.start.timeIntervalSince1970 * 1000, end: last.end.timeIntervalSince1970 * 1000,
                       seconds: seconds, pausedSeconds: max(0, last.end.timeIntervalSince(first.start) - seconds),
                       planned: session.planned, completed: session.completed,
                       fromYesterday: session.segments.first.map { $0.start < dayStart } ?? false)
        }
        .sorted { $0.start < $1.start }
    }

    private static func write(sessions: [TimerSession], now: Date) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "analytics-template", withExtension: "html"),
              let chartURL = Bundle.main.url(forResource: "chart.umd.min", withExtension: "js") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The report template is missing from the app."])
        }
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        let chartJS = try String(contentsOf: chartURL, encoding: .utf8)

        let payload = Payload(generatedAt: now.timeIntervalSince1970 * 1000,
                              countUnfinished: Settings.shared.analyticsCountUnfinished,
                              minStopwatchMinutes: Int(SessionStore.minStopwatchSeconds / 60),
                              sessions: rows(sessions, now: now))
        // "<" only occurs inside strings (tags), so escaping it keeps a tag like "</script>" inert
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")

        let html = template
            .replacingOccurrences(of: "/*@CHARTJS@*/", with: chartJS)
            .replacingOccurrences(of: "/*@DATA@*/null", with: json)

        try FileManager.default.createDirectory(at: SessionStore.directory, withIntermediateDirectories: true)
        let url = SessionStore.directory.appendingPathComponent("analytics.html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
