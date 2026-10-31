import SwiftUI

struct MergePreviewView: View {
  let request: MergePreviewRequest
  @Environment(\.projectTheme) private var theme
  @State private var catalogGit = WindowGitClient()
  @State private var checkGit = WindowGitClient()
  @State private var detailGit = WindowGitClient()
  @State private var diffModel = AppModel()
  @State private var branches: [MergePreviewBranch] = []
  @State private var baseReference = ""
  @State private var showingBasePicker = false
  @State private var reloadToken = 0
  @State private var checkToken = 0
  @State private var loadingBranches = true
  @State private var checking = false
  @State private var result: MergePreviewResult?
  @State private var files: [CommitFile] = []
  @State private var selectedPath: String?
  @State private var conflictsOnly = false
  @State private var mode: PreviewMode = .head
  @State private var loadingDetail = false
  @State private var mergedText = ""
  @State private var error: String?
  @State private var detailError: String?

  private enum PreviewMode: String, CaseIterable {
    case head, base, merged

    var title: String {
      switch self {
      case .head: L10n.text("比较分支改动", "Compare Branch Changes")
      case .base: L10n.text("Base 改动", "Base Changes")
      case .merged: L10n.text("合并预览", "Merge Preview")
      }
    }
  }

  private var repository: URL { URL(fileURLWithPath: request.repositoryPath, isDirectory: true) }
  private var baseBranch: MergePreviewBranch? { branches.first { $0.reference == baseReference } }
  private var conflictPaths: Set<String> { Set(result?.conflictPaths ?? []) }
  private var visibleFiles: [CommitFile] {
    conflictsOnly ? files.filter { conflictPaths.contains($0.path) } : files
  }
  private var checkIdentity: String { "\(baseReference):\(checkToken)" }
  private var detailIdentity: String {
    "\(result?.baseHash ?? ""):\(result?.headHash ?? ""):\(selectedPath ?? ""):\(mode.rawValue)"
  }
  private var comparison: ComparisonRequest? {
    guard let result else { return nil }
    return ComparisonRequest(
      repositoryPath: request.repositoryPath, baseHash: result.mergeBaseHash,
      headHash: mode == .base ? result.baseHash : result.headHash,
      baseLabel: L10n.text("共同祖先", "Common Ancestor"),
      headLabel: mode == .base ? (baseBranch?.name ?? "Base") : request.headBranch)
  }

  var body: some View {
    VStack(spacing: 0) {
      branchHeader
      Divider()
      content
    }
    .frame(minWidth: 950, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    .navigationTitle(L10n.text("PR 冲突检查", "PR Conflict Check"))
    .navigationSubtitle(repository.lastPathComponent)
    .task(id: reloadToken) { await loadBranches() }
    .task(id: checkIdentity) { await check() }
    .task(id: detailIdentity) { await loadDetail() }
    .onChange(of: conflictsOnly) { _, _ in
      if !visibleFiles.contains(where: { $0.path == selectedPath }) {
        selectedPath = visibleFiles.first?.path
      }
    }
    .onDisappear {
      catalogGit.cancel()
      checkGit.cancel()
      detailGit.cancel()
    }
  }

  private var branchHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Base").font(.caption).foregroundStyle(.secondary)
          HStack(spacing: 6) {
            Button {
              showingBasePicker.toggle()
            } label: {
              HStack(spacing: 6) {
                Image(
                  systemName: baseBranch?.isRemote == true ? "network" : "arrow.triangle.branch")
                Text(baseBranch?.name ?? L10n.text("选择分支", "Select Branch"))
                  .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption)
              }
            }
            .disabled(loadingBranches || branches.isEmpty)
            .popover(isPresented: $showingBasePicker) {
              MergeBasePicker(branches: branches, selection: baseReference) { branch in
                baseReference = branch.reference
                showingBasePicker = false
              }
            }
            if let baseBranch {
              MergeBranchCopyButton(name: baseBranch.name)
            }
          }
          if let result { hashLabel(result.baseHash) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "arrow.left").foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.text("比较分支", "Compare Branch")).font(.caption).foregroundStyle(.secondary)
          HStack(spacing: 6) {
            Label(request.headBranch, systemImage: "arrow.triangle.branch")
              .font(.headline).lineLimit(1).truncationMode(.middle).help(request.headBranch)
            MergeBranchCopyButton(name: request.headBranch)
          }
          if let result { hashLabel(result.headHash) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          reloadToken += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help(L10n.text("重新检查", "Check Again"))
        .accessibilityLabel(L10n.text("重新检查", "Check Again"))
        .disabled(loadingBranches || checking)
      }
      HStack {
        Text(request.repositoryPath).lineLimit(1).truncationMode(.middle).help(
          request.repositoryPath)
        Spacer()
        Text(L10n.text("本地引用快照 · 不含未提交修改", "Local ref snapshot · Uncommitted changes excluded"))
      }
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(12)
    .background(theme.headerBackground)
  }

  @ViewBuilder
  private var content: some View {
    if loadingBranches || checking {
      ProgressView(L10n.text("正在检查合并冲突…", "Checking merge conflicts…"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error {
      messageView(error, retry: true)
    } else if branches.isEmpty {
      ContentUnavailableView(
        L10n.text("没有可比较的 Base 分支", "No Base Branch Available"),
        systemImage: "arrow.triangle.branch")
    } else if let result {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Label(
            result.hasConflicts
              ? L10n.text(
                "\(result.conflictPaths.count) 个文件存在合并冲突",
                "\(result.conflictPaths.count) files have merge conflicts")
              : L10n.text("无合并冲突", "No Merge Conflicts"),
            systemImage: result.hasConflicts
              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
          )
          .foregroundStyle(result.hasConflicts ? Color.orange : Color.green)
          Spacer()
          Text(L10n.text("\(files.count) 个文件", "\(files.count) files")).foregroundStyle(.secondary)
          Toggle(L10n.text("仅冲突", "Conflicts Only"), isOn: $conflictsOnly)
            .toggleStyle(.switch).controlSize(.small).fixedSize()
            .disabled(!result.hasConflicts)
        }
        .padding(12)
        Divider()
        if files.isEmpty {
          ContentUnavailableView(
            L10n.text("比较分支没有新增改动", "No New Changes on Compare Branch"),
            systemImage: "checkmark.circle"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HSplitView {
            fileList
            fileDetail
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    } else {
      ContentUnavailableView(
        L10n.text("请选择 Base 分支", "Select a Base Branch"), systemImage: "arrow.triangle.branch")
    }
  }

  private var fileList: some View {
    List(selection: $selectedPath) {
      ForEach(visibleFiles, id: \.path) { file in
        HStack(spacing: 8) {
          Image(
            systemName: conflictPaths.contains(file.path)
              ? "exclamationmark.triangle.fill" : "doc.text"
          )
          .foregroundStyle(statusColor(file))
          VStack(alignment: .leading, spacing: 3) {
            Text(file.path).font(.system(.callout, design: .monospaced))
              .lineLimit(2).truncationMode(.middle)
            Text(conflictPaths.contains(file.path) ? L10n.text("冲突", "Conflict") : file.label)
              .font(.caption).foregroundStyle(statusColor(file))
          }
        }
        .padding(.vertical, 3).tag(file.path).help(file.path)
      }
    }
    .listStyle(.plain)
    .frame(minWidth: 210, idealWidth: 280, maxWidth: 400)
  }

  private var fileDetail: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Picker(L10n.text("内容", "Content"), selection: $mode) {
          ForEach(PreviewMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 510)
        Spacer(minLength: 0)
        Button {
          guard let selectedPath else { return }
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(selectedPath, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .help(L10n.text("复制文件路径", "Copy File Path"))
        .accessibilityLabel(L10n.text("复制文件路径", "Copy File Path"))
        .disabled(selectedPath == nil)
      }
      .padding(10)
      Divider()
      Group {
        if selectedPath == nil {
          ContentUnavailableView(
            L10n.text("选择一个文件", "Select a File"), systemImage: "doc.text.magnifyingglass")
        } else if loadingDetail {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detailError {
          messageView(detailError)
        } else if mode == .merged {
          SelectableSourceView(text: mergedText, identity: detailIdentity)
        } else {
          DiffView(model: diffModel, comparison: true, comparisonRequest: comparison)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
  }

  private func statusColor(_ file: CommitFile) -> Color {
    if conflictPaths.contains(file.path) { return .red }
    switch file.labelText.chinese {
    case "新增": return .green
    case "删除", "冲突": return .red
    case "修改": return .orange
    case "重命名", "复制": return .blue
    default: return .secondary
    }
  }

  private func hashLabel(_ hash: String) -> some View {
    Text(String(hash.prefix(7))).font(.system(.caption, design: .monospaced))
      .foregroundStyle(.secondary).textSelection(.enabled).help(hash)
  }

  private func messageView(_ message: String, retry: Bool = false) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Label(L10n.text("无法显示结果", "Unable to Show Result"), systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        Text(message).font(.callout).textSelection(.enabled)
        if retry {
          Button {
            reloadToken += 1
          } label: {
            Label(L10n.text("重试", "Retry"), systemImage: "arrow.clockwise")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadBranches() async {
    loadingBranches = true
    error = nil
    do {
      let loaded = try await catalogGit.performCancellable {
        try await GitMergePreview.branches(repository: repository, headBranch: request.headBranch)
      }
      guard !Task.isCancelled else { return }
      branches = loaded.branches
      if !branches.contains(where: { $0.reference == baseReference }) {
        baseReference = loaded.defaultReference ?? ""
      }
      checkToken += 1
    } catch {
      guard !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
    loadingBranches = false
  }

  private func check() async {
    let identity = checkIdentity
    result = nil
    files = []
    selectedPath = nil
    guard !baseReference.isEmpty else {
      checking = false
      return
    }
    checking = true
    error = nil
    do {
      let base = baseReference
      let (checked, changed) = try await checkGit.performCancellable {
        let checked = try await GitMergePreview.check(
          repository: repository, base: base, headBranch: request.headBranch)
        let comparison = ComparisonRequest(
          repositoryPath: request.repositoryPath, baseHash: checked.mergeBaseHash,
          headHash: checked.headHash,
          baseLabel: "", headLabel: "")
        let changed = try await GitComparison.files(comparison)
        return (checked, changed)
      }
      guard !Task.isCancelled, identity == checkIdentity else { return }
      let conflicts = Set(checked.conflictPaths)
      let changedPaths = Set(changed.map(\.path))
      let extra = checked.conflictPaths.filter { !changedPaths.contains($0) }.map {
        CommitFile(label: L10n.message("冲突", "Conflict"), path: $0, oldPath: nil)
      }
      files = (changed + extra).sorted {
        if conflicts.contains($0.path) != conflicts.contains($1.path) {
          return conflicts.contains($0.path)
        }
        return $0.path < $1.path
      }
      result = checked
      if !checked.hasConflicts { conflictsOnly = false }
      selectedPath = visibleFiles.first?.path
      mode = checked.hasConflicts ? .merged : .head
    } catch {
      guard !Task.isCancelled, identity == checkIdentity else { return }
      self.error = error.localizedDescription
    }
    checking = false
  }

  private func loadDetail() async {
    let identity = detailIdentity
    detailError = nil
    mergedText = ""
    diffModel.diff = .empty
    diffModel.diffTitle = ""
    guard let result, let path = selectedPath, let file = files.first(where: { $0.path == path })
    else {
      loadingDetail = false
      return
    }
    loadingDetail = true
    do {
      if mode == .merged {
        let text = try await detailGit.performCancellable {
          try await GitMergePreview.mergedFile(repository: repository, result: result, path: path)
        }
        guard !Task.isCancelled, identity == detailIdentity else { return }
        mergedText = text
      } else if let comparison {
        let document = try await detailGit.performCancellable {
          try await GitComparison.diff(comparison, file: file)
        }
        guard !Task.isCancelled, identity == detailIdentity else { return }
        diffModel.diff = document
        diffModel.diffTitle = path
      }
    } catch {
      guard !Task.isCancelled, identity == detailIdentity else { return }
      detailError = error.localizedDescription
    }
    loadingDetail = false
  }
}

private struct MergeBranchCopyButton: View {
  let name: String
  @State private var copyID: UUID?

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setString(name, forType: .string) {
        copyID = UUID()
      }
    } label: {
      Image(systemName: copyID == nil ? "doc.on.doc" : "checkmark")
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.borderless)
    .fixedSize()
    .help(copyID == nil ? L10n.text("复制分支名", "Copy Branch Name") : L10n.text("已复制", "Copied"))
    .accessibilityLabel(L10n.text("复制分支名", "Copy Branch Name"))
    .task(id: copyID) {
      guard copyID != nil else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copyID = nil
    }
    .onChange(of: name) { copyID = nil }
  }
}

private struct MergeBasePicker: View {
  let branches: [MergePreviewBranch]
  let selection: String
  let select: (MergePreviewBranch) -> Void
  @State private var query = ""
  @State private var filtered: [MergePreviewBranch] = []

  private struct Filter: Equatable, Sendable {
    let branches: [MergePreviewBranch]
    let query: String
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField(L10n.text("搜索 Base 分支", "Search Base Branches"), text: $query)
        .textFieldStyle(.roundedBorder).padding(10)
      Divider()
      List {
        section(L10n.text("本地", "Local"), remote: false)
        section(L10n.text("远程", "Remote"), remote: true)
      }
      .listStyle(.plain)
    }
    .frame(width: 380, height: 420)
    .task(id: Filter(branches: branches, query: query)) {
      let snapshot = Filter(branches: branches, query: query)
      let matches = await Task.detached(priority: .userInitiated) {
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.branches.filter {
          query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
      }.value
      guard !Task.isCancelled else { return }
      filtered = matches
    }
  }

  private func section(_ title: String, remote: Bool) -> some View {
    Section(title) {
      ForEach(filtered.filter { $0.isRemote == remote }) { branch in
        Button {
          select(branch)
        } label: {
          HStack {
            Label(branch.name, systemImage: remote ? "network" : "arrow.triangle.branch")
              .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if selection == branch.reference { Image(systemName: "checkmark") }
          }
          .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(
            Rectangle())
        }
        .buttonStyle(.plain).help(branch.name)
      }
    }
  }
}
