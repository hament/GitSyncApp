import Foundation

enum GitTags {
  struct ValidationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  struct Failure: LocalizedError {
    let output: GitOutput
    var errorDescription: String? { output.commandLine + "\n" + output.stderrText }
  }

  private static func checked(_ args: [String], repository: URL, timeout: TimeInterval = 30)
    async throws -> GitOutput
  {
    let output = await GitClient.run(args: args, cwd: repository, timeout: timeout)
    guard output.exitCode == 0 else { throw Failure(output: output) }
    return output
  }

  static func target(reference: String, label: String, repository: URL) async throws -> TagTarget {
    let resolved = try await checked(
      ["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"], repository: repository
    )
    let hash = resolved.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    let output = try await checked(
      ["log", "-1", "--format=%H%x1f%P%x1f%D%x1f%an%x1f%ae%x1f%at%x1f%s%x1e", hash, "--"],
      repository: repository)
    guard let commit = LogParser.parseCommits(output.stdoutText).first else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return TagTarget(commit: commit, label: label)
  }

  static func list(repository: URL) async throws -> [TagRecord] {
    let format =
      [
        "%(refname)", "%(objecttype)", "%(objectname)", "%(*objectname)",
        "%(taggername)", "%(taggerdate:unix)", "%(creatordate:unix)",
        "%(subject)", "%(contents)", "%(*objecttype)",
      ].joined(separator: "%00") + "%00"
    let output = try await checked(
      ["for-each-ref", "--sort=-creatordate", "--format=" + format, "refs/tags"],
      repository: repository)
    let fields = output.stdoutText.components(separatedBy: "\0")
    var tags: [TagRecord] = []
    var index = 0
    while index + 9 < fields.count {
      let name = fields[index].trimmingCharacters(in: .newlines)
      let annotated = fields[index + 1] == "tag"
      if name.hasPrefix("refs/tags/"),
        fields[index + 1] == "commit" || (annotated && fields[index + 9] == "commit")
      {
        tags.append(
          TagRecord(
            name: String(name.dropFirst("refs/tags/".count)), objectHash: fields[index + 2],
            commitHash: annotated ? fields[index + 3] : fields[index + 2], isAnnotated: annotated,
            author: fields[index + 4],
            date: Date(
              timeIntervalSince1970: TimeInterval(fields[index + (annotated ? 5 : 6)]) ?? 0),
            summary: fields[index + 7], message: annotated ? fields[index + 8] : ""
          ))
      }
      index += 10
    }
    return tags
  }

  static func validate(_ name: String, repository: URL) async -> BranchNameCheck {
    guard !name.isEmpty else { return .empty }
    guard !name.hasPrefix("-") else { return .invalid }
    let valid = await GitClient.run(
      args: ["check-ref-format", "refs/tags/" + name], cwd: repository)
    guard valid.exitCode == 0 else { return .invalid }
    let existing = await GitClient.run(
      args: ["show-ref", "--verify", "--quiet", "refs/tags/" + name], cwd: repository)
    return existing.exitCode == 1 ? .ok : (existing.exitCode == 0 ? .duplicate : .invalid)
  }

  static func create(
    name: String, target: TagTarget, annotated: Bool, message: String, repository: URL
  ) async throws {
    guard await validate(name, repository: repository) == .ok,
      !annotated || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ValidationFailure(
        message: L10n.text(
          "Tag 名称无效、已存在，或缺少附注说明。",
          "The tag name is invalid, already exists, or the annotation message is missing."))
    }
    let options = annotated ? ["-a", "--cleanup=verbatim", "-m", message] : ["--no-sign"]
    _ = try await checked(
      ["-c", "tag.gpgSign=false", "tag"] + options + ["--", name, target.commit.hash],
      repository: repository)
  }

  static func remotes(repository: URL) async throws -> [String] {
    let output = try await checked(["remote"], repository: repository)
    return output.stdoutText.split(separator: "\n").map(String.init)
  }

  static func push(_ tag: TagRecord, remote: String, repository: URL) async throws {
    let names = try await remotes(repository: repository)
    guard names.contains(remote) else {
      throw ValidationFailure(
        message: L10n.text("所选远程已不存在。", "The selected remote no longer exists."))
    }
    _ = try await checked(
      [
        "-c", "push.followTags=false", "push", "--no-follow-tags", "--", remote,
        tag.objectHash + ":refs/tags/" + tag.name,
      ], repository: repository, timeout: 120)
  }

  static func delete(_ tag: TagRecord, repository: URL) async throws {
    _ = try await checked(
      ["update-ref", "-d", "refs/tags/" + tag.name, tag.objectHash], repository: repository)
  }
}
