import Foundation

/// One timer or stopwatch run, as kept for analytics.
struct TimerSession: Codable, Equatable {
    enum Kind: String, Codable { case timer, stopwatch }

    /// A stretch of running time; pauses are the gaps between segments.
    struct Segment: Codable, Equatable {
        var start: Date
        var end: Date
    }

    var id: UUID
    var kind: Kind
    /// Lowercase label ("study"), nil when untagged.
    var tag: String?
    /// A countdown's full length; nil for stopwatches.
    var planned: TimeInterval?
    /// A countdown that reached its end, any stopped stopwatch, or a session cut short by quitting.
    var completed: Bool
    var segments: [Segment]

    /// Time spent running, pauses excluded.
    var activeSeconds: TimeInterval {
        segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var end: Date? { segments.last?.end }
}

/// Saves finished sessions to ~/Library/Application Support/SpiderBuddy/sessions.json and keeps
/// only the last `retentionDays` of them.
final class SessionStore {
    static let shared = SessionStore()

    static let retentionDays = 15
    /// Stopwatches shorter than this are taken as started by accident and not kept.
    static let minStopwatchSeconds: TimeInterval = 2 * 60

    private(set) var sessions: [TimerSession] = []
    private let fileURL: URL
    private var cleanupTimer: Timer?

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SpiderBuddy", isDirectory: true)
    }

    private init() {
        fileURL = Self.directory.appendingPathComponent("sessions.json")
        load()
        removeExpired()
        // once a day, for a Mac that stays up for weeks
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.removeExpired() }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    func record(_ session: TimerSession) {
        var session = session
        session.tag = session.tag.flatMap(DurationParser.cleanNote)   // older builds kept capitals
        if session.kind == .stopwatch && session.activeSeconds < Self.minStopwatchSeconds { return }
        sessions.append(session)
        Log.timer.debug("recorded \(session.kind.rawValue) tag=\(session.tag ?? "-") \(Int(session.activeSeconds))s completed=\(session.completed)")
        removeExpired(saveAnyway: true)
    }

    /// Drops sessions that ended more than `retentionDays` ago; saves when anything changed.
    private func removeExpired(saveAnyway: Bool = false) {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 24 * 60 * 60)
        let kept = sessions.filter { ($0.end ?? .distantPast) > cutoff }
        guard saveAnyway || kept.count != sessions.count else { return }
        sessions = kept
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // no file yet
        do {
            sessions = try Self.decoder.decode([TimerSession].self, from: data)
        } catch {
            // keep the unreadable file aside rather than overwrite it with an empty history
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("sessions.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            Log.timer.error("sessions.json unreadable, moved aside: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            // .atomic writes a temporary file and renames it over the old one, so a crash
            // mid-write never leaves a half-written file
            try Self.encoder.encode(sessions).write(to: fileURL, options: .atomic)
        } catch {
            Log.timer.error("couldn't save sessions: \(error.localizedDescription)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
