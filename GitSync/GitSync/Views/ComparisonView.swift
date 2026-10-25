import SwiftUI

struct ComparisonView: View {
  let request: ComparisonRequest
  @Environment(\.projectTheme) private var theme
  @State private var git = WindowGitClient()
  @State private var diffModel = AppModel()
  @State private var files: [CommitFile] = []
  @State private var selectedPath: String?
  @State private var loadingFiles = true
  @State private var loadingDiff = false
  @State private var listError: String?
  @State private var diffError: String?

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 12) {
          revision(request.baseLabel, hash: request.baseHash)
          Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
          revision(request.headLabel, hash: request.headHash)
          Spacer(minLength: 0)
        }
        Text(request.repositoryPath)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(request.repositoryPath)
      }
      .padding(12)
      .background(theme.headerBackground)
      Divider()
      if loadingFiles {
        ProgressView(L10n.text("正在读取修改文件…", "Loading changed files…"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let listError {
        errorView(listError) { Task { await loadFiles() } }
      } else if files.isEmpty {
        ContentUnavailableView(L10n.text("没有差异", "No differences"), systemImage: "checkmark.circle")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HSplitView {
          VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("\(files.count) 个修改文件", "\(files.count) changed files"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(10)
            Divider()
            List(selection: $selectedPath) {
              ForEach(files) { file in
                HStack(spacing: 8) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                      .font(.system(.callout, design: .monospaced))
                      .lineLimit(2)
                      .truncationMode(.middle)
                    if let oldPath = file.oldPath {
                      Text(oldPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                  }
                  Spacer(minLength: 4)
                  Text(file.label)
                    .font(.caption)
                    .foregroundStyle(statusColor(file))
                }
                .padding(.vertical, 3)
                .tag(file.path)
                .help(file.path)
              }
            }
            .listStyle(.plain)
          }
          .frame(minWidth: 220, idealWidth: 290, maxWidth: 440)
          Group {
            if let diffError {
              errorView(diffError) { Task { await loadDiff() } }
            } else {
              DiffView(model: diffModel, comparison: true, comparisonRequest: request)
                .overlay {
                  if loadingDiff {
                    ProgressView()
                      .padding(16)
                      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                  }
                }
            }
          }
          .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(
      minWidth: 850, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity,
      alignment: .topLeading
    )
    .navigationTitle(L10n.text("差异对比", "Compare Changes"))
    .task { await loadFiles() }
    .task(id: selectedPath) { await loadDiff() }
    .onDisappear { git.cancel() }
  }

  private func statusColor(_ file: CommitFile) -> Color {
    switch file.labelText.chinese {
    case "新增": .green
    case "删除", "冲突": .red
    case "重命名", "复制": .blue
    default: .orange
    }
  }

  private func revision(_ label: String, hash: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(label)
      Text(String(hash.prefix(7)))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .help(hash)
    }
  }

  private func errorView(_ message: String, retry: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
      Text(message)
        .font(.callout)
        .textSelection(.enabled)
      Button(L10n.text("重试", "Retry"), action: retry)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadFiles() async {
    loadingFiles = true
    listError = nil
    do {
      let result = try await git.performCancellable { try await GitComparison.files(request) }
      guard !Task.isCancelled else { return }
      files = result
      selectedPath = result.first?.path
    } catch {
      guard !Task.isCancelled else { return }
      listError = error.localizedDescription
    }
    loadingFiles = false
  }

  private func loadDiff() async {
    diffError = nil
    diffModel.diff = .empty
    diffModel.diffTitle = ""
    guard let path = selectedPath, let file = files.first(where: { $0.path == path }) else {
      loadingDiff = false
      return
    }
    loadingDiff = true
    do {
      let document = try await git.performCancellable {
        try await GitComparison.diff(request, file: file)
      }
      guard !Task.isCancelled, selectedPath == path else { return }
      diffModel.diff = document
      diffModel.diffTitle = path
    } catch {
      guard !Task.isCancelled, selectedPath == path else { return }
      diffError = error.localizedDescription
    }
    loadingDiff = false
  }
}

struct CompareBranchSheet: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openWindow) private var openWindow
  @State private var query = ""
  @State private var selection: BranchItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("分支对比", "Compare Branches"))
        .font(.headline)
      Text(model.localizedBranchDisplayName)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      TextField(L10n.text("搜索分支", "Search branches"), text: $query)
        .textFieldStyle(.roundedBorder)
      List(selection: $selection) {
        branchSection(L10n.text("本地", "Local"), names: model.localBranchNames, remote: false)
        branchSection(L10n.text("远程", "Remote"), names: model.remoteBranchNames, remote: true)
      }
      .disabled(model.isWorking)
      HStack {
        if model.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button(L10n.text("取消", "Cancel")) { dismiss() }
          .disabled(model.isWorking)
        Button(L10n.text("对比", "Compare")) {
          guard let selection else { return }
          let reference = (selection.isRemote ? "refs/remotes/" : "refs/heads/") + selection.name
          Task {
            if let request = await model.prepareComparison(
              reference: reference, label: selection.name)
            {
              dismiss()
              openWindow(value: request)
            }
          }
        }
        .disabled(selection == nil || model.isWorking)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 440, height: 500)
    .interactiveDismissDisabled(model.isWorking)
  }

  @ViewBuilder
  private func branchSection(_ title: String, names: [String], remote: Bool) -> some View {
    let filtered = names.filter {
      (remote || $0 != model.currentBranchName)
        && (query.isEmpty || $0.localizedCaseInsensitiveContains(query))
    }
    if !filtered.isEmpty {
      Section(title) {
        ForEach(filtered, id: \.self) { name in
          Label(name, systemImage: remote ? "network" : "arrow.triangle.branch")
            .lineLimit(1)
            .truncationMode(.middle)
            .tag(BranchItem(name: name, isRemote: remote))
            .help(name)
        }
      }
    }
  }
}
