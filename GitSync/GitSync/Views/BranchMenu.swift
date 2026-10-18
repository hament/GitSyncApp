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
                Text(model.branchDisplayName.isEmpty ? "分支" : model.branchDisplayName)
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
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索分支", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !hasMatches {
                        Text("没有匹配的分支")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        section("当前", items: filtered.current)
                        section("最近", items: filtered.recent)
                        section("本地", items: filtered.local)
                        section("远程", items: filtered.remote)
                    }
                }
                .padding(10)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("新建分支…") {
                    dismiss()
                    model.presentNewBranch()
                }
                .disabled(model.isWorking)
                Button("合并到当前分支…") {
                    dismiss()
                    model.presentMergePicker()
                }
                .disabled(model.isWorking || model.isDetached)
                if model.isDetached {
                    Text("请先创建或切换到一个分支")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(width: 320, height: 460)
        .onAppear { searchFocused = true }
    }

    private var filtered: (current: [BranchItem], recent: [BranchItem], local: [BranchItem], remote: [BranchItem]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func match(_ name: String) -> Bool {
            query.isEmpty || name.localizedCaseInsensitiveContains(query)
        }

        var current: [BranchItem] = []
        if let name = model.currentBranchName, match(name) {
            current = [BranchItem(name: name, isRemote: false)]
        }

        let recentNames = model.recentBranchNames.filter { $0 != model.currentBranchName && match($0) }
        let recent = recentNames.map { BranchItem(name: $0, isRemote: false) }
        let recentSet = Set(recentNames)
        let local = model.localBranchNames
            .filter { $0 != model.currentBranchName && !recentSet.contains($0) && match($0) }
            .map { BranchItem(name: $0, isRemote: false) }
        let remote = model.remoteBranchNames
            .filter(match)
            .map { BranchItem(name: $0, isRemote: true) }
        return (current, recent, local, remote)
    }

    private var hasMatches: Bool {
        !filtered.current.isEmpty || !filtered.recent.isEmpty || !filtered.local.isEmpty || !filtered.remote.isEmpty
    }

    @ViewBuilder
    private func section(_ title: String, items: [BranchItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    branchRow(item)
                }
            }
        }
    }

    private func branchRow(_ item: BranchItem) -> some View {
        let isCurrent = !item.isRemote && item.name == model.currentBranchName
        return Button {
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
    }
}
