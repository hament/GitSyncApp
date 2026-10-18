import Foundation

enum RecentsStore {
    private static let lastKey = "lastRepositoryPath"
    private static let branchesKey = "recentBranchesByRepo"
    private static let limit = 8

    static func lastRepository() -> String? {
        UserDefaults.standard.string(forKey: lastKey)
    }

    static func setLastRepository(_ path: String) {
        UserDefaults.standard.set(path, forKey: lastKey)
    }

    static func recentBranches(for path: String) -> [String] {
        let map = UserDefaults.standard.dictionary(forKey: branchesKey) as? [String: [String]] ?? [:]
        return map[path] ?? []
    }

    static func rememberBranch(_ name: String, repository path: String) {
        guard !name.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: branchesKey) as? [String: [String]] ?? [:]
        var list = map[path] ?? []
        list.removeAll { $0 == name }
        list.insert(name, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
        map[path] = list
        UserDefaults.standard.set(map, forKey: branchesKey)
    }
}
