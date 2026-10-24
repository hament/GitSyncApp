import Darwin
import Foundation

enum GitClient {
    @TaskLocal static var owner: UUID?
    @TaskLocal static var operationEpoch: Int?
    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var cachedBinary: String?
    private nonisolated static let processes = ProcessRegistry()

    static func run(args: [String], cwd: URL, timeout: TimeInterval = 30, environmentOverrides: [String: String] = [:]) async -> GitOutput {
        let owner = Self.owner
        let epoch = operationEpoch ?? processes.epoch(for: owner)
        guard !Task.isCancelled, epoch == processes.epoch(for: owner) else {
            return GitOutput(args: args, stdout: Data(), stderr: Data("Canceled".utf8), exitCode: -1)
        }
        return await Task.detached(priority: .userInitiated) {
            runSync(args: args, cwd: cwd, timeout: timeout, owner: owner, epoch: epoch, environmentOverrides: environmentOverrides)
        }.value
    }

    nonisolated static func cancel(owner: UUID) {
        processes.cancel(owner: owner)
    }

    nonisolated static func currentEpoch(owner: UUID) -> Int {
        processes.epoch(for: owner)
    }

    /// Runs `base + paths` in batches. Stops after the first non-zero exit and includes that result.
    static func runBatched(base: [String], paths: [String], cwd: URL, batchSize: Int = 80) async -> [GitOutput] {
        guard !paths.isEmpty else { return [] }
        var results: [GitOutput] = []
        let epoch = processes.epoch(for: owner)
        var index = 0
        while index < paths.count {
            guard epoch == processes.epoch(for: owner) else { break }
            let end = min(index + batchSize, paths.count)
            let slice = Array(paths[index..<end])
            let output = await run(args: base + slice, cwd: cwd)
            results.append(output)
            if output.exitCode != 0 { break }
            index = end
        }
        return results
    }

    private nonisolated static func runSync(args: [String], cwd: URL, timeout: TimeInterval, owner: UUID?, epoch: Int, environmentOverrides: [String: String]) -> GitOutput {
        guard let binary = resolveBinary() else {
            return GitOutput(
                args: args,
                stdout: Data(),
                stderr: Data("未找到 git / Git not found".utf8),
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
        environment.merge(environmentOverrides) { _, override in override }
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminated.signal()
        }

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
        processes.register(process, owner: owner, epoch: epoch)
        defer { processes.unregister(process) }

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

        var timedOut = false
        if terminated.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            processes.terminate(process)
            if terminated.wait(timeout: .now() + 1) == .timedOut {
                processes.terminate(process, force: true)
                terminated.wait()
            }
        }
        if group.wait(timeout: .now() + 2) == .timedOut {
            processes.terminate(process, force: true)
            _ = group.wait(timeout: .now() + 1)
        }

        var stderr = stderrBox.get()
        if timedOut {
            let suffix = "\n命令执行超过 \(Int(timeout)) 秒，已自动终止。 / Command exceeded \(Int(timeout)) seconds and was terminated automatically.\n"
            stderr.append(Data(suffix.utf8))
        }
        return GitOutput(
            args: args,
            stdout: stdoutBox.get(),
            stderr: stderr,
            exitCode: timedOut ? 124 : process.terminationStatus
        )
    }

    nonisolated static func resolveBinary() -> String? {
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

nonisolated final class ProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [Int32: (process: Process, owner: UUID?, group: Int32?)] = [:]
    private var epochs: [UUID: Int] = [:]

    func epoch(for owner: UUID?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return owner.map { epochs[$0, default: 0] } ?? 0
    }

    func register(_ process: Process, owner: UUID?, epoch: Int) {
        lock.lock()
        defer { lock.unlock() }
        let pid = process.processIdentifier
        running[pid] = (process, owner, getpgid(pid) == pid ? pid : nil)
        if let owner, epochs[owner, default: 0] != epoch, process.isRunning {
            signalLocked(process, force: false)
            scheduleEscalation(process)
        }
    }

    func unregister(_ process: Process) {
        lock.lock()
        running.removeValue(forKey: process.processIdentifier)
        lock.unlock()
    }

    func cancel(owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        epochs[owner, default: 0] += 1
        for entry in running.values where entry.owner == owner {
            signalLocked(entry.process, force: false)
            scheduleEscalation(entry.process)
        }
    }

    func terminate(_ process: Process, force: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        signalLocked(process, force: force)
        if !force { scheduleEscalation(process) }
    }

    private func signalLocked(_ process: Process, force: Bool) {
        if let entry = running[process.processIdentifier], entry.process === process, let group = entry.group {
            kill(-group, force ? SIGKILL : SIGTERM)
        } else if process.isRunning {
            kill(process.processIdentifier, force ? SIGKILL : SIGTERM)
        }
    }

    private func scheduleEscalation(_ process: Process) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock()
            defer { lock.unlock() }
            guard running[process.processIdentifier]?.process === process else { return }
            signalLocked(process, force: true)
        }
    }
}

struct WindowGitClient {
    let owner = UUID()

    func run(args: [String], cwd: URL, timeout: TimeInterval = 30) async -> GitOutput {
        await GitClient.$owner.withValue(owner) {
            await GitClient.run(args: args, cwd: cwd, timeout: timeout)
        }
    }

    func runBatched(base: [String], paths: [String], cwd: URL, batchSize: Int = 80) async -> [GitOutput] {
        await GitClient.$owner.withValue(owner) {
            await GitClient.runBatched(base: base, paths: paths, cwd: cwd, batchSize: batchSize)
        }
    }

    func perform<Value>(_ operation: () async throws -> Value) async rethrows -> Value {
        let epoch = GitClient.operationEpoch ?? GitClient.currentEpoch(owner: owner)
        return try await GitClient.$owner.withValue(owner) {
            try await GitClient.$operationEpoch.withValue(epoch, operation: operation)
        }
    }

    func performCancellable<Value>(_ operation: () async throws -> Value) async rethrows -> Value {
        let owner = owner
        return try await withTaskCancellationHandler {
            try await perform(operation)
        } onCancel: {
            GitClient.cancel(owner: owner)
        }
    }

    func cancel() {
        GitClient.cancel(owner: owner)
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
