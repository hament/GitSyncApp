import Foundation

@main
struct RecentRepositoryTests {
  @MainActor
  static func main() throws {
    let defaults = UserDefaults.standard
    let keys = ["recentRepositoryPaths", "lastRepositoryPath"]
    let originalValues = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, originalValues) {
        if let value {
          defaults.set(value, forKey: key)
        } else {
          defaults.removeObject(forKey: key)
        }
      }
    }
    keys.forEach { defaults.removeObject(forKey: $0) }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first").path
    let second = directory.appendingPathComponent("second").path
    try FileManager.default.createDirectory(atPath: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: second, withIntermediateDirectories: true)
    let file = URL(fileURLWithPath: first).appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: file)
    RecentsStore.rememberRepository(second)
    RecentsStore.rememberRepository(first)

    let model = AppModel()
    model.repositoryPath = first
    model.commitMessage = "Keep this draft"
    precondition(model.recentRepositoryPaths == [first, second])
    model.removeRecentRepository(first)
    precondition(model.recentRepositoryPaths == [second])
    precondition(RecentsStore.recentRepositories() == [second])
    precondition(RecentsStore.lastRepository() == second)
    precondition(model.repositoryPath == first && model.commitMessage == "Keep this draft")
    let contents = try String(contentsOf: file, encoding: .utf8)
    precondition(contents == "keep")

    model.isBusy = true
    model.removeRecentRepository(second)
    precondition(model.recentRepositoryPaths == [second])
    model.isBusy = false
    model.removeRecentRepository(second)
    precondition(model.recentRepositoryPaths.isEmpty)
    precondition(RecentsStore.recentRepositories().isEmpty && RecentsStore.lastRepository() == nil)
    precondition(FileManager.default.fileExists(atPath: second))
    model.removeRecentRepository(first)
    precondition(model.recentRepositoryPaths.isEmpty)
    model.closeWindow()
    print(
      "PASS: recent removal, persistence, last-project fallback, empty list, busy guard, local files and current draft preserved"
    )
  }
}
