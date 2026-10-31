import Foundation

@main
struct HistorySearchTests {
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
    _ = try git(["init", "-b", "main"], at: directory)
    let tree = try git(["mktree"], at: directory)
    var hashes: [String] = []
    for index in 0..<106 {
      var arguments = ["commit-tree", tree, "-m", "Commit \(index)"]
      if let parent = hashes.last { arguments += ["-p", parent] }
      hashes.append(try git(arguments, at: directory, author: index == 0 ? "Bob" : "Alice [Dev]"))
    }
    _ = try git(["update-ref", "refs/heads/main", hashes.last!], at: directory)
    let side = try git(["commit-tree", tree, "-p", hashes[0], "-m", "Side branch"], at: directory,
      author: "Charlie")
    _ = try git(["update-ref", "refs/heads/side", side], at: directory)

    let model = AppModel()
    model.repositoryPath = directory.path
    defer { model.closeWindow() }

    model.searchHistory(String(hashes[0].prefix(10)).uppercased(), field: .hash)
    try await waitForHistory(model)
    precondition(model.commits.map(\.hash) == [hashes[0]], "Must search beyond the initial page")
    precondition(!model.canLoadMoreHistory)

    model.searchHistory(hashes[0], field: .hash)
    try await waitForHistory(model)
    precondition(model.commits.map(\.hash) == [hashes[0]])

    model.searchHistory("  aLiCe [dev]\n", field: .author)
    try await waitForHistory(model)
    precondition(model.historySearchQuery == "aLiCe [dev]")
    precondition(model.commits.count == 100 && model.canLoadMoreHistory)
    precondition(model.commits.allSatisfy { $0.authorName == "Alice [Dev]" })
    await model.loadMoreHistory()
    precondition(model.commits.count == 105 && !model.canLoadMoreHistory)
    precondition(Set(model.commits.map(\.hash)).count == 105)

    model.searchHistory("Bob", field: .author)
    try await waitForHistory(model)
    precondition(model.commits.map(\.hash) == [hashes[0]])

    model.searchHistory("Charlie", field: .author)
    try await waitForHistory(model)
    precondition(model.commits.isEmpty && !model.canLoadMoreHistory)
    model.setHistoryScope(.all)
    try await waitForHistory(model)
    precondition(model.commits.map(\.hash) == [side])
    model.setHistoryScope(.mainline)
    try await waitForHistory(model)
    precondition(model.commits.isEmpty)

    model.searchHistory("--all", field: .hash)
    try await waitForHistory(model)
    precondition(model.commits.isEmpty && model.failure == nil)
    model.searchHistory("", field: .hash)
    try await waitForHistory(model)
    precondition(model.commits.count == 100 && model.canLoadMoreHistory)
    await model.loadMoreHistory()
    precondition(model.commits.count == 106 && !model.canLoadMoreHistory)
    print("PASS: full and partial hash, old commits, literal author names, case, whitespace, pagination, scopes, no results and clear")
  }

  @MainActor
  private static func waitForHistory(_ model: AppModel) async throws {
    let deadline = Date().addingTimeInterval(15)
    while model.isWorking {
      precondition(Date() < deadline, "History refresh timed out")
      try await Task.sleep(for: .milliseconds(10))
    }
    precondition(model.failure == nil, "History refresh failed")
  }

  private static func git(_ arguments: [String], at directory: URL, author: String = "Fixture") throws
    -> String
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_AUTHOR_NAME"] = author
    environment["GIT_AUTHOR_EMAIL"] = "fixture@example.invalid"
    environment["GIT_COMMITTER_NAME"] = "Fixture"
    environment["GIT_COMMITTER_EMAIL"] = "fixture@example.invalid"
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, String(decoding: errorData, as: UTF8.self))
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}