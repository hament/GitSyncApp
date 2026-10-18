import Foundation

enum LogParser {
    static func parseCommits(_ text: String) -> [CommitRecord] {
        text.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty, let seconds = TimeInterval(fields[3]) else { return nil }
            return CommitRecord(
                hash: hash,
                authorName: fields[1],
                authorEmail: fields[2],
                date: Date(timeIntervalSince1970: seconds),
                subject: fields[4].trimmingCharacters(in: .newlines)
            )
        }
    }

    static func parseNameStatus(_ data: Data) -> [CommitFile] {
        let parts = data.split(separator: 0, omittingEmptySubsequences: true).map {
            String(decoding: $0, as: UTF8.self)
        }
        var index = 0
        var files: [CommitFile] = []
        while index < parts.count {
            let status = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            guard !status.isEmpty else { continue }
            if status.hasPrefix("R") || status.hasPrefix("C") {
                guard index + 1 < parts.count else { break }
                let oldPath = parts[index]
                let newPath = parts[index + 1]
                index += 2
                files.append(CommitFile(label: label(for: status), path: newPath, oldPath: oldPath))
            } else {
                guard index < parts.count else { break }
                let path = parts[index]
                index += 1
                files.append(CommitFile(label: label(for: status), path: path, oldPath: nil))
            }
        }
        return files
    }

    static func parseLocalBranches(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let pieces = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { return nil }
            let name = String(pieces[1])
            return name.isEmpty ? nil : name
        }
    }

    static func parseRemoteBranches(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func label(for status: String) -> String {
        switch status.first {
        case "A": "新增"
        case "D": "删除"
        case "R": "重命名"
        case "C": "复制"
        case "U": "冲突"
        default: "修改"
        }
    }
}
