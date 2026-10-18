import AppKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var repositoryPath: String?
    var branchDisplayName = ""
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

    var mode: SidebarMode = .changes
    var commits: [CommitRecord] = []
    var canLoadMoreHistory = false
    var expandedCommit: String?
    var commitFiles: [String: [CommitFile]] = [:]
    var selectedHistoryHash: String?
    var selectedHistoryPath: String?

    var diff = DiffDocument.empty
    var diffTitle = ""

    var commitMessage = ""
    var isBusy = false
    var busyLabel = ""
    var isRefreshing = false
    var refreshLabel = ""
    var banner: String?
    var mergeInProgress = false
    var mergeSource = ""

    var failure: FailureReport?
    var dialog: AppDialog?
    var showNewBranch = false
    var showMerge = false

    private var seenPaths: Set<String> = []
    private var generation = 0
    private var didRestore = false
    private var userChoseRepository = false
    private var bannerToken = 0
    private var diffToken = 0
    private var cancelRequested = false

    var repositoryURL: URL? {
        repositoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var windowTitle: String {
        guard let repositoryPath else { return "GitSync" }
        return URL(fileURLWithPath: repositoryPath).lastPathComponent
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

    var showsCommitBar: Bool {
        mode == .changes || mergeInProgress
    }

    func chooseRepository() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择一个本地 Git 仓库文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        userChoseRepository = true
        startLoadingRepository(folder: url, silentIfInvalid: false)
    }

    func openRecentRepository(_ path: String) {
        guard !isWorking else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            dialog = .plain(title: "无法打开项目", message: "项目路径已不存在：\n\(path)")
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
        guard FileManager.default.fileExists(atPath: last, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        await loadRepository(
            folder: URL(fileURLWithPath: last, isDirectory: true),
            silentIfInvalid: true
        )
    }

    func refreshNow() {
        guard !isWorking, repositoryPath != nil else { return }
        startRefresh(label: "正在刷新（git status / log）…") {
            await self.refresh(alertOnFailure: true, updateDivergence: true)
        }
    }

    func refreshIfIdle() {
        guard !isWorking, repositoryPath != nil else { return }
        startRefresh(label: "正在刷新仓库状态…") {
            await self.refresh(alertOnFailure: false)
        }
    }

    func cancelCurrentOperation() {
        guard isWorking else { return }
        cancelRequested = true
        if isBusy {
            busyLabel = "正在取消 Git 操作…"
        } else {
            refreshLabel = "正在取消刷新…"
        }
        GitClient.cancelAll()
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
        mode = newMode
        if newMode == .history {
            if let hash = selectedHistoryHash, let path = selectedHistoryPath {
                Task { await loadHistoryDiff(hash: hash, path: path) }
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

    func toggleCommit(_ hash: String) async {
        if expandedCommit == hash {
            expandedCommit = nil
            return
        }
        expandedCommit = hash
        guard commitFiles[hash] == nil, let cwd = repositoryURL else { return }
        let output = await GitClient.run(
            args: ["show", "--first-parent", "-z", "--name-status", "--pretty=format:", hash],
            cwd: cwd
        )
        guard expandedCommit == hash else { return }
        guard output.exitCode == 0 else {
            present(action: "刷新", outputs: [output])
            return
        }
        var loaded = commitFiles
        loaded[hash] = LogParser.parseNameStatus(output.stdout)
        commitFiles = loaded
    }

    func selectHistoryFile(hash: String, path: String) {
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
        let output = await GitClient.run(args: ["check-ref-format", "--branch", name], cwd: cwd)
        return output.exitCode == 0 ? .ok : .invalid
    }

    func switchBranch(_ item: BranchItem) async {
        if !item.isRemote, item.name == currentBranchName { return }
        guard let cwd = repositoryURL, begin("正在切换分支（git switch）…") else { return }
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
            args = ["switch", item.name]
            remembered = item.name
        }
        let output = await GitClient.run(args: args, cwd: cwd)
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "切换分支", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        if let repositoryPath {
            RecentsStore.rememberBranch(remembered, repository: repositoryPath)
        }
        showBanner("已切换到 \(remembered)")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func createBranch(named raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cwd = repositoryURL, begin("正在创建分支（git switch -c）…") else { return }
        defer { end() }
        let output = await GitClient.run(args: ["switch", "-c", name], cwd: cwd)
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            showNewBranch = false
            presentAfterDelay { self.present(action: "新建分支", outputs: [output]) }
            await refresh(alertOnFailure: false)
            return
        }
        if let repositoryPath {
            RecentsStore.rememberBranch(name, repository: repositoryPath)
        }
        showNewBranch = false
        showBanner("已创建并切换到 \(name)")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func presentNewBranch() {
        presentAfterDelay { self.showNewBranch = true }
    }

    func presentMergePicker() {
        guard !isDetached else { return }
        presentAfterDelay { self.showMerge = true }
    }

    func askMerge(_ source: String) {
        showMerge = false
        presentAfterDelay { self.dialog = .merge(source) }
    }

    func merge(source: String) async {
        guard !isDetached else {
            present(title: "合并失败", reason: "请先创建或切换到一个分支。", log: "未执行 Git 命令。\n当前处于分离头指针。")
            return
        }
        guard let cwd = repositoryURL, begin("正在合并（git merge）…") else { return }
        defer { end() }
        let output = await GitClient.run(args: ["merge", source], cwd: cwd)
        guard !cancelRequested else { return }
        let text = output.stdoutText + "\n" + output.stderrText
        if output.exitCode == 0 {
            if text.localizedCaseInsensitiveContains("Already up to date") {
                showBanner("已经是最新")
            } else {
                showBanner("已合并 \(source)")
            }
            await refresh(alertOnFailure: true, updateDivergence: true)
            return
        }
        await refresh(alertOnFailure: false)
        let conflict = mergeInProgress || text.localizedCaseInsensitiveContains("CONFLICT") || text.localizedCaseInsensitiveContains("fix conflicts")
        present(action: "合并", outputs: [output], conflict: conflict)
    }

    func abortMerge() async {
        guard let cwd = repositoryURL, begin("正在中止合并（git merge --abort）…") else { return }
        defer { end() }
        let output = await GitClient.run(args: ["merge", "--abort"], cwd: cwd)
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "中止合并", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        showBanner("已中止合并")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func commit() async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = files.filter { checkedPaths.contains($0.path) }
        guard !message.isEmpty, !selected.isEmpty else { return }
        let finishingMerge = mergeInProgress
        guard let cwd = repositoryURL,
              begin(finishingMerge ? "正在完成合并（git add / commit）…" : "正在准备提交（git add）…") else { return }
        defer { end() }

        var outputs: [GitOutput] = []
        let uncheckedTracked = files.filter { !checkedPaths.contains($0.path) && $0.kind.isTracked }.map(\.path)
        if !uncheckedTracked.isEmpty {
            let restored = await GitClient.runBatched(
                base: ["restore", "--staged", "--"],
                paths: uncheckedTracked,
                cwd: cwd
            )
            outputs.append(contentsOf: restored)
            guard !cancelRequested else { return }
            if let failed = restored.last, failed.exitCode != 0 {
                present(action: "提交", outputs: outputs)
                await refresh(alertOnFailure: false)
                return
            }
        }

        let added = await GitClient.runBatched(base: ["add", "--"], paths: selected.map(\.path), cwd: cwd)
        outputs.append(contentsOf: added)
        guard !cancelRequested else { return }
        if let failed = added.last, failed.exitCode != 0 {
            present(action: "提交", outputs: outputs)
            await refresh(alertOnFailure: false)
            return
        }

        busyLabel = finishingMerge ? "正在完成合并（git commit）…" : "正在提交（git commit）…"
        let committed = await GitClient.run(args: ["commit", "-m", message], cwd: cwd)
        outputs.append(committed)
        guard !cancelRequested else { return }
        guard committed.exitCode == 0 else {
            present(action: "提交", outputs: outputs)
            await refresh(alertOnFailure: false)
            return
        }
        commitMessage = ""
        showBanner(finishingMerge ? "已完成合并" : "已提交")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func fetch() async {
        guard let cwd = repositoryURL, begin("正在检查远程（git remote）…") else { return }
        defer { end() }
        let remotes = await GitClient.run(args: ["remote"], cwd: cwd)
        guard !cancelRequested else { return }
        guard remotes.exitCode == 0 else {
            present(action: "获取", outputs: [remotes])
            return
        }
        if remotes.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            present(title: "获取失败", reason: "该仓库没有远程。", log: FailureLog.make(outputs: [remotes]))
            return
        }
        busyLabel = "正在获取（git fetch）…"
        let output = await GitClient.run(args: ["fetch", "--prune"], cwd: cwd, timeout: 120)
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "获取", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        showBanner("已获取")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func pull() async {
        guard let cwd = repositoryURL, begin("正在拉取（git pull）…") else { return }
        defer { end() }
        let output = await GitClient.run(args: ["pull"], cwd: cwd, timeout: 120)
        guard !cancelRequested else { return }
        let text = output.stdoutText + "\n" + output.stderrText
        if output.exitCode == 0 {
            if text.localizedCaseInsensitiveContains("Already up to date") {
                showBanner("已经是最新")
            } else {
                showBanner("已拉取")
            }
            await refresh(alertOnFailure: true, updateDivergence: true)
            return
        }
        await refresh(alertOnFailure: false, updateDivergence: true)
        let conflict = mergeInProgress || text.localizedCaseInsensitiveContains("CONFLICT") || text.localizedCaseInsensitiveContains("fix conflicts")
        present(action: "拉取", outputs: [output], conflict: conflict)
    }

    func push() async {
        guard let cwd = repositoryURL, begin("正在检查上游（git rev-parse）…") else { return }
        defer { end() }
        guard let branch = currentBranchName, !isDetached else {
            present(title: "推送失败", reason: "当前不在分支上，无法推送。", log: "未执行 git push。")
            return
        }
        let upstream = await GitClient.run(
            args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            cwd: cwd
        )
        guard !cancelRequested else { return }
        let output: GitOutput
        if upstream.exitCode == 0 {
            busyLabel = "正在推送（git push）…"
            output = await GitClient.run(args: ["push"], cwd: cwd, timeout: 120)
        } else {
            let remotes = await GitClient.run(args: ["remote"], cwd: cwd)
            guard !cancelRequested else { return }
            let names = remotes.stdoutText.split(separator: "\n").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard names.contains("origin") else {
                present(title: "推送失败", reason: "无法推送：没有名为 origin 的远程。", log: FailureLog.make(outputs: [remotes]))
                return
            }
            busyLabel = "正在推送并设置上游（git push -u）…"
            output = await GitClient.run(
                args: ["push", "-u", "origin", branch],
                cwd: cwd,
                timeout: 120
            )
        }
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "推送", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        showBanner("已推送")
        await refresh(alertOnFailure: true, updateDivergence: true)
    }

    func discard(_ file: FileChange) async {
        guard let cwd = repositoryURL, begin("正在放弃修改（git restore）…") else { return }
        defer { end() }
        if file.kind == .untracked {
            let url = cwd.appendingPathComponent(file.path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                present(title: "放弃修改失败", reason: "无法把文件移到废纸篓。", log: error.localizedDescription)
                return
            }
            showBanner("已移到废纸篓")
            await refresh(alertOnFailure: true)
            return
        }
        var paths = [file.path]
        if let oldPath = file.oldPath {
            paths.append(oldPath)
        }
        let output = await GitClient.run(
            args: ["restore", "--source=HEAD", "--worktree", "--staged", "--"] + paths,
            cwd: cwd
        )
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "放弃修改", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        showBanner("已放弃修改")
        await refresh(alertOnFailure: true)
    }

    func ignore(_ file: FileChange) {
        guard let cwd = repositoryURL else { return }
        do {
            try appendGitignore(repo: cwd, pattern: gitignorePattern(file.path))
        } catch {
            dialog = .plain(title: "忽略文件失败", message: error.localizedDescription)
            return
        }
        if file.kind.isTracked {
            dialog = .removeFromIndex(file)
        } else {
            showBanner("已写入 .gitignore")
        }
        Task { await refresh(alertOnFailure: false) }
    }

    func removeFromIndex(_ file: FileChange) async {
        guard let cwd = repositoryURL, begin("正在忽略文件（git rm --cached）…") else { return }
        defer { end() }
        let output = await GitClient.run(args: ["rm", "--cached", "--", file.path], cwd: cwd)
        guard !cancelRequested else { return }
        guard output.exitCode == 0 else {
            present(action: "忽略文件", outputs: [output])
            await refresh(alertOnFailure: false)
            return
        }
        showBanner("已从索引移除")
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
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil else {
            dialog = .vscodeMissing
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", "--", url.path]
        do {
            try process.run()
        } catch {
            dialog = .plain(title: "无法打开 VS Code", message: error.localizedDescription)
        }
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
        guard !isWorking else { return false }
        cancelRequested = false
        isRefreshing = true
        refreshLabel = "正在打开项目（git rev-parse）…"
        return true
    }

    private func endRepositoryLoad() {
        isRefreshing = false
        refreshLabel = ""
        cancelRequested = false
    }

    private func open(folder: URL, silentIfInvalid: Bool) async {
        let probe = await GitClient.run(args: ["rev-parse", "--show-toplevel"], cwd: folder)
        guard !cancelRequested else { return }
        let top = probe.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard probe.exitCode == 0, !top.isEmpty else {
            if !silentIfInvalid {
                dialog = .notRepository
            }
            return
        }
        if repositoryPath != top {
            generation += 1
            resetWorkspace()
        }
        repositoryPath = top
        RecentsStore.setLastRepository(top)
        recentRepositoryPaths = RecentsStore.recentRepositories()
        recentBranchNames = RecentsStore.recentBranches(for: top)
        refreshLabel = "正在刷新（git status / log）…"
        await refresh(alertOnFailure: !silentIfInvalid, updateDivergence: true)
    }

    private func refresh(alertOnFailure: Bool, updateDivergence: Bool = false) async {
        guard let cwd = repositoryURL else { return }
        let gen = generation
        if isRefreshing {
            refreshLabel = "正在读取状态和分支（git status / branch）…"
        }

        async let status = GitClient.run(args: ["status", "--porcelain=v1", "-z", "-uall"], cwd: cwd)
        async let showCurrent = GitClient.run(args: ["branch", "--show-current"], cwd: cwd)
        async let locals = GitClient.run(
            args: ["for-each-ref", "--format=%(HEAD)%09%(refname:short)", "refs/heads"],
            cwd: cwd
        )
        async let remotes = GitClient.run(
            args: ["for-each-ref", "--format=%(refname:short)", "refs/remotes"],
            cwd: cwd
        )
        async let head = GitClient.run(args: ["rev-parse", "--short=7", "HEAD"], cwd: cwd)
        async let mergeHead = GitClient.run(args: ["rev-parse", "-q", "--verify", "MERGE_HEAD"], cwd: cwd)

        let statusOut = await status
        let currentOut = await showCurrent
        let localOut = await locals
        let remoteOut = await remotes
        let headOut = await head
        let mergeOut = await mergeHead
        guard !cancelRequested else { return }
        guard gen == generation else { return }

        guard statusOut.exitCode == 0 else {
            if alertOnFailure {
                present(action: "刷新", outputs: [statusOut])
            } else {
                showBanner("刷新失败")
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
            recentBranchNames = RecentsStore.recentBranches(for: repositoryPath).filter { name in
                localBranchNames.contains(name) || name == current
            }
        }

        let previousBranch = currentBranchName
        let wasDetached = isDetached
        if !current.isEmpty {
            isDetached = false
            currentBranchName = current
            branchDisplayName = current
        } else if headOut.exitCode == 0 {
            let hash = headOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            isDetached = true
            currentBranchName = nil
            branchDisplayName = hash.isEmpty ? "分离头指针" : hash
        } else {
            isDetached = false
            currentBranchName = nil
            branchDisplayName = "尚无提交"
        }

        if updateDivergence {
            if isRefreshing {
                refreshLabel = "正在计算待推送和待拉取提交…"
            }
            await updateDivergenceCounts(cwd: cwd, generation: gen)
            guard !cancelRequested else { return }
        } else if currentBranchName != previousBranch || isDetached != wasDetached {
            unpushedCount = nil
            remoteAheadCount = nil
        }
        guard gen == generation else { return }

        let merging = mergeOut.exitCode == 0 && !mergeOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        mergeInProgress = merging
        mergeSource = merging ? await readMergeSource(cwd: cwd) : ""
        guard !cancelRequested else { return }
        guard gen == generation else { return }

        if isRefreshing {
            refreshLabel = "正在读取提交历史（git log）…"
        }
        await loadHistory(reset: true, alertOnFailure: false, generation: gen)
        guard !cancelRequested else { return }
        guard gen == generation else { return }
        if isRefreshing, selectedPath != nil || selectedHistoryPath != nil {
            refreshLabel = "正在加载文件差异（git diff）…"
        }
        await reloadVisibleDiff()
    }

    private func updateDivergenceCounts(cwd: URL, generation gen: Int) async {
        guard !isDetached, let currentBranchName else {
            unpushedCount = nil
            remoteAheadCount = nil
            return
        }

        let upstreamOutput = await GitClient.run(
            args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            cwd: cwd
        )
        guard !cancelRequested else { return }
        guard gen == generation else { return }

        let configuredUpstream = upstreamOutput.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            unpushedCount = nil
            remoteAheadCount = nil
            return
        }

        async let unpushedOutput = GitClient.run(
            args: ["rev-list", "--count", "\(comparisonRef)..HEAD"],
            cwd: cwd
        )
        async let remoteAheadOutput = GitClient.run(
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
              let remoteAhead = Int(remote.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
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
        let output = await GitClient.run(
            args: [
                "log", "-n", "100", "--skip", "\(skip)",
                "--pretty=format:%H%x1f%an%x1f%ae%x1f%at%x1f%s%x1e",
            ],
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
                present(action: "刷新", outputs: [output])
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
    }

    private func applyFiles(_ parsed: [FileChange]) {
        let paths = Set(parsed.map(\.path))
        let brandNew = paths.subtracting(seenPaths)
        var nextChecked = checkedPaths.intersection(paths)
        nextChecked.formUnion(brandNew)
        files = parsed
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
        if mode == .history, let hash = selectedHistoryHash, let path = selectedHistoryPath {
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
            output = await GitClient.run(
                args: ["diff", "--no-index", "--no-ext-diff", "--no-color", "--", "/dev/null", path],
                cwd: cwd
            )
            allowed = [0, 1]
        } else {
            output = await GitClient.run(
                args: ["diff", "--no-ext-diff", "--no-color", "HEAD", "--", path],
                cwd: cwd
            )
            allowed = [0]
            if output.exitCode != 0, output.stderrText.contains("bad revision"), file?.kind != .deleted {
                output = await GitClient.run(
                    args: ["diff", "--no-index", "--no-ext-diff", "--no-color", "--", "/dev/null", path],
                    cwd: cwd
                )
                allowed = [0, 1]
            }
        }
        guard !cancelRequested else { return }
        guard token == diffToken, selectedPath == path else { return }
        guard allowed.contains(output.exitCode) else {
            diff = .empty
            diffTitle = path
            present(action: "刷新", outputs: [output])
            return
        }
        diff = DiffParser.parse(output.stdoutText)
        diffTitle = path
    }

    private func loadHistoryDiff(hash: String, path: String) async {
        guard let cwd = repositoryURL else { return }
        diffToken += 1
        let token = diffToken
        let output = await GitClient.run(
            args: ["show", "--no-ext-diff", "--no-color", hash, "--", path],
            cwd: cwd
        )
        guard !cancelRequested else { return }
        guard token == diffToken, selectedHistoryHash == hash, selectedHistoryPath == path else { return }
        guard output.exitCode == 0 else {
            present(action: "刷新", outputs: [output])
            return
        }
        diff = DiffParser.parse(output.stdoutText)
        diffTitle = path
    }

    private func readMergeSource(cwd: URL) async -> String {
        let pathOut = await GitClient.run(args: ["rev-parse", "--git-path", "MERGE_MSG"], cwd: cwd)
        let relative = pathOut.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pathOut.exitCode == 0, !relative.isEmpty else { return "另一分支" }
        let url = relative.hasPrefix("/") ? URL(fileURLWithPath: relative) : cwd.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "另一分支" }
        let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        if let name = quotedName(in: first, prefix: "Merge branch '") { return name }
        if let name = quotedName(in: first, prefix: "Merge remote-tracking branch '") { return name }
        return "另一分支"
    }

    private func presentAfterDelay(_ body: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            body()
        }
    }

    private func startRefresh(
        label: String,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard !isWorking else { return }
        cancelRequested = false
        isRefreshing = true
        refreshLabel = label
        Task {
            defer {
                isRefreshing = false
                refreshLabel = ""
                cancelRequested = false
            }
            await operation()
        }
    }

    private func begin(_ label: String) -> Bool {
        guard !isWorking else { return false }
        cancelRequested = false
        isBusy = true
        busyLabel = label
        generation += 1
        return true
    }

    private func end() {
        isBusy = false
        busyLabel = ""
        cancelRequested = false
    }

    private func showBanner(_ text: String) {
        banner = text
        bannerToken += 1
        let token = bannerToken
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard bannerToken == token else { return }
            banner = nil
        }
    }

    private func present(action: String, outputs: [GitOutput], conflict: Bool = false) {
        present(
            title: "\(action)失败",
            reason: FailureLog.reason(action: action, outputs: outputs, conflict: conflict),
            log: FailureLog.make(outputs: outputs)
        )
    }

    private func present(title: String, reason: String, log: String) {
        failure = FailureReport(title: title, reason: reason, log: FailureLog.truncate(log))
    }

    private func resetWorkspace() {
        files = []
        checkedPaths = []
        seenPaths = []
        selectedPath = nil
        commits = []
        canLoadMoreHistory = false
        expandedCommit = nil
        commitFiles = [:]
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
        unpushedCount = nil
        remoteAheadCount = nil
        isDetached = false
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
