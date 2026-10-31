import Foundation

@main
struct PullStrategyTests {
  @MainActor
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("GIT_CONFIG_") {
      unsetenv(key)
    }
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
    setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    setenv("GIT_AUTHOR_NAME", "Pull Fixture", 1)
    setenv("GIT_AUTHOR_EMAIL", "fixture@example.invalid", 1)
    setenv("GIT_COMMITTER_NAME", "Pull Fixture", 1)
    setenv("GIT_COMMITTER_EMAIL", "fixture@example.invalid", 1)
    setenv("GIT_EDITOR", "true", 1)
    setenv("LC_ALL", "C", 1)

    let remote = directory.appendingPathComponent("remote.git")
    let seed = directory.appendingPathComponent("seed")
    _ = await git(["init", "--bare", "--initial-branch=main", remote.path], at: directory)
    _ = await git(["init", "--initial-branch=main", seed.path], at: directory)
    try Data("base\n".utf8).write(to: seed.appendingPathComponent("base.txt"))
    _ = await git(["add", "--", "base.txt"], at: seed)
    _ = await git(["commit", "-m", "Base"], at: seed)
    _ = await git(["remote", "add", "origin", remote.path], at: seed)
    _ = await git(["push", "-u", "origin", "main"], at: seed)

    let names = ["merge", "rebase", "configured", "ff-only", "conflict", "fast-forward"]
    var originals: [String: String] = [:]
    for name in names {
      let repository = directory.appendingPathComponent(name)
      _ = await git(["clone", remote.path, repository.path], at: directory)
      if name != "fast-forward" {
        let filename = name == "conflict" ? "base.txt" : "local.txt"
        try Data("local\n".utf8).write(to: repository.appendingPathComponent(filename))
        _ = await git(["add", "--", filename], at: repository)
        _ = await git(["commit", "-m", "Local"], at: repository)
      }
      originals[name] = await git(["rev-parse", "HEAD"], at: repository)
    }
    try Data("remote\n".utf8).write(to: seed.appendingPathComponent("base.txt"))
    _ = await git(["add", "--", "base.txt"], at: seed)
    _ = await git(["commit", "-m", "Remote"], at: seed)
    _ = await git(["push"], at: seed)
    let remoteHead = await git(["rev-parse", "HEAD"], at: seed)

    let mergeRepository = directory.appendingPathComponent("merge")
    let mergeModel = model(at: mergeRepository)
    defer { mergeModel.closeWindow() }
    await mergeModel.pull()
    precondition(mergeModel.dialog == .pullStrategy && mergeModel.failure == nil)
    let unchangedHead = await git(["rev-parse", "HEAD"], at: mergeRepository)
    precondition(unchangedHead == originals["merge"])
    mergeModel.dialog = nil
    let cancelledHead = await git(["rev-parse", "HEAD"], at: mergeRepository)
    precondition(cancelledHead == unchangedHead)
    await mergeModel.pull(strategy: .merge)
    precondition(mergeModel.failure == nil && !mergeModel.isWorking)
    let mergeParents = await git(["rev-list", "--parents", "-n", "1", "HEAD"], at: mergeRepository)
    precondition(mergeParents.split(separator: " ").count == 3)
    precondition(mergeParents.contains(originals["merge"]!) && mergeParents.contains(remoteHead))
    _ = await git(["config", "--local", "--get", "pull.rebase"], at: mergeRepository, exitCode: 1)
    _ = await git(["config", "--local", "--get", "pull.ff"], at: mergeRepository, exitCode: 1)

    for name in ["rebase", "configured"] {
      let repository = directory.appendingPathComponent(name)
      let rebaseModel = model(at: repository)
      if name == "configured" {
        _ = await git(["config", "pull.rebase", "true"], at: repository)
        await rebaseModel.pull()
      } else {
        await rebaseModel.pull()
        precondition(rebaseModel.dialog == .pullStrategy)
        rebaseModel.dialog = nil
        await rebaseModel.pull(strategy: .rebase)
      }
      precondition(rebaseModel.failure == nil && rebaseModel.dialog == nil)
      let rebasedHead = await git(["rev-parse", "HEAD"], at: repository)
      let rebasedParent = await git(["rev-parse", "HEAD^"], at: repository)
      precondition(rebasedHead != originals[name] && rebasedParent == remoteHead)
      precondition(FileManager.default.fileExists(atPath: repository.appendingPathComponent("local.txt").path))
      rebaseModel.closeWindow()
    }

    let ffRepository = directory.appendingPathComponent("ff-only")
    _ = await git(["config", "pull.ff", "only"], at: ffRepository)
    let ffModel = model(at: ffRepository)
    await ffModel.pull()
    precondition(ffModel.failure != nil && ffModel.dialog == nil)
    let ffHead = await git(["rev-parse", "HEAD"], at: ffRepository)
    precondition(ffHead == originals["ff-only"])
    ffModel.closeWindow()

    let fastForwardRepository = directory.appendingPathComponent("fast-forward")
    let fastForwardModel = model(at: fastForwardRepository)
    await fastForwardModel.pull()
    precondition(fastForwardModel.failure == nil && fastForwardModel.dialog == nil)
    let fastForwardHead = await git(["rev-parse", "HEAD"], at: fastForwardRepository)
    precondition(fastForwardHead == remoteHead)
    fastForwardModel.closeWindow()

    let conflictRepository = directory.appendingPathComponent("conflict")
    let conflictModel = model(at: conflictRepository)
    await conflictModel.pull(strategy: .merge)
    precondition(conflictModel.failure != nil && conflictModel.mergeInProgress)
    precondition(conflictModel.files.contains { $0.kind == .conflict })
    _ = await git(["merge", "--abort"], at: conflictRepository)
    conflictModel.closeWindow()

    print("PASS: divergence prompt, cancel, merge, rebase, configured rebase, ff-only preservation, fast-forward and merge conflicts")
  }

  @MainActor
  private static func model(at repository: URL) -> AppModel {
    let model = AppModel()
    model.repositoryPath = repository.path
    return model
  }

  @MainActor
  private static func git(_ arguments: [String], at directory: URL, exitCode: Int32 = 0) async -> String {
    let output = await GitClient.run(args: arguments, cwd: directory)
    precondition(output.exitCode == exitCode, output.commandLine + "\n" + output.stderrText)
    return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}