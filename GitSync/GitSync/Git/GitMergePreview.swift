import Foundation

nonisolated struct MergePreviewRequest: Codable, Hashable, Sendable {
  var id = UUID()
  let repositoryPath: String
  let headBranch: String
}

nonisolated struct MergePreviewBranch: Identifiable, Hashable, Sendable {
  let reference: String
  let name: String
  let isRemote: Bool
  var id: String { reference }

  var shortName: String {
    guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
    return String(name[name.index(after: slash)...])
  }
}

nonisolated struct MergePreviewBranches: Sendable {
  let branches: [MergePreviewBranch]
  let defaultReference: String?
}

nonisolated struct MergePreviewResult: Sendable {
  let baseHash: String
  let headHash: String
  let mergeBaseHash: String
  let treeHash: String
  let conflictPaths: [String]
  var hasConflicts: Bool { !conflictPaths.isEmpty }
}

enum GitMergePreview {
  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func branches(repository: URL, headBranch: String) async throws -> MergePreviewBranches {
    let output = await GitClient.run(
      args: ["for-each-ref", "--format=%(refname)%09%(symref)", "refs/heads", "refs/remotes"],
      cwd: repository)
    try requireSuccess(output)
    var branches: [MergePreviewBranch] = []
    var remoteDefault: String?
    for line in output.stdoutText.split(separator: "\n") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 2 else { continue }
      let reference = String(fields[0])
      if !fields[1].isEmpty {
        if remoteDefault == nil || reference == "refs/remotes/origin/HEAD" {
          remoteDefault = String(fields[1])
        }
        continue
      }
      let isRemote = reference.hasPrefix("refs/remotes/")
      let prefix = isRemote ? "refs/remotes/" : "refs/heads/"
      guard reference != "refs/heads/" + headBranch else { continue }
      branches.append(
        MergePreviewBranch(
          reference: reference, name: String(reference.dropFirst(prefix.count)), isRemote: isRemote)
      )
    }
    return MergePreviewBranches(
      branches: branches,
      defaultReference: suggestedBase(
        branches: branches, headBranch: headBranch, remoteDefault: remoteDefault))
  }

  nonisolated static func suggestedBase(
    branches: [MergePreviewBranch], headBranch: String, remoteDefault: String?
  ) -> String? {
    let prefersMain =
      ["main", "master", "develop"].contains(headBranch)
      || headBranch.hasPrefix("hotfix/")
    let preferredNames =
      prefersMain
      ? ["main", "master", "develop", "trunk"] : ["develop", "main", "master", "trunk"]
    let candidates = branches.filter { $0.shortName != headBranch }
    for name in preferredNames {
      let matches = candidates.filter { $0.shortName == name }
      if let local = matches.first(where: { !$0.isRemote }) { return local.reference }
      if let origin = matches.first(where: { $0.name == "origin/" + name }) {
        return origin.reference
      }
      if let remote = matches.first { return remote.reference }
    }
    if let remoteDefault, candidates.contains(where: { $0.reference == remoteDefault }) {
      return remoteDefault
    }
    return candidates.first(where: { !$0.isRemote })?.reference ?? candidates.first?.reference
  }

  static func check(repository: URL, base: String, headBranch: String) async throws
    -> MergePreviewResult
  {
    let baseHash = try await resolve(base, repository: repository)
    let headHash = try await resolve("refs/heads/" + headBranch, repository: repository)
    let ancestor = await GitClient.run(args: ["merge-base", baseHash, headHash], cwd: repository)
    if ancestor.exitCode == 1 {
      throw Failure(
        message: L10n.text(
          "这两个分支没有共同祖先，无法进行 PR 合并预检。",
          "These branches have no common ancestor and cannot be checked as a PR merge."))
    }
    try requireSuccess(ancestor)
    let output = await GitClient.run(
      args: ["merge-tree", "--write-tree", "--name-only", "-z", baseHash, headHash],
      cwd: repository, timeout: 120,
      environmentOverrides: ["LC_ALL": "C"])
    guard output.exitCode == 0 || output.exitCode == 1 else {
      throw Failure(
        message: L10n.text(
          "无法预检合并。此功能需要 Git 2.38 或更新版本。",
          "Unable to preview merge. This feature requires Git 2.38 or later.")
          + "\n" + output.commandLine + "\n" + output.stderrText)
    }
    let parsed = try parseMergeTree(output.stdout, exitCode: output.exitCode)
    return MergePreviewResult(
      baseHash: baseHash, headHash: headHash,
      mergeBaseHash: ancestor.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines),
      treeHash: parsed.treeHash, conflictPaths: parsed.paths)
  }

  nonisolated static func parseMergeTree(_ data: Data, exitCode: Int32) throws -> (
    treeHash: String, paths: [String]
  ) {
    let fields = data.split(separator: 0, omittingEmptySubsequences: false)
    guard let first = fields.first else { throw Failure(message: "Invalid merge-tree output") }
    let treeHash = String(decoding: first, as: UTF8.self)
    guard [40, 64].contains(treeHash.count), treeHash.allSatisfy({ $0.isHexDigit }) else {
      throw Failure(message: "Invalid merge-tree tree hash")
    }
    let paths = fields.dropFirst().prefix(while: { !$0.isEmpty }).map {
      String(decoding: $0, as: UTF8.self)
    }
    guard (exitCode == 0 && paths.isEmpty) || (exitCode == 1 && !paths.isEmpty) else {
      throw Failure(message: "Incomplete merge-tree conflict output")
    }
    return (treeHash, Array(Set(paths)).sorted())
  }

  static func mergedFile(repository: URL, result: MergePreviewResult, path: String) async throws
    -> String
  {
    let object = result.treeHash + ":" + path
    let size = await GitClient.run(args: ["cat-file", "-s", object], cwd: repository)
    try requireSuccess(size)
    guard let byteCount = Int(size.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)),
      byteCount <= 2_000_000
    else {
      throw Failure(
        message: L10n.text("文件过大，无法显示文本预览。", "This file is too large for a text preview."))
    }
    let output = await GitClient.run(args: ["cat-file", "blob", object], cwd: repository)
    try requireSuccess(output)
    guard !output.stdout.contains(0), let text = String(data: output.stdout, encoding: .utf8) else {
      throw Failure(
        message: L10n.text("二进制文件无法显示文本预览。", "Binary files cannot be previewed as text."))
    }
    return text
  }

  private static func resolve(_ reference: String, repository: URL) async throws -> String {
    let output = await GitClient.run(
      args: ["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"], cwd: repository)
    try requireSuccess(output)
    return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func requireSuccess(_ output: GitOutput) throws {
    guard output.exitCode == 0 else {
      throw Failure(message: output.commandLine + "\n" + output.stderrText)
    }
  }
}
