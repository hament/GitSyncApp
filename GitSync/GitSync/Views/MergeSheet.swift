import SwiftUI

struct MergeSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: BranchItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("合并到 \(model.currentBranchName ?? model.branchDisplayName)")
                .font(.headline)
            Text("选择要合并进当前分支的分支。")
                .foregroundStyle(.secondary)
            TextField("搜索分支", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !hasBranches {
                        Text("没有匹配的分支")
                            .foregroundStyle(.secondary)
                    } else {
                        group("最近", items: groups.recent)
                        group("本地", items: groups.local)
                        group("远程", items: groups.remote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(mergeTitle) {
                    guard let selection else { return }
                    model.askMerge(selection.name)
                }
                .disabled(selection == nil || model.isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 520)
    }

    private var mergeTitle: String {
        let target = model.currentBranchName ?? model.branchDisplayName
        return "合并到 \(target)"
    }

    private var groups: (recent: [BranchItem], local: [BranchItem], remote: [BranchItem]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func match(_ name: String) -> Bool {
            name != model.currentBranchName && (query.isEmpty || name.localizedCaseInsensitiveContains(query))
        }
        let recentNames = model.recentBranchNames.filter(match)
        let recentSet = Set(recentNames)
        let recent = recentNames.map { BranchItem(name: $0, isRemote: false) }
        let local = model.localBranchNames
            .filter { match($0) && !recentSet.contains($0) }
            .map { BranchItem(name: $0, isRemote: false) }
        let remote = model.remoteBranchNames
            .filter(match)
            .map { BranchItem(name: $0, isRemote: true) }
        return (recent, local, remote)
    }

    private var hasBranches: Bool {
        !groups.recent.isEmpty || !groups.local.isEmpty || !groups.remote.isEmpty
    }

    @ViewBuilder
    private func group(_ title: String, items: [BranchItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    let selected = selection == item
                    Button {
                        selection = item
                    } label: {
                        HStack {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
