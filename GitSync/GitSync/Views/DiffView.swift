import SwiftUI

struct DiffView: View {
    var model: AppModel
    var comparison = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.diffTitle.isEmpty {
                fileHeader
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if model.diffTitle.isEmpty {
            emptyState(L10n.text("选择一个文件查看差异", "Select a file to view its diff"), systemImage: "doc.text.magnifyingglass")
        } else if model.diff.isBinary {
            emptyState(L10n.text("二进制文件，不显示差异", "Diff not available for binary files"), systemImage: "doc.zipper")
        } else if model.diff.lines.isEmpty {
            emptyState(L10n.text("没有差异", "No differences"), systemImage: "checkmark.circle")
        } else if model.diffLayoutMode == .split {
            splitContent
        } else {
            unifiedContent
        }
    }

    private var unifiedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.diff.truncated {
                truncatedNotice
            }
            selectableContent
        }
    }

    private var splitContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Label(comparison ? L10n.text("当前分支", "Current branch") : L10n.text("旧文件", "Old file"), systemImage: "arrow.left")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label(comparison ? L10n.text("对比文件", "Comparison file") : L10n.text("新文件", "New file"), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            if model.diff.truncated {
                truncatedNotice
            }
            selectableContent
        }
    }

    private var selectableContent: some View {
        SelectableDiffView(
            document: model.diff,
            mode: model.diffLayoutMode,
            identity: "\(model.mode)-\(model.selectedHistoryHash ?? "")-\(model.diffTitle)"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                let fileName = (model.diffTitle as NSString).lastPathComponent
                HStack(spacing: 5) {
                    Text(fileName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(fileName)
                    DiffHeaderCopyButton(
                        text: fileName,
                        title: L10n.text("复制文件名", "Copy file name")
                    )
                }
                HStack(spacing: 5) {
                    Text(model.diffTitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.diffTitle)
                    DiffHeaderCopyButton(
                        text: model.diffTitle,
                        title: L10n.text("复制相对文件路径", "Copy relative file path")
                    )
                }
            }

            Spacer(minLength: 12)

            Text(comparison ? L10n.text("对比差异", "Comparison diff") : (model.mode != .changes ? L10n.text("提交差异", "Commit diff") : L10n.text("工作区差异", "Working tree diff")))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                L10n.text("显示模式", "Display mode"),
                selection: Binding(
                    get: { model.diffLayoutMode },
                    set: { model.diffLayoutMode = $0 }
                )
            ) {
                Text("Unified").tag(DiffLayoutMode.unified)
                Text("Split").tag(DiffLayoutMode.split)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 142)

            changeBadge("+\(model.diff.additionCount)", color: .green)
            changeBadge("−\(model.diff.deletionCount)", color: .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.025))
    }

    private var truncatedNotice: some View {
        Text(L10n.text("差异过长，已截断", "Diff truncated because it is too long"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func changeBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct DiffHeaderCopyButton: View {
    let text: String
    let title: String
    @State private var copyID: UUID?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(text, forType: .string) {
                copyID = UUID()
            }
        } label: {
            Image(systemName: copyID == nil ? "doc.on.doc" : "checkmark")
        }
        .buttonStyle(CommitCopyButtonStyle())
        .help(copyID == nil ? title : L10n.text("已复制", "Copied"))
        .accessibilityLabel(title)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copyID = nil
        }
        .onChange(of: text) { copyID = nil }
    }
}
