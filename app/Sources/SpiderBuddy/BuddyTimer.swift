import Foundation

/// A countdown timer or a stopwatch, one at a time. Times come from the clock, not from
/// animation ticks, so skipped ticks (paused, hidden) never make it drift.
final class BuddyTimer {
    enum State {
        case idle
        case countdown(end: Date, total: TimeInterval)
        case countdownPaused(left: TimeInterval, total: TimeInterval)
        case stopwatch(start: Date)                     // start shifted forward by time spent paused
        case stopwatchPaused(elapsed: TimeInterval)
        case finished(at: Date, total: TimeInterval)    // "Time's up!" until dismissed
    }

    static let maxSeconds: TimeInterval = 24 * 60 * 60
    /// One-click lengths in hub > Timer.
    static let presets: [TimeInterval] = [5 * 60, 15 * 60, 25 * 60]

    private(set) var state = State.idle
    /// How the running countdown was asked for, if not as a length ("3:00 PM" for "@3pm").
    private(set) var label: String?
    var now: () -> Date = Date.init                     // replaceable in tests

    /// Running or paused (not idle, not finished).
    var isActive: Bool {
        switch state {
        case .countdown, .countdownPaused, .stopwatch, .stopwatchPaused: return true
        case .idle, .finished: return false
        }
    }

    var isPaused: Bool {
        switch state {
        case .countdownPaused, .stopwatchPaused: return true
        default: return false
        }
    }

    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    func start(seconds: TimeInterval, label: String? = nil) {
        self.label = label
        let seconds = min(max(seconds, 1), Self.maxSeconds)
        state = .countdown(end: now().addingTimeInterval(seconds), total: seconds)
    }

    func startStopwatch() {
        label = nil
        state = .stopwatch(start: now())
    }

    func togglePause() {
        let now = now()
        switch state {
        case .countdown(let end, let total): state = .countdownPaused(left: end.timeIntervalSince(now), total: total)
        case .countdownPaused(let left, let total): state = .countdown(end: now.addingTimeInterval(left), total: total)
        case .stopwatch(let start): state = .stopwatchPaused(elapsed: now.timeIntervalSince(start))
        case .stopwatchPaused(let elapsed): state = .stopwatch(start: now.addingTimeInterval(-elapsed))
        case .idle, .finished: break
        }
    }

    /// Stops a running timer or dismisses "Time's up!".
    func stop() {
        state = .idle
    }

    /// Turns a countdown that has run out into `.finished`. True exactly once per timer.
    func checkFinished() -> Bool {
        guard case .countdown(let end, let total) = state, now() >= end else { return false }
        state = .finished(at: end, total: total)
        return true
    }

    /// The countdown's full length (running, paused or finished), for messages like "Your 25m timer".
    var total: TimeInterval? {
        switch state {
        case .countdown(_, let total), .countdownPaused(_, let total), .finished(_, let total): return total
        default: return nil
        }
    }

    /// The countdown for messages: "25m", "1h 30m", or its clock time ("3:00 PM").
    var description: String? {
        label ?? total.map(DurationParser.describe)
    }

    /// What the bubble shows: time left (rounded up, so it never reads 0:00 while running)
    /// or time elapsed, as "4:05", "12:34" or "1:02:03".
    var display: String {
        let now = now()
        switch state {
        case .countdown(let end, _): return Self.clock(end.timeIntervalSince(now).rounded(.up))
        case .countdownPaused(let left, _): return Self.clock(left.rounded(.up))
        case .stopwatch(let start): return Self.clock(now.timeIntervalSince(start).rounded(.down))
        case .stopwatchPaused(let elapsed): return Self.clock(elapsed.rounded(.down))
        case .idle, .finished: return Self.clock(0)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Reads what you type into the timer bubble.
enum DurationParser {
    enum Result: Equatable {
        case countdown(TimeInterval)
        /// Until a clock time ("@3pm"): seconds from now, and the time as shown ("3:00 PM").
        case until(TimeInterval, label: String)
        case stopwatch
    }

    /// Durations: "45m", "90s", "2h30m", "1h 30m", "1.5h", "2 mins", "1:30" (m:ss),
    /// "1:30:45" (h:mm:ss), "25" (minutes), "pomodoro" (25m).
    /// Clock times: "@3pm", "@3:30pm", "@15:30" (24-hour), "@5" (5 AM or 5 PM, whichever is next);
    /// a time already past today means tomorrow.
    /// "stopwatch" / "sw". Nil for anything else, for zero, and for more than 24 hours.
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "stopwatch", "sw": return .stopwatch
        case "pomodoro", "pomo": return .countdown(25 * 60)
        default: break
        }
        if text.hasPrefix("@") {
            return untilClockTime(String(text.dropFirst()).trimmingCharacters(in: .whitespaces), now: now, calendar: calendar)
        }
        guard let seconds = clockSeconds(text) ?? unitSeconds(text) ?? Int(text).map({ Double($0) * 60 }),
              seconds >= 1, seconds <= BuddyTimer.maxSeconds else { return nil }
        return .countdown(seconds.rounded())
    }

    /// Short description for menus and messages: "1h 30m", "45m", "1m 30s".
    static func describe(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let parts = [(total / 3600, "h"), (total / 60 % 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    /// "1:30" = 1 min 30 s, "1:30:45" = 1 h 30 min 45 s. Later fields must be under 60.
    private static func clockSeconds(_ text: String) -> TimeInterval? {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2 || fields.count == 3,
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = fields.compactMap { Int($0) }
        guard values.count == fields.count, values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return TimeInterval(values.reduce(0) { $0 * 60 + $1 })
    }

    /// "2h30m", "1h 30m", "1.5h", "90s", "2 mins", "1 hour 5 minutes": numbers (decimals allowed)
    /// with h/m/s units, each at most once, in that order.
    private static func unitSeconds(_ text: String) -> TimeInterval? {
        let number = #"(\d+(?:\.\d+)?)"#
        let pattern = "^(?:\(number)\\s*(?:h|hr|hrs|hour|hours))?\\s*(?:\(number)\\s*(?:m|min|mins|minute|minutes))?"
            + "\\s*(?:\(number)\\s*(?:s|sec|secs|second|seconds))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var total: TimeInterval = 0, found = false
        for (group, unit) in [(1, 3600.0), (2, 60.0), (3, 1.0)] {
            guard let range = Range(match.range(at: group), in: text), let value = Double(text[range]) else { continue }
            total += value * unit
            found = true
        }
        return found ? total : nil
    }

    /// "3pm", "3:30pm", "3 pm", "12am", "15:30", "0:15", "5", "5:30". With am/pm, or an hour
    /// 0 or 13-23, the time is exact; a bare 1-12 means whichever of AM or PM comes next.
    private static func untilClockTime(_ text: String, now: Date, calendar: Calendar) -> Result? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text), let hour = Int(text[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        let suffix = Range(match.range(at: 3), in: text).map { String(text[$0]) }
        guard minute < 60 else { return nil }

        let hours: [Int]   // 24-hour candidates
        if let suffix {
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12 + (suffix.hasPrefix("p") ? 12 : 0)]
        } else if hour == 0 || (13...23).contains(hour) {
            hours = [hour]
        } else if (1...12).contains(hour) {
            hours = [hour % 12, hour % 12 + 12]
        } else {
            return nil
        }

        let targets = hours.compactMap { h -> Date? in
            guard let today = calendar.date(bySettingHour: h, minute: minute, second: 0, of: now) else { return nil }
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        guard let target = targets.min() else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return .until(target.timeIntervalSince(now).rounded(), label: formatter.string(from: target))
    }
}
