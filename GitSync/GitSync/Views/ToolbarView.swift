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

            Button("刷新") { model.refreshNow() }
                .disabled(model.isBusy)
            Button("获取") { Task { await model.fetch() } }
                .disabled(model.isBusy)
            Button("拉取") { Task { await model.pull() } }
                .disabled(model.isBusy)
            Button("推送") { Task { await model.push() } }
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
