import SwiftUI

struct ChangesList: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("变更 · \(model.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.allChecked ? "取消全选" : "全选") {
                    model.toggleSelectAll()
                }
                .disabled(model.files.isEmpty || model.isBusy)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if model.files.isEmpty {
                Text("工作区没有修改")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.files) { file in
                            row(file)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func row(_ file: FileChange) -> some View {
        HStack(spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.checkedPaths.contains(file.path) },
                    set: { model.setChecked(file.path, $0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(model.isBusy)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if file.kind == .renamed, let oldPath = file.oldPath {
                        Text(oldPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Text(file.kind.title)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(file.kind).opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor(file.kind))
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectChange(file.path) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            model.selectedPath == file.path ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contextMenu {
            Button("放弃修改") { model.dialog = .discard(file) }
            Button("忽略文件") { model.ignore(file) }
            Button("在 Finder 中显示") { model.reveal(file) }
            Button("用 VS Code 打开") { model.openInVSCode(file) }
                .disabled(!model.fileExists(file))
        }
    }

    private func statusColor(_ kind: ChangeKind) -> Color {
        switch kind {
        case .modified: .orange
        case .added: .green
        case .deleted, .conflict: .red
        case .untracked: .secondary
        case .renamed: .blue
        }
    }
}
