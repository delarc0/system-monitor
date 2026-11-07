import Foundation

/// The Claude Code weekly allowance, from two sources.
///
/// First, the reading Claude Code saves in its own config file, which a running session
/// keeps fresh about every 5 minutes. It costs one file read and no credentials. Second,
/// when that goes stale, `claude -p /usage`. That text costs no usage but is heavy (8 to
/// 24 s and 500 MB here), so it stays rare and at background priority. Both are
/// undocumented, so a miss on either says "no data": it must never read as 0%.
enum ClaudeSampler {
    /// A login item's PATH has none of these. The symlink is the stable name; its
    /// target changes with every Claude Code update, so it must not be resolved and kept.
    static let binaryPath: String? = [
        NSHomeDirectory() + "/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude"
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    static func fetch() async -> ClaudeUsage? {
        guard let binaryPath else { return nil }
        // Empty directory, so the run can't pick up a project's settings or context.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("system-monitor-claude")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = await runProcess(
            binaryPath,
            ["-p", "/usage", "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config"],
            directory: directory,
            qos: .background,
            timeout: 120
        ) else { return nil }
        return parse(String(decoding: data, as: UTF8.self), now: Date())
    }

    /// Reads `Current week (all models): 57% used · resets Nov 11 at 4pm (Europe/Stockholm)`.
    static func parse(_ text: String, now: Date) -> ClaudeUsage? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains("Current week (all models)") }),
              let match = line.firstMatch(of: /(\d+)% used/),
              let percent = Double(match.1) else { return nil }

        guard let resets = line.firstMatch(of: /resets (.+?)(?: \((.+)\))?$/) else {
            return ClaudeUsage(percent: percent, resets: nil, weekElapsed: nil, readAt: now)
        }
        let when = String(resets.1)
        let zone = resets.2.flatMap { TimeZone(identifier: String($0)) }
        return ClaudeUsage(percent: percent, resets: when, weekElapsed: weekElapsed(resets: when, zone: zone, now: now), readAt: now)
    }

    /// How much of the 7-day window has passed. The text has no year, so it takes the
    /// next occurrence of that date. Nil on anything unexpected, which only hides the pace.
    private static func weekElapsed(resets: String, zone: TimeZone?, now: Date) -> Double? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let year = calendar.component(.year, from: now)

        for format in ["yyyy MMM d 'at' ha", "yyyy MMM d 'at' h:mma"] {
            formatter.dateFormat = format
            guard var date = formatter.date(from: "\(year) \(resets)") else { continue }
            if date < now, let next = formatter.date(from: "\(year + 1) \(resets)") { date = next }
            return weekElapsed(until: date, now: now)
        }
        return nil
    }

    private static func weekElapsed(until reset: Date, now: Date) -> Double? {
        let elapsed = 1 - reset.timeIntervalSince(now) / (7 * 86_400)
        return (0...1).contains(elapsed) ? elapsed : nil
    }

    // MARK: - The saved reading

    private struct Config: Decodable {
        let cachedUsageUtilization: Saved?
        let oauthAccount: Account?

        struct Account: Decodable {
            let accountUuid: String?
        }
        struct Saved: Decodable {
            let fetchedAtMs: Double
            let accountUuid: String?
            let utilization: Utilization
        }
        struct Utilization: Decodable {
            let sevenDay: Window?
        }
        struct Window: Decodable {
            let utilization: Double
            let resetsAt: String?
        }
    }

    static func readSaved() -> ClaudeUsage? {
        let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent(".claude.json")
        return (try? Data(contentsOf: url)).flatMap { parseSaved($0) }
    }

    static func parseSaved(_ data: Data, zone: TimeZone = .current, now: Date = Date()) -> ClaudeUsage? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let config = try? decoder.decode(Config.self, from: data),
              let saved = config.cachedUsageUtilization,
              let week = saved.utilization.sevenDay,
              saved.accountUuid == config.oauthAccount?.accountUuid else { return nil }

        let readAt = Date(timeIntervalSince1970: saved.fetchedAtMs / 1000)
        // Microseconds here, which ISO8601DateFormatter won't parse.
        let reset = week.resetsAt
            .map { $0.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression) }
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        // After the reset this is last week's number, not this week's.
        if let reset, reset <= now { return nil }
        return ClaudeUsage(
            percent: week.utilization,
            resets: reset.map { resetText($0, zone: zone) },
            weekElapsed: reset.flatMap { weekElapsed(until: $0, now: readAt) },
            readAt: readAt
        )
    }

    /// Worded like `/usage`, so the row doesn't change depending on the source.
    private static func resetText(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        formatter.dateFormat = calendar.component(.minute, from: date) == 0 ? "MMM d 'at' ha" : "MMM d 'at' h:mma"
        return formatter.string(from: date)
    }
}
