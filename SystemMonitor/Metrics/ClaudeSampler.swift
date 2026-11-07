import Foundation

/// The Claude Code weekly allowance, read from `claude -p /usage`.
///
/// That text is the only free source that works everywhere. The status line JSON
/// only moves in an interactive CLI session, so a machine running through the Agent
/// SDK went stale and read 0%. The call costs nothing but is heavy (about 8 s and
/// 500 MB here), so it stays on a slow cadence at background priority. If the wording
/// ever changes the row says "no data": a parse miss must never read as 0%.
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
            ["-p", "/usage", "--no-session-persistence", "--setting-sources", ""],
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
            let elapsed = 1 - date.timeIntervalSince(now) / (7 * 86_400)
            return (0...1).contains(elapsed) ? elapsed : nil
        }
        return nil
    }
}
