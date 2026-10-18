import Foundation

nonisolated enum ChangeKind: String, Hashable, Sendable {
    case modified
    case added
    case deleted
    case untracked
    case renamed
    case conflict

    var title: String {
        switch self {
        case .modified: "修改"
        case .added: "新增"
        case .deleted: "删除"
        case .untracked: "未跟踪"
        case .renamed: "重命名"
        case .conflict: "冲突"
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

nonisolated struct CommitRecord: Identifiable, Hashable, Sendable {
    var hash: String
    var authorName: String
    var authorEmail: String
    var date: Date
    var subject: String
    var id: String { hash }

    var shortHash: String { String(hash.prefix(7)) }
}

nonisolated struct CommitFile: Identifiable, Hashable, Sendable {
    var label: String
    var path: String
    var oldPath: String?
    var id: String { (oldPath ?? "") + "→" + path }
}

nonisolated enum DiffLineKind: Hashable, Sendable {
    case add
    case delete
    case hunk
    case context
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
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

nonisolated struct FailureReport: Identifiable, Hashable, Sendable {
    var title: String
    var reason: String
    var log: String
    var id: String { title + "\n" + reason + "\n" + log }
}

nonisolated enum AppDialog: Identifiable, Hashable, Sendable {
    case discard(FileChange)
    case removeFromIndex(FileChange)
    case merge(String)
    case abortMerge
    case notRepository
    case vscodeMissing
    case plain(title: String, message: String)

    var id: String {
        switch self {
        case .discard(let file): "discard:\(file.path)"
        case .removeFromIndex(let file): "untrack:\(file.path)"
        case .merge(let source): "merge:\(source)"
        case .abortMerge: "abort"
        case .notRepository: "not-repo"
        case .vscodeMissing: "vscode"
        case .plain(let title, let message): "plain:\(title)\n\(message)"
        }
    }
}

nonisolated enum SidebarMode: String, Hashable, Sendable {
    case changes
    case history
}

nonisolated enum BranchNameCheck: Equatable, Sendable {
    case empty
    case checking
    case ok
    case duplicate
    case invalid
}
