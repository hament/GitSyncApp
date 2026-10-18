import SwiftUI

struct ToolbarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button("选择项目") { model.chooseRepository() }
                .disabled(model.isBusy)

            Text(model.repositoryPath ?? "")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.repositoryPath ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(model.busyLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let banner = model.banner {
                Text(banner)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            BranchMenu(model: model)

            divergenceCounts

            Button("刷新") { model.refreshNow() }
                .disabled(model.isBusy)
            Button("Fetch") { Task { await model.fetch() } }
                .disabled(model.isBusy)
            Button("Pull") { Task { await model.pull() } }
                .disabled(model.isBusy)
            Button("Push") { Task { await model.push() } }
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var divergenceCounts: some View {
        HStack(spacing: 8) {
            countLabel("未推送", model.unpushedCount)
            countLabel("远程领先", model.remoteAheadCount)
        }
        .help("未推送是本地还没推到上游的提交数，远程领先是上游比本地多的提交数。启动时和点击刷新时重新计算。")
    }

    private func countLabel(_ title: String, _ count: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(count.map(String.init) ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(count == nil ? Color.secondary : Color.primary)
        }
    }
}
