import Foundation

/// Top-process sampler.
///
/// Shells out to `/bin/ps` once per tick. `proc_pid_rusage` would avoid the
/// subprocess, but it returns EPERM for processes owned by other users, which
/// would silently drop every root daemon (WindowServer, kernel_task, the
/// Spotlight workers), the exact rows you want when the machine is busy.
///
/// Raw executable names are close to useless in a list: a browser or editor
/// shows up as a dozen "… Helper (Renderer)" rows, and system work appears as
/// bare daemon names. Every row is therefore resolved to its owning application
/// bundle and aggregated by that name, so all of Code's helpers collapse into
/// one "Visual Studio Code" row carrying the summed cost.
/// An actor rather than a struct: it owns a mutable resolution cache and does
/// blocking work (spawning `ps`), so it must stay off the main actor and be
/// serialized against itself.
actor ProcessSampler {
    /// Resolution touches the filesystem (`Bundle(path:)`), so it's cached per
    /// executable path: a few dozen entries that stay valid for the session.
    private var resolvedCache: [String: ResolvedApp] = [:]

    struct ResolvedApp: Sendable {
        let name: String
        let bundlePath: String?
    }

    func sampleTops(n: Int = 5) -> (topCPU: [ProcessEntry], topMemory: [ProcessEntry]) {
        var aggregate: [String: (cpu: Double, rssKB: Double, app: ResolvedApp, path: String, count: Int)] = [:]

        for row in listProcesses() {
            let app = resolve(row.executablePath)
            if var existing = aggregate[app.name] {
                existing.cpu += row.cpu
                existing.rssKB += row.rssKB
                existing.count += 1
                aggregate[app.name] = existing
            } else {
                aggregate[app.name] = (row.cpu, row.rssKB, app, row.executablePath, 1)
            }
        }

        func entries(
            by metric: (_ value: (cpu: Double, rssKB: Double, app: ResolvedApp, path: String, count: Int)) -> Double,
            prefix: String
        ) -> [ProcessEntry] {
            aggregate
                .filter { metric($0.value) > 0 }
                .sorted { metric($0.value) > metric($1.value) }
                .prefix(n)
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

        return (
            topCPU: entries(by: { $0.cpu }, prefix: "cpu"),
            topMemory: entries(by: { $0.rssKB / 1024 / 1024 }, prefix: "mem")
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
            let directoryName = (bundlePath as NSString).lastPathComponent
            let name = bundleDisplayName(at: bundlePath) ?? Self.strippingAppSuffix(directoryName)
            return ResolvedApp(name: name, bundlePath: bundlePath)
        }

        let executable = (executablePath as NSString).lastPathComponent
        if let known = Self.systemNames[executable] {
            return ResolvedApp(name: known, bundlePath: nil)
        }
        return ResolvedApp(name: executable, bundlePath: nil)
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

    /// `FileManager.displayName` is the name Finder, the Dock and Spotlight all
    /// show, which is the name a person actually knows the app by. The Info.plist
    /// keys are only a fallback: VS Code, for one, sets both `CFBundleDisplayName`
    /// and `CFBundleName` to "Code" while every surface calls it
    /// "Visual Studio Code".
    /// Only the trailing extension: a bundle legitimately named
    /// "MyApp.appcast.app" must not come out as "Mycast".
    private static func strippingAppSuffix(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func bundleDisplayName(at path: String) -> String? {
        let displayName = FileManager.default.displayName(atPath: path)
        if !displayName.isEmpty, displayName != "/" {
            return Self.strippingAppSuffix(displayName)
        }

        guard let bundle = Bundle(path: path) else { return nil }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = bundle.localizedInfoDictionary?[key] as? String, !name.isEmpty { return name }
            if let name = bundle.infoDictionary?[key] as? String, !name.isEmpty { return name }
        }
        return nil
    }

    // MARK: - ps

    private struct ProcessRow {
        let executablePath: String
        let cpu: Double
        let rssKB: Double
    }

    private func listProcesses() -> [ProcessRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // %cpu + rss first so the remainder of the line (which can contain
        // spaces, e.g. "…/Code Helper (Renderer)") is the full command path.
        task.arguments = ["-Axo", "%cpu=,rss=,comm="]
        let stdout = Pipe()
        task.standardOutput = stdout
        // /dev/null, not a Pipe: nothing ever drains stderr, so a Pipe there
        // would deadlock the child the moment it filled that buffer.
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }
        // Drain stdout BEFORE waitUntilExit to avoid a pipe-buffer deadlock
        // when the child fills the pipe (ps with full comm paths easily does).
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let cpuEnd = trimmed.firstIndex(of: " ") else { continue }
            let cpuStr = trimmed[..<cpuEnd]
            let afterCPU = trimmed[cpuEnd...].drop(while: { $0 == " " })
            guard let rssEnd = afterCPU.firstIndex(of: " ") else { continue }
            let rssStr = afterCPU[..<rssEnd]
            let path = String(afterCPU[rssEnd...].drop(while: { $0 == " " }))

            guard let cpu = Double(cpuStr), let rss = Double(rssStr), !path.isEmpty else { continue }
            // The `ps` we just spawned is always in its own output.
            if path == "/bin/ps" { continue }
            rows.append(ProcessRow(executablePath: path, cpu: cpu, rssKB: rss))
        }
        return rows
    }
}
