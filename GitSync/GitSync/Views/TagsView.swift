import SwiftUI

struct TagsView: View {
  var model: AppModel
  @Environment(\.openWindow) private var openWindow
  @State private var query = ""

  private var filtered: [TagRecord] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return model.tags.filter { value.isEmpty || $0.name.localizedCaseInsensitiveContains(value) }
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField(L10n.text("搜索 Tag", "Search tags"), text: $query)
        .textFieldStyle(.roundedBorder)
        .padding(10)
      HStack {
        Text(L10n.text("本地 Tags", "Local Tags"))
        Spacer()
        Text("\(filtered.count)")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      if let error = model.tagListError {
        VStack(spacing: 8) {
          Text(error).font(.caption).textSelection(.enabled)
          Button(L10n.text("重试", "Retry")) { model.refreshNow() }
            .disabled(model.isWorking)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filtered.isEmpty {
        ContentUnavailableView(
          model.tags.isEmpty
            ? L10n.text("暂无 Tag", "No Tags") : L10n.text("没有匹配的 Tag", "No Matching Tags"),
          systemImage: "tag"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(filtered) { tag in
              tagRow(tag)
            }
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func tagRow(_ tag: TagRecord) -> some View {
    Button {
      Task { await model.selectTag(tag) }
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        Label(tag.name, systemImage: "tag.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.blue)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(tag.summary)
          .font(.callout)
          .lineLimit(2)
        HStack {
          Text(String(tag.commitHash.prefix(7)))
            .font(.system(.caption, design: .monospaced))
          Spacer()
          Text(tag.date, format: .dateTime.year().month().day())
            .font(.caption)
        }
        .foregroundStyle(.secondary)
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(
        model.selectedTagName == tag.name ? Color.accentColor.opacity(0.16) : Color.clear,
        in: RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .disabled(model.isWorking)
    .help(tag.name)
    .contextMenu {
      Button(L10n.text("与当前分支对比", "Compare with Current Branch")) {
        Task {
          if let request = await model.prepareComparison(reference: tag.commitHash, label: tag.name)
          {
            openWindow(
              value: ComparisonRequest(
                repositoryPath: request.repositoryPath, baseHash: request.baseHash,
                headHash: request.headHash, baseLabel: request.baseLabel, headLabel: tag.name
              ))
          }
        }
      }
      .disabled(model.isWorking)
      Button(L10n.text("从此创建分支…", "Create Branch from Tag…")) {
        model.presentNewBranch(startCommit: tag.commitHash)
      }
      .disabled(model.isWorking)
      Button(L10n.text("推送 Tag…", "Push Tag…")) { model.tagToPush = tag }
        .disabled(model.isWorking)
      Divider()
      Button(L10n.text("复制 Tag 名称", "Copy Tag Name")) { copy(tag.name) }
      Button(L10n.text("复制完整提交号", "Copy Full Commit Hash")) { copy(tag.commitHash) }
      Divider()
      Button(L10n.text("删除本地 Tag…", "Delete Local Tag…"), role: .destructive) {
        model.dialog = .deleteTag(tag)
      }
      .disabled(model.isWorking)
    }
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}

struct TagDetailsHeader: View {
  let tag: TagRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(tag.name, systemImage: "tag.fill")
        .font(.headline)
        .foregroundStyle(.blue)
        .textSelection(.enabled)
      Text(
        tag.isAnnotated
          ? L10n.text("附注 Tag", "Annotated Tag") : L10n.text("轻量 Tag", "Lightweight Tag")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if tag.isAnnotated {
        Text(tag.author)
          .font(.caption)
        ScrollView {
          Text(tag.message.trimmingCharacters(in: .newlines))
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 110)
      }
      Text(tag.date.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NewTagSheet: View {
  var model: AppModel
  let target: TagTarget
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var annotated = true
  @State private var message = ""
  @State private var check: BranchNameCheck = .empty

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("创建 Tag", "Create Tag")).font(.headline)
      Text(target.label).font(.callout).lineLimit(2)
      Text(String(target.commit.hash.prefix(7)) + " · " + target.commit.subject)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
        .help(target.commit.hash)
      TextField(L10n.text("Tag 名称", "Tag name"), text: $name)
        .textFieldStyle(.roundedBorder)
      Text(hint)
        .font(.caption)
        .foregroundStyle(check == .invalid || check == .duplicate ? Color.red : Color.secondary)
      Toggle(L10n.text("附注 Tag", "Annotated Tag"), isOn: $annotated)
        .toggleStyle(.checkbox)
      if annotated {
        Text(L10n.text("Tag 说明", "Tag message")).font(.caption)
        TextEditor(text: $message)
          .font(.body)
          .frame(height: 100)
          .border(Color.secondary.opacity(0.25))
      }
      HStack {
        if model.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button(L10n.text("取消", "Cancel")) { dismiss() }
        Button(L10n.text("创建 Tag", "Create Tag")) {
          Task {
            await model.createTag(
              named: name, target: target, annotated: annotated, message: message)
          }
        }
        .disabled(
          check != .ok
            || (annotated && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 440)
    .disabled(model.isWorking)
    .interactiveDismissDisabled(model.isWorking)
    .task(id: name) {
      check = .checking
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      let result = await model.validateTagName(name)
      guard !Task.isCancelled else { return }
      check = result
    }
  }

  private var hint: String {
    switch check {
    case .empty: L10n.text("请输入 Tag 名称", "Enter a tag name")
    case .checking: L10n.text("正在检查名称…", "Checking name…")
    case .ok: L10n.text("可以创建", "Ready to create")
    case .duplicate: L10n.text("Tag 已存在", "Tag already exists")
    case .invalid: L10n.text("名称不合法", "Invalid tag name")
    }
  }
}

struct PushTagSheet: View {
  var model: AppModel
  let tag: TagRecord
  @Environment(\.dismiss) private var dismiss
  @State private var remotes: [String] = []
  @State private var selectedRemote = ""
  @State private var loading = true
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("推送 Tag", "Push Tag")).font(.headline)
      Text(tag.name).textSelection(.enabled)
      Text(String(tag.commitHash.prefix(7)))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
      if loading {
        ProgressView()
      } else if let error {
        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        Button(L10n.text("重试", "Retry")) { Task { await loadRemotes() } }
      } else if remotes.isEmpty {
        Text(L10n.text("该仓库没有远程", "This repository has no remotes"))
          .foregroundStyle(.secondary)
      } else {
        Picker(L10n.text("远程", "Remote"), selection: $selectedRemote) {
          ForEach(remotes, id: \.self) { Text($0).tag($0) }
        }
      }
      HStack {
        if model.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button(L10n.text("取消", "Cancel")) { dismiss() }
        Button(L10n.text("推送", "Push")) {
          Task { await model.pushTag(tag, remote: selectedRemote) }
        }
        .disabled(loading || error != nil || selectedRemote.isEmpty)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 400)
    .disabled(model.isWorking)
    .interactiveDismissDisabled(model.isWorking)
    .task { await loadRemotes() }
  }

  private func loadRemotes() async {
    guard let repository = model.repositoryURL else { return }
    loading = true
    error = nil
    do {
      let git = WindowGitClient()
      let result = try await git.performCancellable {
        try await GitTags.remotes(repository: repository)
      }
      guard !Task.isCancelled else { return }
      remotes = result
      selectedRemote = result.contains("origin") ? "origin" : (result.first ?? "")
    } catch {
      guard !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
    loading = false
  }
}
