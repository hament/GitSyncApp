import Foundation

enum DiffParser {
    static let lineLimit = 20_000

    static func parse(_ text: String) -> DiffDocument {
        if text.contains("Binary files") || text.contains("GIT binary patch") {
            return DiffDocument(lines: [], isBinary: true, truncated: false)
        }
        var lines: [DiffLine] = []
        var truncated = false
        var oldLineNumber = 0
        var newLineNumber = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { continue }
            guard let kind = classify(line) else { continue }
            if lines.count >= lineLimit {
                truncated = true
                break
            }
            switch kind {
            case .hunk:
                if let starts = hunkStarts(line) {
                    oldLineNumber = starts.old
                    newLineNumber = starts.new
                }
                lines.append(DiffLine(kind: .hunk, text: line))
            case .add:
                lines.append(
                    DiffLine(
                        kind: .add,
                        text: line,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber
                    )
                )
                newLineNumber += 1
            case .delete:
                lines.append(
                    DiffLine(
                        kind: .delete,
                        text: line,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil
                    )
                )
                oldLineNumber += 1
            case .context:
                if line.hasPrefix("\\") {
                    lines.append(DiffLine(kind: .context, text: line))
                } else {
                    lines.append(
                        DiffLine(
                            kind: .context,
                            text: line,
                            oldLineNumber: oldLineNumber,
                            newLineNumber: newLineNumber
                        )
                    )
                    oldLineNumber += 1
                    newLineNumber += 1
                }
            }
        }
        return DiffDocument(lines: lines, isBinary: false, truncated: truncated)
    }

    private static func hunkStarts(_ line: String) -> (old: Int, new: Int)? {
        let fields = line.split(separator: " ")
        guard fields.count >= 3,
              let old = lineStart(String(fields[1]), prefix: "-"),
              let new = lineStart(String(fields[2]), prefix: "+") else {
            return nil
        }
        return (old, new)
    }

    private static func lineStart(_ field: String, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        let value = field.dropFirst().split(separator: ",", maxSplits: 1).first
        return value.flatMap { Int($0) }
    }

    private static func classify(_ line: String) -> DiffLineKind? {
        if line.hasPrefix("diff --git")
            || line.hasPrefix("index ")
            || line.hasPrefix("---")
            || line.hasPrefix("+++")
            || line.hasPrefix("new file")
            || line.hasPrefix("deleted file")
            || line.hasPrefix("old mode")
            || line.hasPrefix("new mode")
            || line.hasPrefix("similarity index")
            || line.hasPrefix("rename from")
            || line.hasPrefix("rename to")
            || line.hasPrefix("copy from")
            || line.hasPrefix("copy to")
            || line.hasPrefix("Binary files") {
            return nil
        }
        if line.hasPrefix("@@") { return .hunk }
        if line.hasPrefix("+") { return .add }
        if line.hasPrefix("-") { return .delete }
        if line.hasPrefix("\\") { return .context }
        return .context
    }
}
