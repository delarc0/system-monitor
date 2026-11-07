import Foundation

/// Runs a command and returns its stdout, or nil if it failed or overran `timeout`.
///
/// Stdout goes to a temp file, not a Pipe: a Pipe deadlocks a child that fills it
/// unless drained, and reading one to EOF never returns while any grandchild still
/// holds it open, even after the child is killed.
func runProcess(
    _ path: String,
    _ arguments: [String],
    environment: [String: String]? = nil,
    directory: URL? = nil,
    qos: QualityOfService = .default,
    timeout: TimeInterval
) async -> Data? {
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("sysmon-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
          let output = try? FileHandle(forWritingTo: outputURL) else { return nil }
    defer {
        try? output.close()
        try? FileManager.default.removeItem(at: outputURL)
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    if let environment { task.environment = environment }
    if let directory { task.currentDirectoryURL = directory }
    task.qualityOfService = qos
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = output
    task.standardError = FileHandle.nullDevice

    return await withCheckedContinuation { continuation in
        task.terminationHandler = { finished in
            let succeeded = finished.terminationStatus == 0 && finished.terminationReason == .exit
            continuation.resume(returning: succeeded ? try? Data(contentsOf: outputURL) : nil)
        }
        do {
            try task.run()
        } catch {
            continuation.resume(returning: nil)
            return
        }
        // Process is thread-safe for these two reads; the checker can't know that.
        nonisolated(unsafe) let running = task
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if running.isRunning { kill(running.processIdentifier, SIGKILL) }
        }
    }
}
