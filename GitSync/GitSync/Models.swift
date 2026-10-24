import Foundation

nonisolated enum ChangeKind: String, Hashable, Sendable {
  case modified
  case added
  case deleted
  case untracked
  case renamed
  case conflict

  @MainActor var title: String { titleText.localized }

  var titleText: LocalizedText {
    switch self {
    case .modified: L10n.message("修改", "Modified")
    case .added: L10n.message("新增", "Added")
    case .deleted: L10n.message("删除", "Deleted")
    case .untracked: L10n.message("未跟踪", "Untracked")
    case .renamed: L10n.message("重命名", "Renamed")
    case .conflict: L10n.message("冲突", "Conflict")
    }
  }

  var isTracked: Bool { self != .untracked }
}

nonisolated struct FileChange: Identifiable, Hashable, Sendable {
  var path: String
  var oldPath: String?
  var kind: ChangeKind
  var id: String { path }
}

nonisolated struct BranchItem: Identifiable, Hashable, Sendable {
  var name: String
  var isRemote: Bool
  var id: String { (isRemote ? "r:" : "l:") + name }

  /// `origin/feature/foo` → `feature/foo`
  var localCandidate: String {
    guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
    return String(name[name.index(after: slash)...])
  }
}

nonisolated struct ComparisonRequest: Codable, Hashable, Identifiable, Sendable {
  var id = UUID()
  let repositoryPath: String
  let baseHash: String
  let headHash: String
  let baseLabel: String
  let headLabel: String
}

nonisolated struct TagRecord: Identifiable, Hashable, Sendable {
  let name: String
  let objectHash: String
  let commitHash: String
  let isAnnotated: Bool
  let author: String
  let date: Date
  let summary: String
  let message: String
  var id: String { name }
}

nonisolated struct TagTarget: Identifiable, Sendable {
  let commit: CommitRecord
  let label: String
  var id: String { commit.hash }
}

nonisolated struct CommitRecord: Identifiable, Hashable, Sendable {
  var hash: String
  var parentHashes: [String] = []
  var references: [String] = []
  var authorName: String
  var authorEmail: String
  var date: Date
  var subject: String
  var id: String { hash }

  var shortHash: String { String(hash.prefix(7)) }
  var isMerge: Bool { parentHashes.count > 1 }
}

nonisolated enum HistoryScope: String, CaseIterable, Hashable, Sendable {
  case current
  case mainline
  case all

  @MainActor var title: String { titleText.localized }

  var titleText: LocalizedText {
    switch self {
    case .current: L10n.message("当前分支", "Current Branch")
    case .mainline: L10n.message("主线", "Mainline")
    case .all: L10n.message("所有分支", "All Branches")
    }
  }
}

nonisolated struct CommitGraphEdge: Hashable, Sendable {
  var fromLane: Int
  var toLane: Int
}

nonisolated struct CommitGraphRow: Hashable, Sendable {
  var nodeLane: Int
  var laneCount: Int
  var throughEdges: [CommitGraphEdge]
  var parentLanes: [Int]
}

nonisolated enum CommitGraphLayout {
  static func build(_ commits: [CommitRecord]) -> [String: CommitGraphRow] {
    var lanes: [String] = []
    var rows: [String: CommitGraphRow] = [:]

    for commit in commits {
      let nodeLane: Int
      if let existing = lanes.firstIndex(of: commit.hash) {
        nodeLane = existing
      } else {
        lanes.append(commit.hash)
        nodeLane = lanes.count - 1
      }

      let topLanes = lanes
      var bottomLanes = lanes
      bottomLanes.remove(at: nodeLane)

      var insertionIndex = nodeLane
      for parent in commit.parentHashes {
        if !bottomLanes.contains(parent) {
          let index = min(insertionIndex, bottomLanes.count)
          bottomLanes.insert(parent, at: index)
          insertionIndex = index + 1
        }
      }

      let throughEdges = topLanes.enumerated().compactMap { topIndex, hash -> CommitGraphEdge? in
        guard hash != commit.hash,
          let bottomIndex = bottomLanes.firstIndex(of: hash)
        else {
          return nil
        }
        return CommitGraphEdge(fromLane: topIndex, toLane: bottomIndex)
      }
      let parentLanes = commit.parentHashes.compactMap { bottomLanes.firstIndex(of: $0) }
      rows[commit.hash] = CommitGraphRow(
        nodeLane: nodeLane,
        laneCount: max(topLanes.count, bottomLanes.count, 1),
        throughEdges: throughEdges,
        parentLanes: parentLanes
      )
      lanes = bottomLanes
    }
    return rows
  }
}

nonisolated struct CommitFile: Identifiable, Hashable, Sendable {
  var labelText: LocalizedText
  @MainActor var label: String { labelText.localized }
  var path: String
  var oldPath: String?
  var id: String { (oldPath ?? "") + "→" + path }

  init(label: LocalizedText, path: String, oldPath: String?) {
    labelText = label
    self.path = path
    self.oldPath = oldPath
  }
}

nonisolated enum DiffLineKind: Hashable, Sendable {
  case add
  case delete
  case hunk
  case context
}

nonisolated enum DiffLayoutMode: String, CaseIterable, Hashable, Sendable {
  case unified
  case split
}

nonisolated struct DiffLine: Hashable, Sendable {
  var kind: DiffLineKind
  var text: String
  var oldLineNumber: Int? = nil
  var newLineNumber: Int? = nil
}

nonisolated struct DiffDocument: Hashable, Sendable {
  var lines: [DiffLine]
  var isBinary: Bool
  var truncated: Bool

  static let empty = DiffDocument(lines: [], isBinary: false, truncated: false)

  var additionCount: Int {
    lines.reduce(0) { $0 + ($1.kind == .add ? 1 : 0) }
  }

  var deletionCount: Int {
    lines.reduce(0) { $0 + ($1.kind == .delete ? 1 : 0) }
  }

  var splitRows: [SplitDiffRow] {
    var rows: [SplitDiffRow] = []
    var index = 0

    while index < lines.count {
      let line = lines[index]
      switch line.kind {
      case .hunk:
        rows.append(.hunk(line.text))
        index += 1
      case .context:
        rows.append(.lines(old: line, new: line))
        index += 1
      case .add, .delete:
        var deletions: [DiffLine] = []
        var additions: [DiffLine] = []
        while index < lines.count {
          let changed = lines[index]
          guard changed.kind == .add || changed.kind == .delete else { break }
          if changed.kind == .delete {
            deletions.append(changed)
          } else {
            additions.append(changed)
          }
          index += 1
        }
        let count = max(deletions.count, additions.count)
        for pairIndex in 0..<count {
          rows.append(
            .lines(
              old: pairIndex < deletions.count ? deletions[pairIndex] : nil,
              new: pairIndex < additions.count ? additions[pairIndex] : nil
            )
          )
        }
      }
    }
    return rows
  }
}

nonisolated enum SplitDiffRow: Hashable, Sendable {
  case hunk(String)
  case lines(old: DiffLine?, new: DiffLine?)
}

nonisolated struct GitOutput: Sendable {
  var args: [String]
  var stdout: Data
  var stderr: Data
  var exitCode: Int32

  var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
  var stderrText: String { String(decoding: stderr, as: UTF8.self) }

  var commandLine: String {
    (["git"] + args).map(Self.quote).joined(separator: " ")
  }

  var succeeded: Bool { exitCode == 0 }

  private static func quote(_ value: String) -> String {
    let needsQuote = value.isEmpty || value.contains { $0.isWhitespace || "\"'\\".contains($0) }
    guard needsQuote else { return value }
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}

nonisolated struct FailureReport: Identifiable, Hashable, Sendable {
  var title: LocalizedText
  var reason: LocalizedText
  var log: LocalizedText
  var id: String {
    "\(title.chinese)\n\(title.english)\n\(reason.chinese)\n\(reason.english)\n\(log.chinese)\n\(log.english)"
  }
}

nonisolated enum AppDialog: Identifiable, Hashable, Sendable {
  case discard(FileChange)
  case discardFiles([FileChange])
  case removePathsFromIndex([String], folders: Bool)
  case removeFromIndex(FileChange)
  case removeFolderFromIndex(String)
  case merge(String)
  case deleteBranch(String)
  case deleteTag(TagRecord)
  case abortMerge
  case notRepository
  case vscodeMissing
  case plain(title: LocalizedText, message: LocalizedText)

  var id: String {
    switch self {
    case .discard(let file): "discard:\(file.path)"
    case .removeFromIndex(let file): "untrack:\(file.path)"
    case .removeFolderFromIndex(let path): "untrack-folder:\(path)"
    case .discardFiles(let files): "discard-files:\(files.map(\.path))"
    case .removePathsFromIndex(let paths, let folders): "untrack-paths:\(folders):\(paths)"
    case .merge(let source): "merge:\(source)"
    case .deleteBranch(let name): "delete-branch:\(name)"
    case .deleteTag(let tag): "delete-tag:\(tag.name):\(tag.objectHash)"
    case .abortMerge: "abort"
    case .notRepository: "not-repo"
    case .vscodeMissing: "vscode"
    case .plain(let title, let message):
      "plain:\(title.chinese)\n\(title.english)\n\(message.chinese)\n\(message.english)"
    }
  }
}

nonisolated enum SidebarMode: String, Hashable, Sendable {
  case changes
  case history
  case tags
}

nonisolated enum BranchNameCheck: Equatable, Sendable {
  case empty
  case checking
  case ok
  case duplicate
  case invalid
}
