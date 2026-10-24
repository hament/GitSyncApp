import Foundation

enum GitComparison {
  struct Failure: LocalizedError {
    let output: GitOutput

    var errorDescription: String? {
      output.commandLine + "\n" + output.stderrText
    }
  }

  static func snapshot(repository: URL, reference: String, label: String, headLabel: String)
    async throws -> ComparisonRequest
  {
    let base = try await resolve("HEAD", repository: repository)
    let head = try await resolve(reference, repository: repository)
    let targetLabel: String
    if reference.hasPrefix("refs/heads/") || reference.hasPrefix("refs/remotes/") {
      targetLabel = label
    } else {
      targetLabel = await branchLabel(for: head, repository: repository) ?? String(head.prefix(7))
    }
    return ComparisonRequest(
      repositoryPath: repository.path, baseHash: base, headHash: head,
      baseLabel: headLabel, headLabel: targetLabel
    )
  }

  private static func branchLabel(for hash: String, repository: URL) async -> String? {
    let output = await GitClient.run(
      args: [
        "for-each-ref", "--format=%(refname)%09%(symref)", "--points-at", hash, "refs/heads",
        "refs/remotes",
      ],
      cwd: repository
    )
    guard output.exitCode == 0 else { return nil }
    let names = output.stdoutText.split(separator: "\n").compactMap { line -> String? in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 2, fields[1].isEmpty else { return nil }
      let name = String(fields[0])
      if name.hasPrefix("refs/heads/") { return String(name.dropFirst("refs/heads/".count)) }
      if name.hasPrefix("refs/remotes/") { return String(name.dropFirst("refs/remotes/".count)) }
      return nil
    }
    return names.isEmpty ? nil : names.joined(separator: ", ")
  }

  private static func resolve(_ reference: String, repository: URL) async throws -> String {
    let output = await GitClient.run(
      args: ["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"], cwd: repository
    )
    guard output.exitCode == 0 else { throw Failure(output: output) }
    return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func files(_ request: ComparisonRequest) async throws -> [CommitFile] {
    let output = await GitClient.run(
      args: [
        "diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "--find-renames",
        request.baseHash, request.headHash, "--",
      ],
      cwd: URL(fileURLWithPath: request.repositoryPath, isDirectory: true)
    )
    guard output.exitCode == 0 else { throw Failure(output: output) }
    return LogParser.parseNameStatus(output.stdout)
  }

  static func diff(_ request: ComparisonRequest, file: CommitFile) async throws -> DiffDocument {
    let paths = [file.path] + (file.oldPath.map { [$0] } ?? [])
    let output = await GitClient.run(
      args: [
        "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--find-renames", request.baseHash,
        request.headHash, "--",
      ]
        + paths.map { ":(literal)" + $0 },
      cwd: URL(fileURLWithPath: request.repositoryPath, isDirectory: true)
    )
    guard output.exitCode == 0 else { throw Failure(output: output) }
    return DiffParser.parse(output.stdoutText)
  }
}
