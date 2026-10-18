import Foundation

enum GitClient {
    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var cachedBinary: String?

    static func run(args: [String], cwd: URL) async -> GitOutput {
        await Task.detached(priority: .userInitiated) {
            runSync(args: args, cwd: cwd)
        }.value
    }

    /// Runs `base + paths` in batches. Stops after the first non-zero exit and includes that result.
    static func runBatched(base: [String], paths: [String], cwd: URL, batchSize: Int = 80) async -> [GitOutput] {
        guard !paths.isEmpty else { return [] }
        var results: [GitOutput] = []
        var index = 0
        while index < paths.count {
            let end = min(index + batchSize, paths.count)
            let slice = Array(paths[index..<end])
            let output = await run(args: base + slice, cwd: cwd)
            results.append(output)
            if output.exitCode != 0 { break }
            index = end
        }
        return results
    }

    private nonisolated static func runSync(args: [String], cwd: URL) -> GitOutput {
        guard let binary = resolveBinary() else {
            return GitOutput(
                args: args,
                stdout: Data(),
                stderr: Data("未找到 git".utf8),
                exitCode: -1
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["PATH"] = augmentedPath(environment["PATH"])
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return GitOutput(
                args: args,
                stdout: Data(),
                stderr: Data(error.localizedDescription.utf8),
                exitCode: -1
            )
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let group = DispatchGroup()
        let stdoutBox = LockedData()
        let stderrBox = LockedData()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.set(stdoutHandle.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.set(stderrHandle.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        return GitOutput(
            args: args,
            stdout: stdoutBox.get(),
            stderr: stderrBox.get(),
            exitCode: process.terminationStatus
        )
    }

    private nonisolated static func resolveBinary() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedBinary { return cachedBinary }
        let found = locate()
        if let found { cachedBinary = found }
        return found
    }

    /// Prefer a user-installed git (Homebrew, MacPorts) so a Finder-launched app
    /// does not bind to the `/usr/bin/git` shim when a real git is installed.
    private nonisolated static func locate() -> String? {
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        let pathDirs = augmentedPath(ProcessInfo.processInfo.environment["PATH"])
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        let ordered = extra + pathDirs
        for directory in ordered where seen.insert(directory).inserted {
            let candidate = (directory as NSString).appendingPathComponent("git")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        let fallback = "/usr/bin/git"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return fallback
        }
        return nil
    }

    private nonisolated static func augmentedPath(_ existing: String?) -> String {
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"]
        let current = existing?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (extras + current).filter { seen.insert($0).inserted }.joined(separator: ":")
    }
}

private nonisolated final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
