import Foundation

@main
struct BranchListTests {
  static func main() throws {
    let snapshot = BranchListSnapshot(
      repositoryPath: "/test/repository",
      currentBranchName: "main",
      recentBranchNames: ["main", "feature/recent"],
      localBranchNames: ["main", "feature/recent", "feature/local"],
      remoteBranchNames: ["origin/main", "origin/feature/recent", "origin/feature/LOCAL"],
      query: ""
    )
    let sections = snapshot.filtered()
    precondition(sections.current == ["main"])
    precondition(sections.recent == ["feature/recent"])
    precondition(sections.local == ["feature/local"])
    precondition(sections.remote == snapshot.remoteBranchNames)
    precondition(!sections.isEmpty)

    let searched = withQuery("  LOCAL\n", in: snapshot).filtered()
    precondition(searched.current.isEmpty && searched.recent.isEmpty)
    precondition(searched.local == ["feature/local"])
    precondition(searched.remote == ["origin/feature/LOCAL"])
    precondition(withQuery("no-such-branch", in: snapshot).filtered().isEmpty)
    let recentSearch = withQuery("recent", in: snapshot).filtered()
    precondition(recentSearch.recent == ["feature/recent"] && recentSearch.local.isEmpty)

    let detached = BranchListSnapshot(
      repositoryPath: "/test/repository",
      currentBranchName: nil,
      recentBranchNames: [],
      localBranchNames: ["main"],
      remoteBranchNames: [],
      query: ""
    ).filtered()
    precondition(detached.current.isEmpty && detached.local == ["main"])

    let empty = BranchListSnapshot(
      repositoryPath: nil, currentBranchName: nil, recentBranchNames: [],
      localBranchNames: [], remoteBranchNames: [], query: ""
    ).filtered()
    precondition(empty.isEmpty)

    let large = BranchListSnapshot(
      repositoryPath: "/test/large",
      currentBranchName: "main",
      recentBranchNames: [],
      localBranchNames: ["main"],
      remoteBranchNames: (0..<10_000).map { "origin/feature/branch-\($0)" },
      query: "branch-9999"
    )
    precondition(large.filtered().remote == ["origin/feature/branch-9999"])
    precondition(withQuery("", in: large).filtered().remote.count == 10_000)
    print("PASS: grouping, deduplication, search, detached HEAD, empty list, 10,000 branches")

    if let path = CommandLine.arguments.dropFirst().first {
      try checkRepository(path)
    }
  }

  private static func withQuery(_ query: String, in snapshot: BranchListSnapshot)
    -> BranchListSnapshot
  {
    BranchListSnapshot(
      repositoryPath: snapshot.repositoryPath,
      currentBranchName: snapshot.currentBranchName,
      recentBranchNames: snapshot.recentBranchNames,
      localBranchNames: snapshot.localBranchNames,
      remoteBranchNames: snapshot.remoteBranchNames,
      query: query
    )
  }

  private static func checkRepository(_ path: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = [
      "-C", path, "for-each-ref", "--format=%(refname)%09%(symref)", "refs/heads", "refs/remotes",
    ]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0)

    var local: [String] = []
    var remote: [String] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 2, fields[1].isEmpty else { continue }
      let ref = fields[0]
      if ref.hasPrefix("refs/heads/") { local.append(String(ref.dropFirst("refs/heads/".count))) }
      if ref.hasPrefix("refs/remotes/") {
        remote.append(String(ref.dropFirst("refs/remotes/".count)))
      }
    }
    let snapshot = BranchListSnapshot(
      repositoryPath: path,
      currentBranchName: local.first,
      recentBranchNames: [],
      localBranchNames: local,
      remoteBranchNames: remote,
      query: ""
    )
    let clock = ContinuousClock()
    let groupingTime = clock.measure {
      let sections = snapshot.filtered()
      precondition(sections.current.count + sections.local.count == local.count)
      precondition(sections.remote == remote)
    }
    let searchTime = clock.measure {
      let searched = withQuery("feature", in: snapshot).filtered()
      precondition(
        searched.remote == remote.filter { $0.localizedCaseInsensitiveContains("feature") })
    }
    print("PASS: actual repository, \(local.count) local + \(remote.count) remote branches")
    print("Grouping: \(groupingTime); search and verification: \(searchTime)")
  }
}
