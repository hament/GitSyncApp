import SwiftUI

struct BranchMenu: View {
  @Bindable var model: AppModel
  @State private var shown = false

  var body: some View {
    Button {
      shown.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "arrow.triangle.branch")
        Text(model.localizedBranchDisplayName)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.caption)
      }
    }
    .disabled(model.isWorking || model.repositoryPath == nil)
    .popover(isPresented: $shown, arrowEdge: .bottom) {
      BranchPanel(model: model) { shown = false }
    }
  }
}

private struct BranchPanel: View {
  @Bindable var model: AppModel
  var dismiss: () -> Void
  @State private var query = ""
  @State private var sections: BranchListSections?
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField(L10n.text("搜索分支", "Search branches"), text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .padding(10)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if let sections {
            if sections.isEmpty {
              Text(L10n.text("没有匹配的分支", "No matching branches"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
              section(L10n.text("当前", "Current"), items: sections.current)
              section(L10n.text("最近", "Recent"), items: sections.recent)
              section(L10n.text("本地", "Local"), items: sections.local)
              section(L10n.text("远程", "Remote"), items: sections.remote, isRemote: true)
            }
          } else {
            ProgressView(L10n.text("正在加载分支…", "Loading branches…"))
              .controlSize(.small)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 20)
          }
        }
        .padding(10)
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        Button(L10n.text("新建分支…", "New Branch…")) {
          dismiss()
          model.presentNewBranch()
        }
        .disabled(model.isWorking)
        Button(L10n.text("合并到当前分支…", "Merge into Current Branch…")) {
          dismiss()
          model.presentMergePicker()
        }
        .disabled(model.isWorking || model.isDetached)
        Button(L10n.text("分支对比…", "Compare Branches…")) {
          dismiss()
          model.presentBranchComparison()
        }
        .disabled(model.isWorking)
        if model.isDetached {
          Text(L10n.text("请先创建或切换到一个分支", "Create or switch to a branch first"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
    }
    .frame(width: 320, height: 460)
    .onAppear { searchFocused = true }
    .task(id: snapshot) {
      let snapshot = snapshot
      sections = nil
      let loaded = await Task.detached(priority: .userInitiated) {
        snapshot.filtered()
      }.value
      guard !Task.isCancelled else { return }
      sections = loaded
    }
  }

  private var snapshot: BranchListSnapshot {
    BranchListSnapshot(
      repositoryPath: model.repositoryPath,
      currentBranchName: model.currentBranchName,
      recentBranchNames: model.recentBranchNames,
      localBranchNames: model.localBranchNames,
      remoteBranchNames: model.remoteBranchNames,
      query: query
    )
  }

  @ViewBuilder
  private func section(_ title: String, items: [String], isRemote: Bool = false) -> some View {
    if !items.isEmpty {
      Section {
        ForEach(items, id: \.self) { name in
          branchRow(BranchItem(name: name, isRemote: isRemote))
        }
      } header: {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 10)
      }
    }
  }

  private func branchRow(_ item: BranchItem) -> some View {
    let isCurrent = !item.isRemote && item.name == model.currentBranchName
    return HStack(spacing: 6) {
      Button {
        dismiss()
        Task { await model.switchBranch(item) }
      } label: {
        HStack {
          Text(item.name)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 8)
          if isCurrent {
            Image(systemName: "checkmark")
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isCurrent || model.isWorking)
      if !item.isRemote {
        Button(role: .destructive) {
          dismiss()
          model.askDeleteBranch(item)
        } label: {
          Image(systemName: "trash")
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!model.canDeleteBranch(item))
        .help(L10n.text("删除未发布的本地分支", "Delete unpublished local branch"))
        .accessibilityLabel(L10n.text("删除分支 \(item.name)", "Delete branch \(item.name)"))
      }
    }
    .contextMenu {
      Button(L10n.text("创建 Tag…", "Create Tag…")) {
        dismiss()
        let reference = (item.isRemote ? "refs/remotes/" : "refs/heads/") + item.name
        Task { await model.presentNewTag(reference: reference, label: item.name) }
      }
      .disabled(model.isWorking)
      if !item.isRemote {
        Button(L10n.text("删除分支…", "Delete Branch…"), role: .destructive) {
          dismiss()
          model.askDeleteBranch(item)
        }
        .disabled(!model.canDeleteBranch(item))
      }
    }
  }
}
