import AppKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
  let windowID: UUID

  init(windowID: UUID = UUID()) {
    self.windowID = windowID
  }
  private let git = WindowGitClient()
  private var operationRepository: String?
  private var isWindowClosed = false
  private var emptyWindowTheme: ProjectTheme = .blue

  var projectTheme: ProjectTheme {
    get { ProjectAppearance.shared.theme(for: repositoryPath, fallback: emptyWindowTheme) }
    set {
      if let repositoryPath {
        ProjectAppearance.shared.setTheme(newValue, for: repositoryPath)
      } else {
        emptyWindowTheme = newValue
      }
    }
  }
  var repositoryPath: String?
  var repositoryDisplayName = ""
  var branchDisplayName = ""
  var detachedBranchName: String?
  var unpushedCount: Int?
  var remoteAheadCount: Int?
  var currentBranchName: String?
  var isDetached = false
  var localBranchNames: [String] = []
  var remoteBranchNames: [String] = []
  var recentBranchNames: [String] = []
  var recentRepositoryPaths = RecentsStore.recentRepositories()

  var files: [FileChange] = []
  var checkedPaths: Set<String> = []
  var selectedPath: String?
  var selectedChangePaths: Set<String> = []

  var mode: SidebarMode = .changes
  var historyScope: HistoryScope = .current
  var commits: [CommitRecord] = []
  var canLoadMoreHistory = false
  var selectedCommitHash: String?
  var loadingCommitHash: String?
  var commitFiles: [String: [CommitFile]] = [:]
  var commitBranches: [String: [String]] = [:]
  var tags: [TagRecord] = []
  var selectedTagName: String?
  var selectedTagCommit: CommitRecord?
  var tagTarget: TagTarget?
  var tagToPush: TagRecord?
  var tagListError: String?
  var selectedHistoryHash: String?
  var selectedHistoryPath: String?

  var diff = DiffDocument.empty
  var diffTitle = ""
  var diffLayoutMode: DiffLayoutMode = {
    guard let rawValue = UserDefaults.standard.string(forKey: "diffLayoutMode") else {
      return .unified
    }
    return DiffLayoutMode(rawValue: rawValue) ?? .unified
  }()
  {
    didSet {
      UserDefaults.standard.set(diffLayoutMode.rawValue, forKey: "diffLayoutMode")
    }
  }

  var commitMessage = ""
  var isBusy = false
  var busyLabel: LocalizedText = L10n.message("", "")
  var isRefreshing = false
  var refreshLabel: LocalizedText = L10n.message("", "")
  var banner: LocalizedText?
  var mergeInProgress = false
  var mergeSource = ""

  var failure: FailureReport?
  var dialog: AppDialog?
  var showProjectInfo = false
  var showNewBranch = false
  var newBranchStartCommit: String?
  var showBranchComparison = false
  var showMerge = false
  var showClone = false
  var cloneError: String?
  var cloneAuthenticationGuide: CloneAuthenticationGuide?

  private var seenPaths: Set<String> = []
  private var generation = 0
  private var didRestore = false
  private var userChoseRepository = false
  private var bannerToken = 0
  private var diffToken = 0
  private var tagLoadToken = 0
  private var savedHistoryHash: String?
  private var savedHistoryPath: String?
  private var tagSelectedPaths: [String: String] = [:]
  private var cancelRequested = false

  var repositoryURL: URL? {
    repositoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  var windowTitle: String {
    let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Git Sync"
  }

  var localizedBranchDisplayName: String {
    if let currentBranchName { return currentBranchName }
    if isDetached {
      if let detachedBranchName {
        return L10n.text("\(detachedBranchName)（分离）", "\(detachedBranchName) (detached)")
      }
      return branchDisplayName.isEmpty || branchDisplayName == "分离头指针"
        ? L10n.text("分离头指针", "Detached HEAD")
        : L10n.text("\(branchDisplayName)（分离）", "\(branchDisplayName) (detached)")
    }
    return repositoryPath == nil ? L10n.text("分支", "Branch") : L10n.text("尚无提交", "No commits yet")
  }

  var checkedCount: Int {
    files.reduce(0) { $0 + (checkedPaths.contains($1.path) ? 1 : 0) }
  }

  var allChecked: Bool {
    !files.isEmpty && checkedCount == files.count
  }

  var canCommit: Bool {
    !isWorking
      && repositoryPath != nil
      && checkedCount > 0
      && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isWorking: Bool {
    isBusy || isRefreshing
  }

  var selectedCommit: CommitRecord? {
    if mode == .tags { return selectedTagCommit }
    guard let selectedCommitHash else { return nil }
    return commits.first { $0.hash == selectedCommitHash }
  }

  var selectedCommitFiles: [CommitFile] {
    guard let selectedCommitHash else { return [] }
    return commitFiles[selectedCommitHash] ?? []
  }

  var selectedCommitBranches: [String] {
    guard let selectedCommitHash else { return [] }
    return commitBranches[selectedCommitHash] ?? []
  }

  var commitGraphRows: [String: CommitGraphRow] {
    CommitGraphLayout.build(commits)
  }

  func presentClone() {
    guard !isWorking, !isWindowClosed else { return }
    userChoseRepository = true
    cloneError = nil
    cloneAuthenticationGuide = nil
    showClone = true
  }

  func cloneRepository(address: String, destinationPath: String) async {
    guard beginRepositoryLoad() else { return }
    defer { endRepositoryLoad() }
    cloneError = nil
    cloneAuthenticationGuide = nil
    userChoseRepository = true
    refreshLabel = L10n.message("正在克隆仓库（git clone）…", "Cloning repository (git clone)…")
    do {
      let result = try await git.perform {
        try await GitClone.clone(address: address, destinationPath: destinationPath)
      }
      guard !isWindowClosed else { return }
      if cancelRequested {
        cloneError = L10n.text(
          "克隆已取消。如果保存目录仍存在，请选择新目录或检查保留的文件后重试。",
          "Clone canceled. If the destination still exists, choose a new folder or inspect the retained files before retrying."
        )
        return
      }
      guard result.output.exitCode == 0 else {
        cloneError =
          L10n.text(
            "克隆失败。如果保存目录仍存在，请检查保留的文件后重试。\n\n",
            "Clone failed. If the destination still exists, inspect the retained files before retrying.\n\n"
          )
          + String(result.output.stderrText.suffix(8_000))
        if let gitPath = GitClient.resolveBinary() {
          cloneAuthenticationGuide = CloneAuthenticationGuide(
            address: address, failure: result.output.stderrText, gitPath: gitPath
          )
        }
        return
      }
      showClone = false
      refreshLabel = L10n.message("正在打开克隆的项目…", "Opening cloned repository…")
      await open(folder: result.destination, silentIfInvalid: false)
    } catch {
      guard !isWindowClosed else { return }
      cloneError = error.localizedDescription
    }
  }

  func chooseRepository() {
    guard !isWorking else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.text("选择", "Choose")
    panel.message = L10n.text("选择一个本地 Git 仓库文件夹", "Choose a local Git repository folder")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    userChoseRepository = true
    startLoadingRepository(folder: url, silentIfInvalid: false)
  }

  func removeRecentRepository(_ path: String) {
    guard !isWorking else { return }
    RecentsStore.removeRepository(path)
    recentRepositoryPaths = RecentsStore.recentRepositories()
  }

  func openRecentRepository(_ path: String) {
    guard !isWorking else { return }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      RecentsStore.removeRepository(path)
      recentRepositoryPaths = RecentsStore.recentRepositories()
      dialog = .plain(
        title: L10n.message("无法打开项目", "Unable to Open Project"),
        message: L10n.message(
          "项目路径已不存在，已从最近项目移除：\n\(path)",
          "The project path no longer exists and was removed from recent projects:\n\(path)"))
      return
    }
    userChoseRepository = true
    startLoadingRepository(
      folder: URL(fileURLWithPath: path, isDirectory: true),
      silentIfInvalid: false
    )
  }

  func restoreLastIfNeeded() async {
    guard !didRestore else { return }
    didRestore = true
    guard !userChoseRepository, let last = RecentsStore.lastRepository() else { return }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: last, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return }
    await loadRepository(
      folder: URL(fileURLWithPath: last, isDirectory: true),
      silentIfInvalid: true
    )
  }

  func refreshNow() {
    guard !isWorking, repositoryPath != nil else { return }
    startRefresh(label: L10n.message("正在刷新（git status / log）…", "Refreshing (git status / log)…")) {
      await self.refresh(alertOnFailure: true, updateDivergence: true)
    }
  }

  func refreshIfIdle() {
    guard !isWorking, repositoryPath != nil else { return }
    startRefresh(label: L10n.message("正在刷新仓库状态…", "Refreshing repository status…")) {
      await self.refresh(alertOnFailure: false, updateDivergence: true)
    }
  }

  func cancelCurrentOperation() {
    guard isWorking else { return }
    cancelRequested = true
    if isBusy {
      busyLabel = L10n.message("正在取消 Git 操作…", "Canceling Git operation…")
    } else {
      refreshLabel = L10n.message("正在取消刷新…", "Canceling refresh…")
    }
    git.cancel()
  }

  func closeWindow() {
    isWindowClosed = true
    cancelRequested = true
    git.cancel()
    ProjectWindows.shared.release(windowID)
  }

  func setChecked(_ path: String, _ checked: Bool) {
    var next = checkedPaths
    if checked {
      next.insert(path)
    } else {
      next.remove(path)
    }
    checkedPaths = next
  }

  func toggleSelectAll() {
    if allChecked {
      checkedPaths = []
    } else {
      checkedPaths = Set(files.map(\.path))
    }
  }

  func selectChange(_ path: String) {
    selectedPath = path
    Task { await loadWorktreeDiff(path) }
  }

  func setMode(_ newMode: SidebarMode) {
    guard mode != newMode else { return }
    if mode == .history {
      savedHistoryHash = selectedHistoryHash
      savedHistoryPath = selectedHistoryPath
    }
    mode = newMode
    if newMode == .tags {
      if let tag = tags.first(where: { $0.name == selectedTagName }) ?? tags.first {
        Task { await selectTag(tag) }
      } else {
        clearTagSelection()
      }
      return
    }
    if newMode == .history {
      if let hash = savedHistoryHash, commits.contains(where: { $0.hash == hash }),
        let path = savedHistoryPath, commitFiles[hash]?.contains(where: { $0.path == path }) == true
      {
        selectHistoryFile(hash: hash, path: path)
      } else if let hash = savedHistoryHash, commits.contains(where: { $0.hash == hash }) {
        Task { await selectCommit(hash) }
      } else if let first = commits.first {
        Task { await selectCommit(first.hash) }
      } else {
        diff = .empty
        diffTitle = ""
      }
    } else if let path = selectedPath {
      Task { await loadWorktreeDiff(path) }
    } else {
      diff = .empty
      diffTitle = ""
    }
  }

  func setHistoryScope(_ scope: HistoryScope) {
    guard historyScope != scope, !isWorking else { return }
    historyScope = scope
    commits = []
    canLoadMoreHistory = false
    selectedCommitHash = nil
    selectedHistoryHash = nil
    selectedHistoryPath = nil
    diff = .empty
    diffTitle = ""
    startRefresh(
      label: L10n.message(
        "正在读取\(scope.titleText.chinese)历史（git log）…",
        "Reading history for \(scope.titleText.english) (git log)…")
    ) {
      await self.loadHistory(reset: true, alertOnFailure: true)
    }
  }

  func selectCommit(_ hash: String) async {
    guard !isWindowClosed else { return }
    selectedCommitHash = hash
    selectedHistoryHash = hash
    selectedHistoryPath = nil
    diff = .empty
    diffTitle = ""

    guard let cwd = repositoryURL else { return }
    let selectionMode = mode
    loadingCommitHash = hash
    defer {
      if loadingCommitHash == hash {
        loadingCommitHash = nil
      }
    }

    let fileTask: Task<GitOutput, Never>? =
      commitFiles[hash] == nil
      ? Task {
        await git.run(
          args: ["show", "--first-parent", "-z", "--name-status", "--pretty=format:", hash],
          cwd: cwd
        )
      }
      : nil
    let branchesTask: Task<GitOutput, Never>? =
      commitBranches[hash] == nil
      ? Task {
        await git.run(
          args: [
            "for-each-ref", "--format=%(refname)%09%(symref)",
            "--points-at", hash, "refs/heads", "refs/remotes",
          ],
          cwd: cwd
        )
      }
      : nil

    if let output = await fileTask?.value {
      guard repositoryURL == cwd, mode == selectionMode, selectedCommitHash == hash else { return }
      if output.exitCode == 0 {
        var loaded = commitFiles
        loaded[hash] = LogParser.parseNameStatus(output.stdout)
        commitFiles = loaded
      } else if selectedCommitHash == hash {
        present(action: L10n.message("刷新", "Refresh"), outputs: [output])
        return
      }
    }

    if let output = await branchesTask?.value, output.exitCode == 0 {
      guard repositoryURL == cwd, mode == selectionMode, selectedCommitHash == hash else { return }
      var loaded = commitBranches
      loaded[hash] = output.stdoutText
        .split(separator: "\n")
        .compactMap { line -> String? in
          let fields = line.split(
            separator: "\t",
            maxSplits: 1,
            omittingEmptySubsequences: false
          )
          guard let first = fields.first, fields.count == 1 || fields[1].isEmpty else {
            return nil
          }
          let raw = String(first)
          return LogParser.localBranchName(from: raw) ?? LogParser.remoteBranchName(from: raw)
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      commitBranches = loaded
    }

    guard repositoryURL == cwd, mode == selectionMode, selectedCommitHash == hash else { return }
    if mode == .tags, let name = selectedTagName, let path = tagSelectedPaths[name],
      commitFiles[hash]?.contains(where: { $0.path == path }) == true
    {
      selectHistoryFile(hash: hash, path: path)
    } else if let first = commitFiles[hash]?.first {
      selectHistoryFile(hash: hash, path: first.path)
    }
  }

  func selectHistoryFile(hash: String, path: String) {
    if mode == .tags, let name = selectedTagName {
      tagSelectedPaths[name] = path
    }
    selectedCommitHash = hash
    selectedHistoryHash = hash
    selectedHistoryPath = path
    Task { await loadHistoryDiff(hash: hash, path: path) }
  }

  func loadMoreHistory() async {
    guard !isWorking else { return }
    await loadHistory(reset: false, alertOnFailure: true)
  }

  func validateBranchName(_ raw: String) async -> BranchNameCheck {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return .empty }
    if localBranchNames.contains(name) { return .duplicate }
    guard let cwd = repositoryURL else { return .invalid }
    let output = await git.run(args: ["check-ref-format", "--branch", name], cwd: cwd)
    return output.exitCode == 0 ? .ok : .invalid
  }

  func switchBranch(_ item: BranchItem) async {
    if !item.isRemote, item.name == currentBranchName { return }
    guard let cwd = repositoryURL,
      begin(L10n.message("正在切换分支（git switch）…", "Switching branches (git switch)…"))
    else { return }
    defer { end() }
    let args: [String]
    let remembered: String
    if item.isRemote {
      if localBranchNames.contains(item.localCandidate) {
        args = ["switch", item.localCandidate]
        remembered = item.localCandidate
      } else {
        args = ["switch", "--track", item.name]
        remembered = item.localCandidate
      }
    } else {
      let name = await resolvedLocalBranchName(item.name, cwd: cwd) ?? item.name
      args = ["switch", name]
      remembered = name
    }
    let output = await git.run(args: args, cwd: cwd)
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("切换分支", "Switch Branch"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    if let repositoryPath {
      RecentsStore.rememberBranch(remembered, repository: repositoryPath)
    }
    showBanner(L10n.message("已切换到 \(remembered)", "Switched to \(remembered)"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func createBranch(named raw: String, startCommit: String? = nil) async {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let cwd = repositoryURL,
      begin(L10n.message("正在创建分支（git switch -c）…", "Creating branch (git switch -c)…"))
    else { return }
    defer { end() }
    let output = await git.run(
      args: ["switch", "-c", name] + (startCommit.map { [$0] } ?? []), cwd: cwd)
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      showNewBranch = false
      presentAfterDelay {
        self.present(action: L10n.message("新建分支", "Create Branch"), outputs: [output])
      }
      await refresh(alertOnFailure: false)
      return
    }
    if let repositoryPath {
      RecentsStore.rememberBranch(name, repository: repositoryPath)
    }
    showNewBranch = false
    showBanner(L10n.message("已创建并切换到 \(name)", "Created and switched to \(name)"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func presentNewBranch(startCommit: String? = nil) {
    guard !isWorking else { return }
    newBranchStartCommit = startCommit
    presentAfterDelay { self.showNewBranch = true }
  }

  func canDeleteBranch(_ item: BranchItem) -> Bool {
    guard !isWorking, !item.isRemote else { return false }
    let name =
      LogParser.matchingLocalBranch(
        item.name, existing: localBranchNames, current: currentBranchName)
      ?? item.name
    if name == currentBranchName { return false }
    return !remoteBranchNames.contains { $0.hasSuffix("/" + name) }
  }

  func askDeleteBranch(_ item: BranchItem) {
    guard canDeleteBranch(item) else { return }
    presentAfterDelay { self.dialog = .deleteBranch(item.name) }
  }

  func deleteBranch(_ name: String) async {
    guard canDeleteBranch(BranchItem(name: name, isRemote: false)), let cwd = repositoryURL,
      begin(L10n.message("正在删除本地分支…", "Deleting local branch…"))
    else { return }
    defer { end() }
    let current = await git.run(args: ["branch", "--show-current"], cwd: cwd)
    let remoteRefs = await git.run(
      args: ["for-each-ref", "--format=%(refname)", "refs/remotes"], cwd: cwd)
    guard !cancelRequested else { return }
    guard current.exitCode == 0, remoteRefs.exitCode == 0,
      let branchName = await resolvedLocalBranchName(name, cwd: cwd)
    else {
      dialog = .plain(
        title: L10n.message("无法删除分支", "Unable to Delete Branch"),
        message: L10n.message(
          "无法确认分支状态，未删除该分支。",
          "The branch state could not be verified, so it was not deleted."
        ))
      return
    }
    let remoteNames = remoteRefs.stdoutText.split(separator: "\n").compactMap {
      LogParser.remoteBranchName(from: String($0))
    }
    guard current.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) != branchName,
      !remoteNames.contains(where: { $0.hasSuffix("/" + branchName) })
    else {
      dialog = .plain(
        title: L10n.message("无法删除分支", "Unable to Delete Branch"),
        message: L10n.message(
          "不能删除当前分支或已有远程同名引用的分支。",
          "Cannot delete the current branch or a branch with a matching remote reference."))
      return
    }
    let output = await git.run(args: ["branch", "-D", "--", branchName], cwd: cwd)
    guard !cancelRequested else { return }
    if output.exitCode != 0 {
      present(action: L10n.message("删除分支", "Delete Branch"), outputs: [output])
    } else {
      showBanner(L10n.message("已删除本地分支 \(branchName)", "Deleted local branch \(branchName)"))
    }
    await refresh(alertOnFailure: false, updateDivergence: true)
  }

  private func resolvedLocalBranchName(_ name: String, cwd: URL) async -> String? {
    var candidates: [String] = []
    if let matched = LogParser.matchingLocalBranch(
      name, existing: localBranchNames, current: currentBranchName)
    {
      candidates.append(matched)
    }
    candidates.append(name)
    if name.hasPrefix("heads/") {
      candidates.append(String(name.dropFirst("heads/".count)))
    }
    var seen = Set<String>()
    for candidate in candidates where seen.insert(candidate).inserted && !candidate.isEmpty {
      let output = await git.run(
        args: ["show-ref", "--verify", "--quiet", "refs/heads/" + candidate],
        cwd: cwd
      )
      guard !cancelRequested else { return nil }
      if output.exitCode == 0 { return candidate }
    }
    return nil
  }

  func presentMergePicker() {
    guard !isDetached else { return }
    presentAfterDelay { self.showMerge = true }
  }

  var selectedTag: TagRecord? {
    tags.first { $0.name == selectedTagName }
  }

  private func clearTagSelection() {
    tagLoadToken += 1
    selectedTagName = nil
    selectedTagCommit = nil
    selectedCommitHash = nil
    selectedHistoryHash = nil
    selectedHistoryPath = nil
    diff = .empty
    diffTitle = ""
  }

  func selectTag(_ tag: TagRecord) async {
    guard mode == .tags, let cwd = repositoryURL else { return }
    tagLoadToken += 1
    let token = tagLoadToken
    selectedTagName = tag.name
    selectedTagCommit = nil
    selectedCommitHash = nil
    selectedHistoryHash = nil
    selectedHistoryPath = nil
    diff = .empty
    diffTitle = ""
    do {
      let target = try await git.perform {
        try await GitTags.target(reference: tag.commitHash, label: tag.name, repository: cwd)
      }
      guard token == tagLoadToken, repositoryURL == cwd, mode == .tags, selectedTagName == tag.name
      else { return }
      selectedTagCommit = target.commit
      await selectCommit(target.commit.hash)
    } catch {
      guard token == tagLoadToken, repositoryURL == cwd, mode == .tags, selectedTagName == tag.name
      else { return }
      dialog = .plain(
        title: L10n.message("读取 Tag 失败", "Unable to Load Tag"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
    }
  }

  func presentNewTag(reference: String, label: String) async {
    guard let cwd = repositoryURL, begin(L10n.message("正在读取 Tag 目标…", "Loading tag target…")) else {
      return
    }
    defer { end() }
    do {
      let target = try await git.perform {
        try await GitTags.target(reference: reference, label: label, repository: cwd)
      }
      guard !cancelRequested else { return }
      tagTarget = target
    } catch {
      guard !cancelRequested else { return }
      dialog = .plain(
        title: L10n.message("无法创建 Tag", "Unable to Create Tag"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
    }
  }

  func validateTagName(_ raw: String) async -> BranchNameCheck {
    guard let cwd = repositoryURL else { return .invalid }
    return await git.perform {
      await GitTags.validate(raw.trimmingCharacters(in: .whitespacesAndNewlines), repository: cwd)
    }
  }

  func createTag(named raw: String, target: TagTarget, annotated: Bool, message: String) async {
    guard let cwd = repositoryURL, begin(L10n.message("正在创建 Tag…", "Creating tag…")) else { return }
    defer { end() }
    do {
      try await git.perform {
        try await GitTags.create(
          name: raw.trimmingCharacters(in: .whitespacesAndNewlines), target: target,
          annotated: annotated, message: message, repository: cwd)
      }
      tagTarget = nil
      showBanner(L10n.message("已创建本地 Tag", "Local tag created"))
      await refresh(alertOnFailure: false)
    } catch {
      tagTarget = nil
      let message = error.localizedDescription
      presentAfterDelay {
        self.dialog = .plain(
          title: L10n.message("创建 Tag 失败", "Create Tag Failed"),
          message: L10n.message(message, message))
      }
    }
  }

  func pushTag(_ tag: TagRecord, remote: String) async {
    guard let cwd = repositoryURL, begin(L10n.message("正在推送 Tag…", "Pushing tag…")) else { return }
    defer { end() }
    do {
      try await git.perform { try await GitTags.push(tag, remote: remote, repository: cwd) }
      tagToPush = nil
      showBanner(L10n.message("已推送 Tag \(tag.name)", "Pushed tag \(tag.name)"))
    } catch {
      tagToPush = nil
      let message = error.localizedDescription
      presentAfterDelay {
        self.dialog = .plain(
          title: L10n.message("推送 Tag 失败", "Push Tag Failed"),
          message: L10n.message(message, message))
      }
    }
  }

  func deleteTag(_ tag: TagRecord) async {
    guard let cwd = repositoryURL, begin(L10n.message("正在删除本地 Tag…", "Deleting local tag…")) else {
      return
    }
    defer { end() }
    do {
      try await git.perform { try await GitTags.delete(tag, repository: cwd) }
      showBanner(L10n.message("已删除本地 Tag \(tag.name)", "Deleted local tag \(tag.name)"))
      await refresh(alertOnFailure: false)
    } catch {
      dialog = .plain(
        title: L10n.message("删除 Tag 失败", "Delete Tag Failed"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
    }
  }

  func presentBranchComparison() {
    guard !isWorking else { return }
    presentAfterDelay { self.showBranchComparison = true }
  }

  func prepareComparison(reference: String, label: String) async -> ComparisonRequest? {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在准备差异对比…", "Preparing comparison…"))
    else { return nil }
    defer { end() }
    do {
      let request = try await git.perform {
        try await GitComparison.snapshot(
          repository: cwd, reference: reference, label: label,
          headLabel: localizedBranchDisplayName
        )
      }
      guard !cancelRequested else { return nil }
      return request
    } catch {
      guard !cancelRequested else { return nil }
      showBranchComparison = false
      let message = error.localizedDescription
      presentAfterDelay {
        self.dialog = .plain(
          title: L10n.message("无法对比", "Unable to Compare"), message: L10n.message(message, message))
      }
      return nil
    }
  }

  func askMerge(_ source: String) {
    showMerge = false
    presentAfterDelay { self.dialog = .merge(source) }
  }

  func merge(source: String) async {
    guard !isDetached else {
      present(
        title: L10n.message("合并失败", "Merge Failed"),
        reason: L10n.message("请先创建或切换到一个分支。", "Create or switch to a branch first."),
        log: L10n.message("未执行 Git 命令。\n当前处于分离头指针。", "No Git command was run.\nHEAD is detached."))
      return
    }
    guard let cwd = repositoryURL, begin(L10n.message("正在合并（git merge）…", "Merging (git merge)…"))
    else { return }
    defer { end() }
    let output = await git.run(args: ["merge", source], cwd: cwd)
    guard !cancelRequested else { return }
    let text = output.stdoutText + "\n" + output.stderrText
    if output.exitCode == 0 {
      if text.localizedCaseInsensitiveContains("Already up to date") {
        showBanner(L10n.message("已经是最新", "Already up to date"))
      } else {
        showBanner(L10n.message("已合并 \(source)", "Merged \(source)"))
      }
      await refresh(alertOnFailure: true, updateDivergence: true)
      return
    }
    await refresh(alertOnFailure: false)
    let conflict =
      mergeInProgress || text.localizedCaseInsensitiveContains("CONFLICT")
      || text.localizedCaseInsensitiveContains("fix conflicts")
    present(action: L10n.message("合并", "Merge"), outputs: [output], conflict: conflict)
  }

  func abortMerge() async {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在中止合并（git merge --abort）…", "Aborting merge (git merge --abort)…"))
    else { return }
    defer { end() }
    let output = await git.run(args: ["merge", "--abort"], cwd: cwd)
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("中止合并", "Abort Merge"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    showBanner(L10n.message("已中止合并", "Merge aborted"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func commit() async {
    let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    let selected = files.filter { checkedPaths.contains($0.path) }
    guard !message.isEmpty, !selected.isEmpty else { return }
    let finishingMerge = mergeInProgress
    guard let cwd = repositoryURL,
      begin(
        finishingMerge
          ? L10n.message("正在完成合并（git add / commit）…", "Completing merge (git add / commit)…")
          : L10n.message("正在准备提交（git add）…", "Preparing commit (git add)…"))
    else { return }
    defer { end() }

    var outputs: [GitOutput] = []
    let uncheckedTracked = files.filter { !checkedPaths.contains($0.path) && $0.kind.isTracked }
      .map(\.path)
    if !uncheckedTracked.isEmpty {
      let restored = await git.runBatched(
        base: ["reset", "--"],
        paths: uncheckedTracked,
        cwd: cwd
      )
      outputs.append(contentsOf: restored)
      guard !cancelRequested else { return }
      if let failed = restored.last, failed.exitCode != 0 {
        present(action: L10n.message("提交", "Commit"), outputs: outputs)
        await refresh(alertOnFailure: false)
        return
      }
    }

    var pathsToAdd = selected.map(\.path)
    if selected.contains(where: { $0.kind == .deleted }) {
      let indexed = await git.run(args: ["ls-files", "-z"], cwd: cwd)
      outputs.append(indexed)
      guard !cancelRequested else { return }
      guard indexed.exitCode == 0 else {
        present(action: L10n.message("提交", "Commit"), outputs: outputs)
        await refresh(alertOnFailure: false)
        return
      }
      let indexedPaths = Set(
        indexed.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
      pathsToAdd = selected.filter {
        $0.kind != .deleted || indexedPaths.contains($0.path)
      }.map(\.path)
    }
    let added = await git.runBatched(base: ["add", "--"], paths: pathsToAdd, cwd: cwd)
    outputs.append(contentsOf: added)
    guard !cancelRequested else { return }
    if let failed = added.last, failed.exitCode != 0 {
      present(action: L10n.message("提交", "Commit"), outputs: outputs)
      await refresh(alertOnFailure: false)
      return
    }

    busyLabel =
      finishingMerge
      ? L10n.message("正在完成合并（git commit）…", "Completing merge (git commit)…")
      : L10n.message("正在提交（git commit）…", "Committing (git commit)…")
    let committed = await git.run(args: ["commit", "-m", message], cwd: cwd)
    outputs.append(committed)
    guard !cancelRequested else { return }
    guard committed.exitCode == 0 else {
      present(action: L10n.message("提交", "Commit"), outputs: outputs)
      await refresh(alertOnFailure: false)
      return
    }
    commitMessage = ""
    showBanner(
      finishingMerge ? L10n.message("已完成合并", "Merge completed") : L10n.message("已提交", "Committed"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func fetch() async {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在检查远程（git remote）…", "Checking remotes (git remote)…"))
    else { return }
    defer { end() }
    let remotes = await git.run(args: ["remote"], cwd: cwd)
    guard !cancelRequested else { return }
    guard remotes.exitCode == 0 else {
      present(action: L10n.message("获取", "Fetch"), outputs: [remotes])
      return
    }
    if remotes.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      present(
        title: L10n.message("获取失败", "Fetch Failed"),
        reason: L10n.message("该仓库没有远程。", "This repository has no remotes."),
        log: FailureLog.make(outputs: [remotes]))
      return
    }
    busyLabel = L10n.message("正在获取（git fetch）…", "Fetching (git fetch)…")
    let output = await git.run(args: ["fetch", "--prune"], cwd: cwd, timeout: 120)
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("获取", "Fetch"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    showBanner(L10n.message("已获取", "Fetched"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func pull() async {
    guard let cwd = repositoryURL, begin(L10n.message("正在拉取（git pull）…", "Pulling (git pull)…"))
    else { return }
    defer { end() }
    let output = await git.run(args: ["pull"], cwd: cwd, timeout: 120)
    guard !cancelRequested else { return }
    let text = output.stdoutText + "\n" + output.stderrText
    if output.exitCode == 0 {
      if text.localizedCaseInsensitiveContains("Already up to date") {
        showBanner(L10n.message("已经是最新", "Already up to date"))
      } else {
        showBanner(L10n.message("已拉取", "Pulled"))
      }
      await refresh(alertOnFailure: true, updateDivergence: true)
      return
    }
    await refresh(alertOnFailure: false, updateDivergence: true)
    let conflict =
      mergeInProgress || text.localizedCaseInsensitiveContains("CONFLICT")
      || text.localizedCaseInsensitiveContains("fix conflicts")
    present(action: L10n.message("拉取", "Pull"), outputs: [output], conflict: conflict)
  }

  func push() async {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在检查上游（git rev-parse）…", "Checking upstream (git rev-parse)…"))
    else { return }
    defer { end() }
    guard let branch = currentBranchName, !isDetached else {
      present(
        title: L10n.message("推送失败", "Push Failed"),
        reason: L10n.message("当前不在分支上，无法推送。", "Cannot push while HEAD is detached."),
        log: L10n.message("未执行 git push。", "git push was not run."))
      return
    }
    let upstream = await git.run(
      args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
      cwd: cwd
    )
    guard !cancelRequested else { return }
    let output: GitOutput
    if upstream.exitCode == 0 {
      busyLabel = L10n.message("正在推送（git push）…", "Pushing (git push)…")
      output = await git.run(args: ["push"], cwd: cwd, timeout: 120)
    } else {
      let remotes = await git.run(args: ["remote"], cwd: cwd)
      guard !cancelRequested else { return }
      let names = remotes.stdoutText.split(separator: "\n").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard names.contains("origin") else {
        present(
          title: L10n.message("推送失败", "Push Failed"),
          reason: L10n.message("无法推送：没有名为 origin 的远程。", "Cannot push: no remote named origin."),
          log: FailureLog.make(outputs: [remotes]))
        return
      }
      busyLabel = L10n.message(
        "正在推送并设置上游（git push -u）…", "Pushing and setting upstream (git push -u)…")
      output = await git.run(
        args: ["push", "-u", "origin", branch],
        cwd: cwd,
        timeout: 120
      )
    }
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("推送", "Push"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    showBanner(L10n.message("已推送", "Pushed"))
    await refresh(alertOnFailure: true, updateDivergence: true)
  }

  func discard(files targets: [FileChange]) async {
    guard !targets.isEmpty, let cwd = repositoryURL,
      begin(L10n.message("正在放弃所选修改…", "Discarding selected changes…"))
    else { return }
    defer { end() }
    await discardSelectedFiles(targets, cwd: cwd)
    await refresh(alertOnFailure: false)
  }

  private func discardSelectedFiles(_ targets: [FileChange], cwd: URL) async {
    let paths = Set(
      targets.filter { $0.kind.isTracked }.flatMap { file in
        [file.path] + (file.oldPath.map { [$0] } ?? [])
      }
    ).sorted()
    if !paths.isEmpty {
      let outputs = await git.runBatched(
        base: ["restore", "--source=HEAD", "--worktree", "--staged", "--"],
        paths: paths.map { ":(literal)" + $0 }, cwd: cwd
      )
      guard !cancelRequested else { return }
      if outputs.contains(where: { $0.exitCode != 0 }) {
        present(action: L10n.message("放弃修改", "Discard Changes"), outputs: outputs)
        return
      }
    }
    for file in targets where file.kind == .untracked {
      guard !cancelRequested else { return }
      do {
        try FileManager.default.trashItem(
          at: cwd.appendingPathComponent(file.path), resultingItemURL: nil)
      } catch {
        present(
          title: L10n.message("放弃修改失败", "Discard Changes Failed"),
          reason: L10n.message("无法把文件移到废纸篓。", "Unable to move the file to Trash."),
          log: LocalizedText(error.localizedDescription, error.localizedDescription))
        return
      }
    }
    showBanner(L10n.message("已放弃所选修改", "Selected changes discarded"))
  }

  func ignore(files targets: [FileChange], folders: Bool) async {
    let paths = Set(
      targets.compactMap { file -> String? in
        let path = folders ? (file.path as NSString).deletingLastPathComponent : file.path
        return path.isEmpty || path == "." || path == "/" ? nil : path
      }
    ).sorted()
    guard !paths.isEmpty, let cwd = repositoryURL,
      begin(L10n.message("正在忽略所选项目…", "Ignoring selected items…"))
    else { return }
    defer { end() }
    var trackedPaths: [String] = []
    for path in paths {
      let tracked = await git.run(
        args: ["ls-files", "-z", "--", ":(literal)" + path + (folders ? "/" : "")], cwd: cwd)
      guard !cancelRequested else { return }
      guard tracked.exitCode == 0 else {
        present(action: L10n.message("忽略", "Ignore"), outputs: [tracked])
        return
      }
      if !tracked.stdout.isEmpty { trackedPaths.append(path) }
    }
    do {
      for path in paths {
        try appendGitignore(repo: cwd, pattern: "/" + gitignorePattern(path) + (folders ? "/" : ""))
      }
    } catch {
      dialog = .plain(
        title: L10n.message("忽略失败", "Ignore Failed"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
      return
    }
    if trackedPaths.isEmpty {
      showBanner(L10n.message("已写入 .gitignore", "Added to .gitignore"))
    } else {
      dialog = .removePathsFromIndex(trackedPaths, folders: folders)
    }
    await refresh(alertOnFailure: false)
  }

  func removeFromIndex(paths: [String], isDirectory: Bool) async {
    guard !paths.isEmpty, let cwd = repositoryURL,
      begin(L10n.message("正在移出索引…", "Removing from index…"))
    else { return }
    defer { end() }
    let outputs = await git.runBatched(
      base: ["rm", "--cached", "--ignore-unmatch"] + (isDirectory ? ["-r"] : []) + ["--"],
      paths: paths.map { ":(literal)" + $0 }, cwd: cwd
    )
    guard !cancelRequested else { return }
    if outputs.contains(where: { $0.exitCode != 0 }) {
      present(action: L10n.message("移出索引", "Remove from Index"), outputs: outputs)
    } else {
      showBanner(L10n.message("已从索引移除", "Removed from index"))
    }
    await refresh(alertOnFailure: false)
  }

  func discard(_ file: FileChange) async {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在放弃修改（git restore）…", "Discarding changes (git restore)…"))
    else { return }
    defer { end() }
    if file.kind == .untracked {
      let url = cwd.appendingPathComponent(file.path)
      do {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      } catch {
        let raw = error.localizedDescription
        present(
          title: L10n.message("放弃修改失败", "Discard Changes Failed"),
          reason: L10n.message("无法把文件移到废纸篓。", "Unable to move the file to Trash."),
          log: LocalizedText(raw, raw))
        return
      }
      showBanner(L10n.message("已移到废纸篓", "Moved to Trash"))
      await refresh(alertOnFailure: true)
      return
    }
    var paths = [file.path]
    if let oldPath = file.oldPath {
      paths.append(oldPath)
    }
    let output = await git.run(
      args: ["restore", "--source=HEAD", "--worktree", "--staged", "--"] + paths,
      cwd: cwd
    )
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("放弃修改", "Discard Changes"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    showBanner(L10n.message("已放弃修改", "Changes discarded"))
    await refresh(alertOnFailure: true)
  }

  func ignore(_ file: FileChange) {
    guard let cwd = repositoryURL else { return }
    do {
      try appendGitignore(repo: cwd, pattern: gitignorePattern(file.path))
    } catch {
      dialog = .plain(
        title: L10n.message("忽略文件失败", "Ignore File Failed"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
      return
    }
    if file.kind.isTracked {
      dialog = .removeFromIndex(file)
    } else {
      showBanner(L10n.message("已写入 .gitignore", "Added to .gitignore"))
    }
    Task { await refresh(alertOnFailure: false) }
  }

  func ignoreFolder(_ file: FileChange) async {
    let directory = (file.path as NSString).deletingLastPathComponent
    guard !directory.isEmpty, directory != ".", directory != "/",
      let cwd = repositoryURL,
      begin(L10n.message("正在忽略文件夹…", "Ignoring folder…"))
    else { return }
    defer { end() }
    let tracked = await git.run(
      args: ["ls-files", "-z", "--", ":(literal)" + directory + "/"], cwd: cwd)
    guard !cancelRequested else { return }
    guard tracked.exitCode == 0 else {
      present(action: L10n.message("忽略文件夹", "Ignore Folder"), outputs: [tracked])
      return
    }
    do {
      try appendGitignore(repo: cwd, pattern: "/" + gitignorePattern(directory) + "/")
    } catch {
      dialog = .plain(
        title: L10n.message("忽略文件夹失败", "Ignore Folder Failed"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
      return
    }
    if !tracked.stdout.isEmpty {
      dialog = .removeFolderFromIndex(directory)
    } else {
      showBanner(L10n.message("已写入 .gitignore", "Added to .gitignore"))
    }
    await refresh(alertOnFailure: false)
  }

  func removeFromIndex(_ file: FileChange) async {
    await removeFromIndex(path: file.path)
  }

  func removeFromIndex(path: String, isDirectory: Bool = false) async {
    guard let cwd = repositoryURL,
      begin(L10n.message("正在移出索引（git rm --cached）…", "Removing from index (git rm --cached)…"))
    else { return }
    defer { end() }
    let pathspec = isDirectory ? ":(literal)" + path : path
    let arguments = ["rm", "--cached"] + (isDirectory ? ["-r"] : []) + ["--", pathspec]
    let output = await git.run(args: arguments, cwd: cwd)
    guard !cancelRequested else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("忽略文件", "Ignore File"), outputs: [output])
      await refresh(alertOnFailure: false)
      return
    }
    showBanner(L10n.message("已从索引移除", "Removed from index"))
    await refresh(alertOnFailure: true)
  }

  func reveal(_ file: FileChange) {
    guard let cwd = repositoryURL else { return }
    let url = cwd.appendingPathComponent(file.path)
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
  }

  func openInVSCode(_ file: FileChange) {
    guard let cwd = repositoryURL else { return }
    let url = cwd.appendingPathComponent(file.path)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
    else {
      dialog = .vscodeMissing
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Visual Studio Code", "--", url.path]
    do {
      try process.run()
    } catch {
      dialog = .plain(
        title: L10n.message("无法打开 VS Code", "Unable to Open VS Code"),
        message: L10n.message(error.localizedDescription, error.localizedDescription))
    }
  }

  enum FileCopyValue {
    case name
    case path
    case contents
  }

  @discardableResult
  func copyFiles(_ targets: [FileChange], value: FileCopyValue, pasteboard: NSPasteboard = .general)
    -> Bool
  {
    guard !targets.isEmpty, let cwd = repositoryURL else { return false }
    let text: String
    switch value {
    case .name:
      text = targets.map { ($0.path as NSString).lastPathComponent }.joined(separator: "\n")
    case .path:
      text = targets.map { cwd.appendingPathComponent($0.path).path }.joined(separator: "\n")
    case .contents:
      guard targets.count == 1, let file = targets.first else { return false }
      do {
        text = try String(contentsOf: cwd.appendingPathComponent(file.path), encoding: .utf8)
      } catch {
        dialog = .plain(
          title: L10n.message("复制文件内容失败", "Unable to Copy File Contents"),
          message: L10n.message(
            "无法读取 UTF-8 文本文件：\(file.path)\n\(error.localizedDescription)",
            "Unable to read UTF-8 text file: \(file.path)\n\(error.localizedDescription)")
        )
        return false
      }
    }
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      dialog = .plain(
        title: L10n.message("复制失败", "Copy Failed"),
        message: L10n.message("无法写入剪贴板。", "Unable to write to the clipboard."))
      return false
    }
    showBanner(L10n.message("已复制到剪贴板", "Copied to clipboard"))
    return true
  }

  func fileExists(_ file: FileChange) -> Bool {
    guard let cwd = repositoryURL else { return false }
    return FileManager.default.fileExists(atPath: cwd.appendingPathComponent(file.path).path)
  }

  private func loadRepository(folder: URL, silentIfInvalid: Bool) async {
    guard beginRepositoryLoad() else { return }
    defer { endRepositoryLoad() }
    await open(folder: folder, silentIfInvalid: silentIfInvalid)
  }

  private func startLoadingRepository(folder: URL, silentIfInvalid: Bool) {
    guard beginRepositoryLoad() else { return }
    Task {
      defer { endRepositoryLoad() }
      await open(folder: folder, silentIfInvalid: silentIfInvalid)
    }
  }

  private func beginRepositoryLoad() -> Bool {
    guard !isWorking, !isWindowClosed else { return false }
    cancelRequested = false
    isRefreshing = true
    refreshLabel = L10n.message("正在打开项目（git rev-parse）…", "Opening project (git rev-parse)…")
    return true
  }

  private func endRepositoryLoad() {
    isRefreshing = false
    refreshLabel = L10n.message("", "")
    cancelRequested = false
  }

  private func open(folder: URL, silentIfInvalid: Bool) async {
    let probe = await git.run(args: ["rev-parse", "--show-toplevel"], cwd: folder)
    guard !cancelRequested, !isWindowClosed else { return }
    let top = probe.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard probe.exitCode == 0, !top.isEmpty else {
      if !silentIfInvalid {
        dialog = .notRepository
      }
      return
    }
    if let existing = ProjectWindows.shared.claim(top, owner: windowID) {
      ProjectWindows.shared.activate(existing)
      return
    }
    if repositoryPath != top {
      generation += 1
      resetWorkspace()
    }
    repositoryPath = top
    if emptyWindowTheme != .blue {
      ProjectAppearance.shared.setTheme(emptyWindowTheme, for: top)
      emptyWindowTheme = .blue
    }
    repositoryDisplayName = URL(fileURLWithPath: top).lastPathComponent
    RecentsStore.setLastRepository(top)
    recentRepositoryPaths = RecentsStore.recentRepositories()
    recentBranchNames = RecentsStore.recentBranches(for: top)
    let origin = await git.run(
      args: ["remote", "get-url", "origin"],
      cwd: URL(fileURLWithPath: top, isDirectory: true)
    )
    guard !cancelRequested else { return }
    if origin.exitCode == 0,
      let name = Self.repositoryName(from: origin.stdoutText)
    {
      repositoryDisplayName = name
    }
    refreshLabel = L10n.message("正在刷新（git status / log）…", "Refreshing (git status / log)…")
    await refresh(alertOnFailure: !silentIfInvalid, updateDivergence: true)
  }

  private static func repositoryName(from remote: String) -> String? {
    let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let component = value.split(whereSeparator: { $0 == "/" || $0 == ":" }).last else {
      return nil
    }
    let name =
      String(component).hasSuffix(".git")
      ? String(String(component).dropLast(4))
      : String(component)
    return name.isEmpty ? nil : name
  }

  private func refresh(alertOnFailure: Bool, updateDivergence: Bool = false) async {
    guard !isWindowClosed, let cwd = repositoryURL else { return }
    let gen = generation
    if isRefreshing {
      refreshLabel = L10n.message(
        "正在读取状态和分支（git status / branch）…", "Reading status and branches (git status / branch)…")
    }

    async let status = git.run(args: ["status", "--porcelain=v1", "-z", "-uall"], cwd: cwd)
    async let showCurrent = git.run(args: ["branch", "--show-current"], cwd: cwd)
    async let locals = git.run(
      args: ["for-each-ref", "--format=%(HEAD)%09%(refname)", "refs/heads"],
      cwd: cwd
    )
    async let remotes = git.run(
      args: [
        "for-each-ref", "--format=%(refname)%09%(symref)", "refs/remotes",
      ],
      cwd: cwd
    )
    async let branchesAtHead = git.run(
      args: ["for-each-ref", "--format=%(refname)", "--points-at", "HEAD", "refs/heads"],
      cwd: cwd
    )
    async let head = git.run(args: ["rev-parse", "--short=7", "HEAD"], cwd: cwd)
    async let mergeHead = git.run(args: ["rev-parse", "-q", "--verify", "MERGE_HEAD"], cwd: cwd)

    let statusOut = await status
    let currentOut = await showCurrent
    let localOut = await locals
    let remoteOut = await remotes
    let branchesAtHeadOut = await branchesAtHead
    let headOut = await head
    let mergeOut = await mergeHead
    guard !cancelRequested else { return }
    guard gen == generation else { return }

    guard statusOut.exitCode == 0 else {
      if alertOnFailure {
        present(action: L10n.message("刷新", "Refresh"), outputs: [statusOut])
      } else {
        showBanner(L10n.message("刷新失败", "Refresh failed"))
      }
      return
    }

    applyFiles(StatusParser.parse(statusOut.stdout))
    let current = currentOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    localBranchNames = LogParser.parseLocalBranches(localOut.stdoutText).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
    remoteBranchNames = LogParser.parseRemoteBranches(remoteOut.stdoutText)
    if let repositoryPath {
      recentBranchNames = RecentsStore.recentBranches(for: repositoryPath).compactMap { name in
        LogParser.matchingLocalBranch(name, existing: localBranchNames, current: current)
      }
    }

    let previousBranch = currentBranchName
    let wasDetached = isDetached
    if !current.isEmpty {
      isDetached = false
      currentBranchName = current
      branchDisplayName = current
      detachedBranchName = nil
    } else if headOut.exitCode == 0 {
      let hash = headOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
      let exactBranches =
        branchesAtHeadOut.exitCode == 0
        ? LogParser.parseRefNames(branchesAtHeadOut.stdoutText) : []
      isDetached = true
      currentBranchName = nil
      branchDisplayName = hash.isEmpty ? "分离头指针" : hash
      detachedBranchName = LogParser.preferredDetachedBranch(
        exact: exactBranches, recent: recentBranchNames)
    } else {
      isDetached = false
      currentBranchName = nil
      branchDisplayName = "尚无提交"
      detachedBranchName = nil
    }

    if updateDivergence {
      if isRefreshing {
        refreshLabel = L10n.message("正在计算待推送和待拉取提交…", "Counting outgoing and incoming commits…")
      }
      await updateDivergenceCounts(cwd: cwd, generation: gen)
      guard !cancelRequested else { return }
    } else if currentBranchName != previousBranch || isDetached != wasDetached {
      unpushedCount = nil
      remoteAheadCount = nil
    }
    guard gen == generation else { return }

    let merging =
      mergeOut.exitCode == 0
      && !mergeOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    mergeInProgress = merging
    mergeSource = merging ? await readMergeSource(cwd: cwd) : ""
    guard !cancelRequested else { return }
    guard gen == generation else { return }

    if isRefreshing {
      refreshLabel = L10n.message("正在读取提交历史（git log）…", "Reading commit history (git log)…")
    }
    do {
      let loadedTags = try await git.perform { try await GitTags.list(repository: cwd) }
      guard !cancelRequested, gen == generation else { return }
      tags = loadedTags
      tagListError = nil
      if mode == .tags {
        if let tag = selectedTag ?? tags.first {
          if selectedTagCommit?.hash != tag.commitHash || selectedTagName != tag.name {
            await selectTag(tag)
          }
        } else {
          clearTagSelection()
        }
      }
    } catch {
      guard !cancelRequested, gen == generation else { return }
      tagListError = error.localizedDescription
    }
    await loadHistory(reset: true, alertOnFailure: false, generation: gen)
    guard !cancelRequested else { return }
    guard gen == generation else { return }
    if isRefreshing, selectedPath != nil || selectedHistoryPath != nil {
      refreshLabel = L10n.message("正在加载文件差异（git diff）…", "Loading file diff (git diff)…")
    }
    await reloadVisibleDiff()
  }

  private func updateDivergenceCounts(cwd: URL, generation gen: Int) async {
    guard !isDetached, let currentBranchName else {
      unpushedCount = nil
      remoteAheadCount = nil
      return
    }

    let upstreamOutput = await git.run(
      args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
      cwd: cwd
    )
    guard !cancelRequested else { return }
    guard gen == generation else { return }

    let configuredUpstream = upstreamOutput.stdoutText.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let comparisonRef: String?
    if upstreamOutput.exitCode == 0, !configuredUpstream.isEmpty {
      comparisonRef = configuredUpstream
    } else {
      let originCandidate = "origin/\(currentBranchName)"
      if remoteBranchNames.contains(originCandidate) {
        comparisonRef = originCandidate
      } else {
        let matching = remoteBranchNames.filter { $0.hasSuffix("/\(currentBranchName)") }
        comparisonRef = matching.count == 1 ? matching[0] : nil
      }
    }

    guard let comparisonRef else {
      let remotes = await git.run(args: ["remote"], cwd: cwd)
      guard !cancelRequested, gen == generation else { return }
      let names = remotes.stdoutText.split(separator: "\n").map(String.init)
      let targetRemote = names.contains("origin") ? "origin" : (names.count == 1 ? names[0] : nil)
      guard remotes.exitCode == 0, let targetRemote else {
        unpushedCount = nil
        remoteAheadCount = nil
        return
      }
      let local = await git.run(
        args: ["rev-list", "--count", "HEAD", "--not", "--remotes=\(targetRemote)"],
        cwd: cwd
      )
      guard !cancelRequested, gen == generation else { return }
      unpushedCount =
        local.exitCode == 0
        ? Int(local.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
      remoteAheadCount = nil
      return
    }

    async let unpushedOutput = git.run(
      args: ["rev-list", "--count", "\(comparisonRef)..HEAD"],
      cwd: cwd
    )
    async let remoteAheadOutput = git.run(
      args: ["rev-list", "--count", "HEAD..\(comparisonRef)"],
      cwd: cwd
    )
    let local = await unpushedOutput
    let remote = await remoteAheadOutput
    guard !cancelRequested else { return }
    guard gen == generation else { return }

    guard local.exitCode == 0,
      remote.exitCode == 0,
      let unpushed = Int(local.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)),
      let remoteAhead = Int(remote.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      unpushedCount = nil
      remoteAheadCount = nil
      return
    }
    unpushedCount = unpushed
    remoteAheadCount = remoteAhead
  }

  private func loadHistory(reset: Bool, alertOnFailure: Bool, generation gen: Int? = nil) async {
    guard let cwd = repositoryURL else { return }
    let token = gen ?? generation
    let skip = reset ? 0 : commits.count
    var arguments = ["log"]
    switch historyScope {
    case .current:
      break
    case .mainline:
      arguments.append("--first-parent")
    case .all:
      arguments.append(contentsOf: ["--all", "--topo-order", "--date-order"])
    }
    arguments.append(contentsOf: [
      "-n", "100", "--skip", "\(skip)",
      "--pretty=format:%H%x1f%P%x1f%D%x1f%an%x1f%ae%x1f%at%x1f%s%x1e",
    ])
    let output = await git.run(
      args: arguments,
      cwd: cwd
    )
    guard !cancelRequested else { return }
    guard token == generation else { return }
    if output.exitCode != 0 {
      let blob = output.stderrText + output.stdoutText
      if blob.contains("does not have any commits") {
        if reset {
          commits = []
          canLoadMoreHistory = false
        }
        return
      }
      if alertOnFailure {
        present(action: L10n.message("刷新", "Refresh"), outputs: [output])
      }
      return
    }
    let parsed = LogParser.parseCommits(output.stdoutText)
    if reset {
      commits = parsed
    } else {
      commits.append(contentsOf: parsed)
    }
    canLoadMoreHistory = parsed.count == 100

    if reset, mode == .history {
      let selectionIsVisible =
        selectedCommitHash.map { selected in
          commits.contains { $0.hash == selected }
        } ?? false
      if !selectionIsVisible, let first = commits.first {
        await selectCommit(first.hash)
      }
    }
  }

  private func applyFiles(_ parsed: [FileChange]) {
    let paths = Set(parsed.map(\.path))
    let brandNew = paths.subtracting(seenPaths)
    var nextChecked = checkedPaths.intersection(paths)
    nextChecked.formUnion(brandNew)
    files = parsed
    selectedChangePaths.formIntersection(paths)
    checkedPaths = nextChecked
    seenPaths = paths
    if let selectedPath, !paths.contains(selectedPath) {
      self.selectedPath = nil
      if mode == .changes {
        diff = .empty
        diffTitle = ""
      }
    }
  }

  private func reloadVisibleDiff() async {
    if mode != .changes, let hash = selectedHistoryHash, let path = selectedHistoryPath {
      await loadHistoryDiff(hash: hash, path: path)
    } else if mode == .changes, let path = selectedPath {
      await loadWorktreeDiff(path)
    }
  }

  private func loadWorktreeDiff(_ path: String) async {
    guard mode == .changes, selectedPath == path, let cwd = repositoryURL else { return }
    diffToken += 1
    let token = diffToken
    let file = files.first { $0.path == path }
    var output: GitOutput
    var allowed: Set<Int32>
    if file?.kind == .untracked {
      output = await git.run(
        args: ["diff", "--no-index", "--no-ext-diff", "--no-color", "--", "/dev/null", path],
        cwd: cwd
      )
      allowed = [0, 1]
    } else {
      output = await git.run(
        args: ["diff", "--no-ext-diff", "--no-color", "HEAD", "--", path],
        cwd: cwd
      )
      allowed = [0]
      if output.exitCode != 0, output.stderrText.contains("bad revision"), file?.kind != .deleted {
        output = await git.run(
          args: ["diff", "--no-index", "--no-ext-diff", "--no-color", "--", "/dev/null", path],
          cwd: cwd
        )
        allowed = [0, 1]
      }
    }
    guard !cancelRequested else { return }
    guard token == diffToken, mode == .changes, repositoryURL == cwd, selectedPath == path else {
      return
    }
    guard allowed.contains(output.exitCode) else {
      diff = .empty
      diffTitle = path
      present(action: L10n.message("刷新", "Refresh"), outputs: [output])
      return
    }
    diff = DiffParser.parse(output.stdoutText)
    diffTitle = path
  }

  private func loadHistoryDiff(hash: String, path: String) async {
    guard let cwd = repositoryURL else { return }
    diffToken += 1
    let token = diffToken
    let output = await git.run(
      args: [
        "show", "-m", "--first-parent", "--format=",
        "--no-ext-diff", "--no-color", hash, "--", path,
      ],
      cwd: cwd
    )
    guard !cancelRequested else { return }
    guard token == diffToken, mode != .changes, repositoryURL == cwd, selectedHistoryHash == hash,
      selectedHistoryPath == path
    else { return }
    guard output.exitCode == 0 else {
      present(action: L10n.message("刷新", "Refresh"), outputs: [output])
      return
    }
    diff = DiffParser.parse(output.stdoutText)
    diffTitle = path
  }

  private func readMergeSource(cwd: URL) async -> String {
    let pathOut = await git.run(args: ["rev-parse", "--git-path", "MERGE_MSG"], cwd: cwd)
    let relative = pathOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard pathOut.exitCode == 0, !relative.isEmpty else { return "" }
    let url =
      relative.hasPrefix("/")
      ? URL(fileURLWithPath: relative) : cwd.appendingPathComponent(relative)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    if let name = quotedName(in: first, prefix: "Merge branch '") { return name }
    if let name = quotedName(in: first, prefix: "Merge remote-tracking branch '") { return name }
    return ""
  }

  private func presentAfterDelay(_ body: @escaping @MainActor () -> Void) {
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      body()
    }
  }

  private func startRefresh(
    label: LocalizedText,
    operation: @escaping @MainActor () async -> Void
  ) {
    guard !isWorking, !isWindowClosed else { return }
    cancelRequested = false
    isRefreshing = true
    refreshLabel = label
    Task {
      defer {
        isRefreshing = false
        refreshLabel = L10n.message("", "")
        cancelRequested = false
      }
      await operation()
    }
  }

  private func begin(_ label: LocalizedText) -> Bool {
    guard !isWorking, !isWindowClosed else { return false }
    if let repository = repositoryURL?.resolvingSymlinksInPath().standardizedFileURL.path {
      guard RepositoryOperations.acquire(repository, owner: git.owner) else {
        showBanner(
          L10n.message(
            "另一个窗口正在操作此仓库，请稍后重试。",
            "Another window is operating on this repository. Please try again shortly."))
        return false
      }
      operationRepository = repository
    }
    cancelRequested = false
    isBusy = true
    busyLabel = label
    generation += 1
    return true
  }

  private func end() {
    if let operationRepository {
      RepositoryOperations.release(operationRepository, owner: git.owner)
      self.operationRepository = nil
    }
    isBusy = false
    busyLabel = L10n.message("", "")
    cancelRequested = false
  }

  private func showBanner(_ text: LocalizedText) {
    banner = text
    bannerToken += 1
    let token = bannerToken
    Task {
      try? await Task.sleep(for: .seconds(4))
      guard bannerToken == token else { return }
      banner = nil
    }
  }

  private func present(action: LocalizedText, outputs: [GitOutput], conflict: Bool = false) {
    present(
      title: L10n.message("\(action.chinese)失败", "\(action.english) Failed"),
      reason: FailureLog.reason(action: action, outputs: outputs, conflict: conflict),
      log: FailureLog.make(outputs: outputs)
    )
  }

  private func present(title: LocalizedText, reason: LocalizedText, log: LocalizedText) {
    failure = FailureReport(title: title, reason: reason, log: FailureLog.truncate(log))
  }

  private func resetWorkspace() {
    tagLoadToken += 1
    savedHistoryHash = nil
    savedHistoryPath = nil
    tagSelectedPaths = [:]
    tags = []
    selectedTagName = nil
    selectedTagCommit = nil
    tagTarget = nil
    tagToPush = nil
    tagListError = nil
    selectedChangePaths = []
    files = []
    checkedPaths = []
    seenPaths = []
    selectedPath = nil
    commits = []
    canLoadMoreHistory = false
    selectedCommitHash = nil
    loadingCommitHash = nil
    commitFiles = [:]
    commitBranches = [:]
    selectedHistoryHash = nil
    selectedHistoryPath = nil
    diff = .empty
    diffTitle = ""
    commitMessage = ""
    mergeInProgress = false
    mergeSource = ""
    banner = nil
    localBranchNames = []
    remoteBranchNames = []
    recentBranchNames = []
    currentBranchName = nil
    branchDisplayName = ""
    detachedBranchName = nil
    unpushedCount = nil
    remoteAheadCount = nil
    isDetached = false
  }
}

@MainActor
enum RepositoryOperations {
  private static var owners: [String: UUID] = [:]

  static func acquire(_ path: String, owner: UUID) -> Bool {
    guard owners[path] == nil else { return false }
    owners[path] = owner
    return true
  }

  static func release(_ path: String, owner: UUID) {
    guard owners[path] == owner else { return }
    owners.removeValue(forKey: path)
  }
}

private func quotedName(in line: String, prefix: String) -> String? {
  guard line.hasPrefix(prefix) else { return nil }
  let rest = line.dropFirst(prefix.count)
  guard let end = rest.firstIndex(of: "'") else { return nil }
  let name = String(rest[..<end])
  return name.isEmpty ? nil : name
}

private func gitignorePattern(_ relativePath: String) -> String {
  var result = ""
  for character in relativePath {
    if "*?[]".contains(character) {
      result.append("\\")
    }
    result.append(character)
  }
  return result
}

private func appendGitignore(repo: URL, pattern: String) throws {
  let file = repo.appendingPathComponent(".gitignore")
  var existing = ""
  if FileManager.default.fileExists(atPath: file.path) {
    existing = try String(contentsOf: file, encoding: .utf8)
  }
  if existing.components(separatedBy: "\n").contains(pattern) { return }
  if !existing.isEmpty && !existing.hasSuffix("\n") {
    existing += "\n"
  }
  existing += pattern + "\n"
  try existing.write(to: file, atomically: true, encoding: .utf8)
}
