import Foundation

@main
struct MergePreviewTests {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gitsync-merge-tests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try testSuggestedBase()
    try await testCleanMerge(root: root)
    try await testConflictsAndWorktreeSafety(root: root)
    try await testRenameAndBinary(root: root)
    try await testUnrelatedAndInvalidReferences(root: root)
    print("PASS: smart base selection, clean merges, conflicts, special paths, rename/delete, binary, unrelated histories, worktree safety")
  }

  private static func testSuggestedBase() throws {
    let branches = [branch("main"), branch("develop"), branch("origin/main", remote: true)]
    precondition(GitMergePreview.suggestedBase(branches: branches, headBranch: "feature/login", remoteDefault: nil) == "refs/heads/develop")
    precondition(GitMergePreview.suggestedBase(branches: branches, headBranch: "develop", remoteDefault: nil) == "refs/heads/main")
    precondition(GitMergePreview.suggestedBase(branches: branches, headBranch: "hotfix/urgent", remoteDefault: nil) == "refs/heads/main")
    precondition(GitMergePreview.suggestedBase(branches: branches, headBranch: "main", remoteDefault: nil) == "refs/heads/develop")
    precondition(GitMergePreview.suggestedBase(branches: [branch("main"), branch("origin/main", remote: true)], headBranch: "main", remoteDefault: nil) == nil)
    precondition(GitMergePreview.suggestedBase(branches: [branch("origin/main", remote: true)], headBranch: "topic", remoteDefault: nil) == "refs/remotes/origin/main")
    let custom = [branch("other"), branch("upstream/stable", remote: true)]
    precondition(GitMergePreview.suggestedBase(branches: custom, headBranch: "topic", remoteDefault: "refs/remotes/upstream/stable") == "refs/remotes/upstream/stable")
    precondition(GitMergePreview.suggestedBase(branches: [], headBranch: "topic", remoteDefault: nil) == nil)
    do {
      _ = try GitMergePreview.parseMergeTree(Data("invalid\0".utf8), exitCode: 0)
      preconditionFailure("Malformed output must fail")
    } catch {}
    do {
      _ = try GitMergePreview.parseMergeTree(Data((String(repeating: "a", count: 40) + "\0\0").utf8), exitCode: 1)
      preconditionFailure("Conflict exit without conflict paths must fail")
    } catch {}
  }

  private static func testCleanMerge(root: URL) async throws {
    let repository = try await makeRepository(root: root, name: "clean")
    try write("initial\n", path: "shared.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "-b", "feature/clean"], repository)
    try write("feature\n", path: "feature.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "main"], repository)
    try write("main\n", path: "main.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "feature/clean"], repository)
    try await git(["update-ref", "refs/remotes/origin/main", "main"], repository)
    try await git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], repository)
    let choices = try await GitMergePreview.branches(repository: repository, headBranch: "feature/clean")
    precondition(choices.defaultReference == "refs/heads/main")
    precondition(!choices.branches.contains { $0.name == "origin/HEAD" || $0.name == "feature/clean" })
    let result = try await GitMergePreview.check(repository: repository, base: "refs/heads/main", headBranch: "feature/clean")
    precondition(!result.hasConflicts)
    precondition(result.mergeBaseHash != result.baseHash && result.mergeBaseHash != result.headHash)
    let comparison = ComparisonRequest(
      repositoryPath: repository.path, baseHash: result.mergeBaseHash, headHash: result.headHash,
      baseLabel: "ancestor", headLabel: "feature/clean")
    let files = try await GitComparison.files(comparison)
    precondition(files.map(\.path) == ["feature.txt"])
    let diff = try await GitComparison.diff(comparison, file: files[0])
    precondition(diff.lines.contains { $0.kind == .add && $0.text.contains("feature") })
    let text = try await GitMergePreview.mergedFile(repository: repository, result: result, path: "feature.txt")
    precondition(text == "feature\n")
    let identical = try await GitMergePreview.check(repository: repository, base: "refs/heads/feature/clean", headBranch: "feature/clean")
    precondition(!identical.hasConflicts)
  }

  private static func testConflictsAndWorktreeSafety(root: URL) async throws {
    let repository = try await makeRepository(root: root, name: "conflicts")
    let paths = ["conflict.txt", "space name.txt", "tab\tname.txt", "line\nbreak.txt", "-option.txt", "\u{6587}\u{4ef6}.txt"]
    for path in paths { try write("initial\n", path: path, repository: repository) }
    try write("delete me\n", path: "deleted.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "-b", "feature/conflict"], repository)
    for path in paths { try write("feature\n", path: path, repository: repository) }
    try await git(["rm", "deleted.txt"], repository)
    try await commit(repository)
    try await git(["checkout", "main"], repository)
    for path in paths { try write("base\n", path: path, repository: repository) }
    try write("modified on base\n", path: "deleted.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "feature/conflict"], repository)
    try write("staged\n", path: "staged.txt", repository: repository)
    try await git(["add", "staged.txt"], repository)
    try write("unstaged\n", path: "staged.txt", repository: repository)
    try write("keep me\n", path: "untracked.txt", repository: repository)
    try write("dirty conflict file\n", path: "conflict.txt", repository: repository)
    let statusBefore = try await git(["status", "--porcelain=v1", "-z"], repository).stdout
    let indexBefore = try await git(["write-tree"], repository).stdout
    let headBefore = try await git(["rev-parse", "HEAD"], repository).stdout
    let result = try await GitMergePreview.check(repository: repository, base: "refs/heads/main", headBranch: "feature/conflict")
    precondition(Set(result.conflictPaths) == Set(paths + ["deleted.txt"]))
    let preview = try await GitMergePreview.mergedFile(repository: repository, result: result, path: "conflict.txt")
    precondition(preview.contains("<<<<<<<") && preview.contains("base") && preview.contains("feature"))
    let statusAfter = try await git(["status", "--porcelain=v1", "-z"], repository).stdout
    let indexAfter = try await git(["write-tree"], repository).stdout
    let headAfter = try await git(["rev-parse", "HEAD"], repository).stdout
    precondition(statusBefore == statusAfter && indexBefore == indexAfter && headBefore == headAfter)
    let workingText = try String(contentsOf: repository.appendingPathComponent("conflict.txt"), encoding: .utf8)
    precondition(workingText == "dirty conflict file\n")
    precondition(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(".git/MERGE_HEAD").path))
  }

  private static func testRenameAndBinary(root: URL) async throws {
    let repository = try await makeRepository(root: root, name: "rename-binary")
    try write("original\n", path: "old.txt", repository: repository)
    try Data([0, 1, 2]).write(to: repository.appendingPathComponent("binary.dat"))
    try await commit(repository)
    try await git(["checkout", "-b", "feature/rename"], repository)
    try await git(["mv", "old.txt", "feature.txt"], repository)
    try Data([0, 3, 4]).write(to: repository.appendingPathComponent("binary.dat"))
    try await commit(repository)
    try await git(["checkout", "main"], repository)
    try await git(["mv", "old.txt", "base.txt"], repository)
    try Data([0, 5, 6]).write(to: repository.appendingPathComponent("binary.dat"))
    try await commit(repository)
    let result = try await GitMergePreview.check(repository: repository, base: "refs/heads/main", headBranch: "feature/rename")
    precondition(result.hasConflicts && result.conflictPaths.contains("binary.dat"))
    precondition(result.conflictPaths.contains("old.txt") || result.conflictPaths.contains("feature.txt"))
    do {
      _ = try await GitMergePreview.mergedFile(repository: repository, result: result, path: "binary.dat")
      preconditionFailure("Binary preview must fail")
    } catch {}
  }

  private static func testUnrelatedAndInvalidReferences(root: URL) async throws {
    let repository = try await makeRepository(root: root, name: "unrelated")
    try write("base\n", path: "base.txt", repository: repository)
    try await commit(repository)
    try await git(["checkout", "--orphan", "unrelated"], repository)
    try write("independent history\n", path: "independent.txt", repository: repository)
    try await commit(repository)
    do {
      _ = try await GitMergePreview.check(repository: repository, base: "refs/heads/main", headBranch: "unrelated")
      preconditionFailure("Unrelated histories must not be reported clean")
    } catch {}
    do {
      _ = try await GitMergePreview.check(repository: repository, base: "refs/heads/missing", headBranch: "unrelated")
      preconditionFailure("Missing references must not be reported clean")
    } catch {}
  }

  private static func branch(_ name: String, remote: Bool = false) -> MergePreviewBranch {
    MergePreviewBranch(reference: (remote ? "refs/remotes/" : "refs/heads/") + name, name: name, isRemote: remote)
  }

  private static func makeRepository(root: URL, name: String) async throws -> URL {
    let repository = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    try await git(["init", "-b", "main"], repository)
    try await git(["config", "user.name", "Merge Preview Tests"], repository)
    try await git(["config", "user.email", "merge-preview@example.invalid"], repository)
    try await git(["config", "core.autocrlf", "false"], repository)
    try await git(["config", "core.hooksPath", "/dev/null"], repository)
    return repository
  }

  private static func write(_ text: String, path: String, repository: URL) throws {
    try Data(text.utf8).write(to: repository.appendingPathComponent(path))
  }

  private static func commit(_ repository: URL) async throws {
    try await git(["add", "-A"], repository)
    try await git(["commit", "--no-gpg-sign", "--allow-empty", "-m", "test snapshot"], repository)
  }

  @discardableResult
  private static func git(_ args: [String], _ repository: URL) async throws -> GitOutput {
    let output = await GitClient.run(args: args, cwd: repository)
    guard output.exitCode == 0 else {
      throw GitMergePreview.Failure(message: output.commandLine + "\n" + output.stderrText)
    }
    return output
  }
}