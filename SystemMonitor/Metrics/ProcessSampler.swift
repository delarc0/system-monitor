import Foundation

/// Top-process sampler.
///
/// Shells out to `/bin/ps`. `proc_pid_rusage` would avoid the subprocess, but it
/// returns EPERM for processes owned by other users, which would silently drop
/// every root daemon (WindowServer, kernel_task, the Spotlight workers), the exact
/// rows you want when the machine is busy.
///
/// Raw executable names are close to useless in a list: a browser or editor shows
/// up as a dozen "… Helper (Renderer)" rows, and system work appears as bare daemon
/// names. Every row is therefore resolved to its owning application bundle and
/// aggregated by that name, so all of Code's helpers collapse into one
/// "Visual Studio Code" row carrying the summed cost.
actor ProcessSampler {
    /// Resolution touches the filesystem, so it's cached per executable path: a few
    /// dozen entries that stay valid for the session.
    private var resolvedCache: [String: ResolvedApp] = [:]

    private struct ResolvedApp {
        let name: String
        let bundlePath: String?
    }

    private struct Aggregate {
        var cpu: Double
        var rssKB: Double
        let app: ResolvedApp
        let path: String
        var count: Int
    }

    /// Nil when `ps` failed, so the panel keeps its last rows instead of going blank.
    func sampleTops(count: Int = 5) async -> TopProcesses? {
        // LC_ALL=C: under a Swedish locale `ps` prints 145,6, which no number parser accepts.
        guard let data = await runProcess(
            "/bin/ps", ["-Axo", "%cpu=,rss=,comm="], environment: ["LC_ALL": "C"], timeout: 5
        ) else { return nil }

        var aggregate: [String: Aggregate] = [:]
        for row in Self.parseRows(String(decoding: data, as: UTF8.self)) {
            let app = resolve(row.executablePath)
            aggregate[app.name, default: Aggregate(cpu: 0, rssKB: 0, app: app, path: row.executablePath, count: 0)].cpu += row.cpu
            aggregate[app.name]?.rssKB += row.rssKB
            aggregate[app.name]?.count += 1
        }

        func entries(by metric: (Aggregate) -> Double, prefix: String) -> [ProcessEntry] {
            aggregate
                .filter { metric($0.value) > 0 }
                .sorted { metric($0.value) > metric($1.value) }
                .prefix(count)
                .map { name, value in
                    ProcessEntry(
                        id: "\(prefix)-\(name)",
                        name: name,
                        value: metric(value),
                        bundlePath: value.app.bundlePath,
                        executablePath: value.path,
                        instances: value.count
                    )
                }
        }

        return TopProcesses(
            cpu: entries(by: { $0.cpu }, prefix: "cpu"),
            memory: entries(by: { $0.rssKB / 1024 / 1024 }, prefix: "mem")
        )
    }

    // MARK: - Name resolution

    /// A handful of system processes whose human name is Apple's own product
    /// name. Deliberately short: anything not listed keeps its real executable
    /// name rather than a label we made up.
    private static let systemNames: [String: String] = [
        "WindowServer": "Window Server",
        "backupd": "Time Machine",
        "backupd-helper": "Time Machine",
        "bird": "iCloud",
        "cloudd": "iCloud",
        "coreaudiod": "Core Audio",
        "corespotlightd": "Spotlight",
        "mds": "Spotlight",
        "mds_stores": "Spotlight",
        "mdsync": "Spotlight",
        "mdsyncd": "Spotlight",
        "mdworker": "Spotlight",
        "mdworker_shared": "Spotlight",
        "photoanalysisd": "Photos",
        "photolibraryd": "Photos",
        "WindowManager": "Window Manager"
    ]

    private func resolve(_ executablePath: String) -> ResolvedApp {
        if let cached = resolvedCache[executablePath] { return cached }
        let resolved = uncachedResolve(executablePath)
        // Build and temp binaries have unique paths; dropping the cache every
        // few hundred entries is cheaper than remembering them forever.
        if resolvedCache.count >= 512 { resolvedCache.removeAll() }
        resolvedCache[executablePath] = resolved
        return resolved
    }

    private func uncachedResolve(_ executablePath: String) -> ResolvedApp {
        if let bundlePath = outermostBundlePath(in: executablePath) {
            // The name Finder, the Dock and Spotlight show. Info.plist can't be used:
            // VS Code sets both name keys to "Code" while every surface says
            // "Visual Studio Code".
            let shown = FileManager.default.displayName(atPath: bundlePath)
            let name = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
            return ResolvedApp(name: name, bundlePath: bundlePath)
        }

        let executable = (executablePath as NSString).lastPathComponent
        return ResolvedApp(name: Self.systemNames[executable] ?? executable, bundlePath: nil)
    }

    /// The *outermost* `.app` is what a person means by "the app": VS Code's
    /// renderer lives at `…/Visual Studio Code.app/Contents/Frameworks/Code
    /// Helper (Renderer).app/Contents/MacOS/…`, and the useful answer there is
    /// "Visual Studio Code", not the helper.
    private func outermostBundlePath(in executablePath: String) -> String? {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }

    // MARK: - ps

    struct ProcessRow {
        let executablePath: String
        let cpu: Double
        let rssKB: Double
    }

    /// `%cpu` and `rss` come first so the remainder of the line, which can contain
    /// spaces ("…/Code Helper (Renderer)"), is the full command path.
    static func parseRows(_ output: String) -> [ProcessRow] {
        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let cpuEnd = trimmed.firstIndex(of: " ") else { continue }
            let afterCPU = trimmed[cpuEnd...].drop(while: { $0 == " " })
            guard let rssEnd = afterCPU.firstIndex(of: " ") else { continue }
            let path = String(afterCPU[rssEnd...].drop(while: { $0 == " " }))

            guard let cpu = Double(trimmed[..<cpuEnd]), let rss = Double(afterCPU[..<rssEnd]), !path.isEmpty else { continue }
            // The `ps` we just spawned is always in its own output.
            if path == "/bin/ps" { continue }
            rows.append(ProcessRow(executablePath: path, cpu: cpu, rssKB: rss))
        }
        return rows
    }
}
