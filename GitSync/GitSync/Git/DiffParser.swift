import Foundation

enum DiffParser {
    static let lineLimit = 20_000

    static func parse(_ text: String) -> DiffDocument {
        if text.contains("Binary files") || text.contains("GIT binary patch") {
            return DiffDocument(lines: [], isBinary: true, truncated: false)
        }
        var lines: [DiffLine] = []
        var truncated = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { continue }
            guard let kind = classify(line) else { continue }
            if lines.count >= lineLimit {
                truncated = true
                break
            }
            lines.append(DiffLine(kind: kind, text: line))
        }
        return DiffDocument(lines: lines, isBinary: false, truncated: truncated)
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
