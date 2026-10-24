import Foundation

enum RecentsStore {
  private static let lastKey = "lastRepositoryPath"
  private static let repositoriesKey = "recentRepositoryPaths"
  private static let branchesKey = "recentBranchesByRepo"
  private static let branchLimit = 8
  private static let repositoryLimit = 20

  static func lastRepository() -> String? {
    recentRepositories().first ?? UserDefaults.standard.string(forKey: lastKey)
  }

  static func setLastRepository(_ path: String) {
    rememberRepository(path)
  }

  static func recentRepositories() -> [String] {
    UserDefaults.standard.stringArray(forKey: repositoriesKey) ?? []
  }

  static func removeRepository(_ path: String) {
    let repositories = recentRepositories().filter { $0 != path }
    UserDefaults.standard.set(repositories, forKey: repositoriesKey)
    if UserDefaults.standard.string(forKey: lastKey) == path {
      if let first = repositories.first {
        UserDefaults.standard.set(first, forKey: lastKey)
      } else {
        UserDefaults.standard.removeObject(forKey: lastKey)
      }
    }
  }

  static func rememberRepository(_ path: String) {
    guard !path.isEmpty else { return }
    var repositories = recentRepositories()
    repositories.removeAll { $0 == path }
    repositories.insert(path, at: 0)
    if repositories.count > repositoryLimit {
      repositories = Array(repositories.prefix(repositoryLimit))
    }
    UserDefaults.standard.set(repositories, forKey: repositoriesKey)
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
    if list.count > branchLimit {
      list = Array(list.prefix(branchLimit))
    }
    map[path] = list
    UserDefaults.standard.set(map, forKey: branchesKey)
  }
}
