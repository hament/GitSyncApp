import Foundation

enum StatusParser {
    static func parse(_ data: Data) -> [FileChange] {
        let parts = data.split(separator: 0, omittingEmptySubsequences: true).map { Data($0) }
        var index = 0
        var files: [FileChange] = []
        while index < parts.count {
            let entry = String(decoding: parts[index], as: UTF8.self)
            index += 1
            guard entry.count >= 4 else { continue }
            let x = entry[entry.startIndex]
            let y = entry[entry.index(entry.startIndex, offsetBy: 1)]
            let pathStart = entry.index(entry.startIndex, offsetBy: 3)
            let path = String(entry[pathStart...])
            var oldPath: String?
            if x == "R" || x == "C" || y == "R" || y == "C", index < parts.count {
                // Porcelain v1 -z is `R  <new>\0<old>\0`.
                oldPath = String(decoding: parts[index], as: UTF8.self)
                index += 1
            }
            files.append(FileChange(path: path, oldPath: oldPath, kind: kind(x: x, y: y)))
        }
        return files
    }

    private static func kind(x: Character, y: Character) -> ChangeKind {
        let pair = "\(x)\(y)"
        let unmerged: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        if unmerged.contains(pair) { return .conflict }
        if x == "R" || y == "R" || x == "C" || y == "C" { return .renamed }
        if x == "?" || y == "?" { return .untracked }
        if x == "A" || y == "A" { return .added }
        if x == "D" || y == "D" { return .deleted }
        return .modified
    }
}
