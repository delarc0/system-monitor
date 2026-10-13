import Foundation

/// Claude Code plan usage. There is no official API for the 5-hour and 7-day
/// windows; the documented source is the JSON Claude Code pipes to its
/// statusline script on every turn, which `~/.claude/statusline.sh` mirrors to
/// this file. It only moves while a Claude Code session is running, so
/// `updatedAt` is part of the sample.
struct ClaudeSampler {
    // shortcut: ignores CLAUDE_CONFIG_DIR, honour it if Erik ever sets one.
    private let url = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/usage-latest.json")

    func sample() -> ClaudeSample? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { return nil }
        let now = Date()
        func resets(_ window: [String: Any]?) -> Date? {
            (window?["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        }
        // Claude Code drops a window from the JSON once it resets, and a file
        // written before the reset still carries the old figure: both are 0.
        func percent(_ window: [String: Any]?) -> Double {
            guard let reset = resets(window), reset > now else { return 0 }
            return window?["used_percentage"] as? Double ?? 0
        }
        let five = limits["five_hour"] as? [String: Any]
        let seven = limits["seven_day"] as? [String: Any]
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ClaudeSample(
            fiveHourPercent: percent(five),
            sevenDayPercent: percent(seven),
            fiveHourResetsAt: resets(five),
            sevenDayResetsAt: resets(seven),
            sessionCostUSD: (root["cost"] as? [String: Any])?["total_cost_usd"] as? Double,
            updatedAt: modified ?? now
        )
    }
}
