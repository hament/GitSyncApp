import AppKit
import SwiftUI

struct MainView: View {
  @Bindable var model: AppModel
  var restoreLastRepository = true
  var restoreRepositoryPath: String?

  var body: some View {
    Group {
      if model.repositoryPath == nil {
        emptyState
      } else {
        workspace
      }
    }
    .frame(
      minWidth: 1000, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity,
      alignment: .topLeading
    )
    .navigationTitle(model.windowTitle)
    .background(WindowAutosave(model: model))
    .task {
      if let restoreRepositoryPath, model.repositoryPath == nil {
        model.openRecentRepository(restoreRepositoryPath)
      } else if restoreLastRepository {
        await model.restoreLastIfNeeded()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      model.refreshIfIdle()
    }
    .sheet(item: $model.failure) { report in
      FailureSheet(report: report) { model.failure = nil }
        .projectTheme(model.projectTheme)
    }
    .sheet(isPresented: $model.showNewBranch) {
      NewBranchSheet(model: model)
        .projectTheme(model.projectTheme)
    }
    .sheet(isPresented: $model.showClone) {
      CloneSheet(model: model)
        .projectTheme(model.projectTheme)
    }
    .sheet(isPresented: $model.showMerge) {
      MergeSheet(model: model)
        .projectTheme(model.projectTheme)
    }
    .sheet(isPresented: $model.showBranchComparison) {
      CompareBranchSheet(model: model)
        .projectTheme(model.projectTheme)
    }
    .sheet(item: $model.tagTarget) { target in
      NewTagSheet(model: model, target: target)
        .projectTheme(model.projectTheme)
    }
    .sheet(item: $model.tagToPush) { tag in
      PushTagSheet(model: model, tag: tag)
        .projectTheme(model.projectTheme)
    }
    .alert(dialogTitle, isPresented: dialogPresented) {
      dialogButtons
    } message: {
      Text(dialogMessage)
    }
  }

  private var workspace: some View {
    VStack(spacing: 0) {
      ToolbarView(model: model)
      if model.mergeInProgress {
        mergeBanner
      }
      Divider()
      HSplitView {
        sidebar
          .frame(
            minWidth: model.mode != .changes ? 230 : 280,
            idealWidth: model.mode != .changes ? 270 : 340,
            maxWidth: model.mode != .changes ? 380 : 520
          )
        if model.mode != .changes {
          VStack(spacing: 0) {
            if model.mode == .tags, let tag = model.selectedTag {
              TagDetailsHeader(tag: tag)
              Divider()
            }
            CommitFilesView(model: model)
          }
          .frame(minWidth: 250, idealWidth: 310, maxWidth: 460)
        }
        DiffView(model: model)
          .frame(minWidth: 420)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      Picker(
        L10n.text("列表", "List"),
        selection: Binding(
          get: { model.mode },
          set: { model.setMode($0) }
        )
      ) {
        Text(L10n.text("变更", "Changes")).tag(SidebarMode.changes)
        Text(L10n.text("历史", "History")).tag(SidebarMode.history)
        Text("Tags").tag(SidebarMode.tags)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(10)

      if model.mode == .changes {
        ChangesList(model: model)
          .frame(maxHeight: .infinity)
        Divider()
        CommitBar(model: model)
      } else if model.mode == .tags {
        TagsView(model: model)
      } else {
        HistoryList(model: model)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var mergeBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "arrow.triangle.merge")
      let source =
        model.mergeSource.isEmpty ? L10n.text("另一分支", "another branch") : model.mergeSource
      Text(L10n.text("正在合并 \(source)", "Merging \(source)"))
      Spacer()
      Button(L10n.text("中止合并", "Abort Merge")) {
        model.dialog = .abortMerge
      }
      .disabled(model.isWorking)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.16))
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "folder.badge.gearshape")
        .font(.system(size: 42))
        .foregroundStyle(.secondary)
      Text(L10n.text("选择一个本地 Git 仓库", "Choose a Local Git Repository"))
        .font(.title3)
      Text(
        L10n.text(
          "打开文件夹后，可以查看分支、变更和提交历史。", "Open a folder to view branches, changes, and commit history.")
      )
      .foregroundStyle(.secondary)
      if model.isRefreshing {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(model.refreshLabel.localized)
            .foregroundStyle(.secondary)
          Button(L10n.text("取消", "Cancel")) {
            model.cancelCurrentOperation()
          }
          .buttonStyle(.borderless)
        }
      } else {
        HStack(spacing: 12) {
          ProjectMenu(model: model)
          CloneButton(model: model)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .topTrailing) {
      SettingsButton(model: model)
        .padding(12)
    }
  }

  private var dialogPresented: Binding<Bool> {
    Binding(
      get: { model.dialog != nil },
      set: { if !$0 { model.dialog = nil } }
    )
  }

  private var dialogTitle: String {
    switch model.dialog {
    case .discard: L10n.text("放弃修改", "Discard Changes")
    case .discardFiles: L10n.text("放弃所选修改", "Discard Selected Changes")
    case .removePathsFromIndex: L10n.text("忽略已跟踪项目", "Ignore Tracked Items")
    case .removeFromIndex: L10n.text("忽略已跟踪文件", "Ignore Tracked File")
    case .removeFolderFromIndex: L10n.text("忽略已跟踪文件夹", "Ignore Tracked Folder")
    case .merge: L10n.text("合并分支", "Merge Branch")
    case .deleteBranch: L10n.text("删除本地分支", "Delete Local Branch")
    case .deleteTag: L10n.text("删除本地 Tag", "Delete Local Tag")
    case .abortMerge: L10n.text("中止合并", "Abort Merge")
    case .notRepository: L10n.text("无法打开", "Cannot Open")
    case .vscodeMissing: L10n.text("未找到 VS Code", "VS Code Not Found")
    case .plain(let title, _): title.localized
    case nil: ""
    }
  }

  private var dialogMessage: String {
    switch model.dialog {
    case .deleteTag(let tag):
      return L10n.text(
        "删除本地 Tag「\(tag.name)」？不会删除提交、文件或远程 Tag。",
        "Delete local tag \"\(tag.name)\"? Commits, files, and remote tags will not be deleted.")
    case .deleteBranch(let name):
      return L10n.text(
        "确定删除本地分支「\(name)」？即使有未合并的提交也会删除，该分支独有的未推送提交可能丢失。工作区文件和远程分支不会被删除。",
        "Delete local branch \"\(name)\"? It will be deleted even if it has unmerged commits, and unpushed commits unique to this branch may be lost. Working files and remote branches will not be deleted."
      )
    case .discardFiles(let files):
      return L10n.text(
        "放弃以下 \(files.count) 个文件的修改？未跟踪文件将移到废纸篓，冲突文件会丢失两边修改，其他文件将恢复到 HEAD。此操作不能撤销。\n\n",
        "Discard changes to these \(files.count) files? Untracked files will move to Trash, conflicts will lose both sides, and other files will revert to HEAD. This cannot be undone.\n\n"
      ) + files.map(\.path).joined(separator: "\n")
    case .removePathsFromIndex(let paths, let folders):
      return L10n.text(
        "已写入 .gitignore。是否将以下项目\(folders ? "内的所有文件" : "")从索引中移除？本地文件将保留。\n\n",
        "Added to .gitignore. Remove the following items\(folders ? " and all files inside them" : "") from the index? Local files will be kept.\n\n"
      ) + paths.joined(separator: "\n")
    case .discard(let file):
      if file.kind == .untracked {
        return L10n.text("将把「\(file.path)」移到废纸篓。", "Move \"\(file.path)\" to the Trash?")
      }
      if file.kind == .conflict {
        return L10n.text(
          "放弃「\(file.path)」的修改会丢掉冲突中的两边内容。",
          "Discarding changes to \"\(file.path)\" will lose both sides of the conflict.")
      }
      return L10n.text(
        "放弃「\(file.path)」的修改？此操作不能撤销。",
        "Discard changes to \"\(file.path)\"? This cannot be undone.")
    case .removeFromIndex(let file):
      return L10n.text(
        "「\(file.path)」已被 Git 跟踪。已写入 .gitignore，但在从索引移除前仍会显示为变更。是否从索引中移除并保留工作区文件？",
        "\"\(file.path)\" is tracked by Git. It was added to .gitignore but will still appear as changed until removed from the index. Remove it from the index and keep the working file?"
      )
    case .removeFolderFromIndex(let path):
      return L10n.text(
        "「\(path)」内包含已跟踪文件。已写入 .gitignore，是否将此文件夹内的所有文件从索引中移除并保留本地文件？",
        "\"\(path)\" contains tracked files. It was added to .gitignore. Remove all files in this folder from the index and keep the local files?"
      )
    case .merge(let source):
      let target = model.localizedBranchDisplayName
      return L10n.text("将把「\(source)」合并到「\(target)」。", "Merge \"\(source)\" into \"\(target)\"?")
    case .abortMerge:
      return L10n.text(
        "中止合并会丢弃这次合并中的改动，工作区回到合并前。",
        "Aborting will discard changes from this merge and restore the working tree to its previous state."
      )
    case .notRepository:
      return L10n.text("这不是 Git 仓库。", "This is not a Git repository.")
    case .vscodeMissing:
      return L10n.text("未找到 Visual Studio Code。", "Visual Studio Code was not found.")
    case .plain(_, let message):
      return message.localized
    case nil:
      return ""
    }
  }

  @ViewBuilder
  private var dialogButtons: some View {
    switch model.dialog {
    case .deleteTag(let tag):
      Button(L10n.text("删除本地 Tag", "Delete Local Tag"), role: .destructive) {
        Task { await model.deleteTag(tag) }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .deleteBranch(let name):
      Button(L10n.text("删除分支", "Delete Branch"), role: .destructive) {
        Task { await model.deleteBranch(name) }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .discardFiles(let files):
      Button(L10n.text("放弃修改", "Discard Changes"), role: .destructive) {
        Task { await model.discard(files: files) }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .removePathsFromIndex(let paths, let folders):
      Button(L10n.text("移除索引并保留文件", "Untrack and Keep Files")) {
        Task { await model.removeFromIndex(paths: paths, isDirectory: folders) }
      }
      Button(L10n.text("仅保留 .gitignore", "Keep .gitignore Only"), role: .cancel) {}
    case .discard(let file):
      Button(L10n.text("放弃修改", "Discard Changes"), role: .destructive) {
        Task { await model.discard(file) }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .removeFromIndex(let file):
      Button(L10n.text("移除索引并保留文件", "Untrack and Keep File")) {
        Task { await model.removeFromIndex(file) }
      }
      Button(L10n.text("仅保留 .gitignore", "Keep .gitignore Only"), role: .cancel) {}
    case .removeFolderFromIndex(let path):
      Button(L10n.text("移除索引并保留文件", "Untrack and Keep Files")) {
        Task { await model.removeFromIndex(path: path, isDirectory: true) }
      }
      Button(L10n.text("仅保留 .gitignore", "Keep .gitignore Only"), role: .cancel) {}
    case .merge(let source):
      Button(L10n.text("合并", "Merge")) {
        Task { await model.merge(source: source) }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .abortMerge:
      Button(L10n.text("中止合并", "Abort Merge"), role: .destructive) {
        Task { await model.abortMerge() }
      }
      Button(L10n.text("取消", "Cancel"), role: .cancel) {}
    case .notRepository, .vscodeMissing, .plain, nil:
      Button(L10n.text("好", "OK")) {}
    }
  }
}

private struct WindowAutosave: NSViewRepresentable {
  let model: AppModel

  func makeNSView(context: Context) -> NSView {
    ProjectWindowObserver(model: model)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    (nsView as? ProjectWindowObserver)?.configureWindow()
  }
}

private final class ProjectWindowObserver: NSView {
  let model: AppModel
  private var closeObserver: NSObjectProtocol?

  init(model: AppModel) {
    self.model = model
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureWindow()
  }

  func configureWindow() {
    guard let window else { return }
    let name = "GitSyncProject-" + model.windowID.uuidString
    if window.frameAutosaveName != name {
      window.setFrameAutosaveName(name)
    }
    ProjectWindows.shared.register(window, owner: model.windowID)
    if closeObserver == nil {
      let model = model
      closeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification, object: window, queue: .main
      ) { _ in
        MainActor.assumeIsolated { model.closeWindow() }
      }
    }
  }

  deinit {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
  }
}
