import Foundation

/// Top-process sampler. Shells out to /bin/ps once per tick — pragmatic, avoids
/// libproc / bridging for the same info. At 2s polling the overhead is negligible.
struct ProcessSampler {
    func sampleTops(n: Int = 5) -> (topCPU: [ProcessEntry], topMemory: [ProcessEntry]) {
        let raw = listProcesses()

        let topCPU = raw
            .filter { $0.cpu > 0 }
            .sorted { $0.cpu > $1.cpu }
            .prefix(n)
            .map { ProcessEntry(id: "cpu-\($0.name)", name: $0.name, value: $0.cpu) }

        var memAgg: [String: Double] = [:]
        for p in raw {
            memAgg[p.name, default: 0] += p.rssKB
        }
        let topMem = memAgg
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { ProcessEntry(id: "mem-\($0.key)", name: $0.key, value: $0.value / 1024 / 1024) }

        return (Array(topCPU), Array(topMem))
    }

    private struct ProcessRow {
        let name: String
        let cpu: Double
        let rssKB: Double
    }

    private func listProcesses() -> [ProcessRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Axo", "comm=,%cpu=,rss="]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed.split(separator: " ").filter { !$0.isEmpty }
            guard tokens.count >= 3,
                  let rss = Double(tokens[tokens.count - 1]),
                  let cpu = Double(tokens[tokens.count - 2]) else { continue }
            let cmdPath = tokens[0..<(tokens.count - 2)].joined(separator: " ")
            let name = (cmdPath as NSString).lastPathComponent
            if name.isEmpty { continue }
            rows.append(ProcessRow(name: name, cpu: cpu, rssKB: rss))
        }
        return rows
    }
}
