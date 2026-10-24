import Foundation

nonisolated struct BranchListSnapshot: Equatable, Sendable {
  let repositoryPath: String?
  let currentBranchName: String?
  let recentBranchNames: [String]
  let localBranchNames: [String]
  let remoteBranchNames: [String]
  let query: String

  func filtered() -> BranchListSections {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    func matches(_ name: String) -> Bool {
      query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    let current = currentBranchName.flatMap { matches($0) ? [$0] : nil } ?? []
    let recent = recentBranchNames.filter { $0 != currentBranchName && matches($0) }
    let recentSet = Set(recent)
    let local = localBranchNames.filter {
      $0 != currentBranchName && !recentSet.contains($0) && matches($0)
    }
    let remote = remoteBranchNames.filter(matches)
    return BranchListSections(current: current, recent: recent, local: local, remote: remote)
  }
}

nonisolated struct BranchListSections: Equatable, Sendable {
  let current: [String]
  let recent: [String]
  let local: [String]
  let remote: [String]

  var isEmpty: Bool {
    current.isEmpty && recent.isEmpty && local.isEmpty && remote.isEmpty
  }
}
