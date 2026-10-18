import Foundation

enum LogParser {
    static func parseCommits(_ text: String) -> [CommitRecord] {
        text.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let usesGraphFields = fields.count >= 7
            let authorIndex = usesGraphFields ? 3 : 1
            let emailIndex = usesGraphFields ? 4 : 2
            let dateIndex = usesGraphFields ? 5 : 3
            let subjectIndex = usesGraphFields ? 6 : 4
            guard !hash.isEmpty, let seconds = TimeInterval(fields[dateIndex]) else { return nil }
            return CommitRecord(
                hash: hash,
                parentHashes: usesGraphFields
                    ? fields[1].split(separator: " ").map(String.init)
                    : [],
                references: usesGraphFields ? parseReferences(fields[2]) : [],
                authorName: fields[authorIndex],
                authorEmail: fields[emailIndex],
                date: Date(timeIntervalSince1970: seconds),
                subject: fields[subjectIndex].trimmingCharacters(in: .newlines)
            )
        }
    }

    private static func parseReferences(_ decorations: String) -> [String] {
        var references: [String] = []
        for raw in decorations.split(separator: ",") {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("HEAD -> ") {
                references.append("HEAD")
                references.append(String(value.dropFirst("HEAD -> ".count)))
            } else if value.hasSuffix("/HEAD") || value.contains("/HEAD -> ") {
                continue
            } else if value.hasPrefix("tag: ") {
                references.append(String(value.dropFirst("tag: ".count)))
            } else if !value.isEmpty {
                references.append(value)
            }
        }
        var seen = Set<String>()
        return references.filter { seen.insert($0).inserted }
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
            .compactMap { line -> String? in
                let fields = line.split(
                    separator: "\t",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard let first = fields.first,
                      fields.count == 1 || fields[1].isEmpty else {
                    return nil
                }
                let name = String(first)
                return name.isEmpty || name.hasSuffix("/HEAD") ? nil : name
            }
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
