import SwiftUI

struct CommitFilesView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let commit = model.selectedCommit {
                commitHeader(commit)
                Divider()
                filesContent(commit)
            } else {
                emptyState("选择一条提交", systemImage: "clock.arrow.circlepath")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func commitHeader(_ commit: CommitRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(commit.subject.isEmpty ? "（无说明）" : commit.subject)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.green)
                Text(commit.authorName)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Image(systemName: "number")
                Text(commit.shortHash)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func filesContent(_ commit: CommitRecord) -> some View {
        if model.loadingCommitHash == commit.hash {
            VStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取修改文件…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.commitFiles[commit.hash] == nil {
            emptyState("正在等待文件列表", systemImage: "doc.on.doc")
        } else if model.selectedCommitFiles.isEmpty {
            emptyState("这次提交没有修改文件", systemImage: "doc")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(model.selectedCommitFiles.count) 个修改文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.selectedCommitFiles.enumerated()), id: \.element.id) { index, file in
                            fileRow(file, hash: commit.hash)
                            if index < model.selectedCommitFiles.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ file: CommitFile, hash: String) -> some View {
        let isSelected = model.selectedHistoryHash == hash
            && model.selectedHistoryPath == file.path
        let fileName = (file.path as NSString).lastPathComponent
        let directory = (file.path as NSString).deletingLastPathComponent

        return Button {
            model.selectHistoryFile(hash: hash, path: file.path)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: statusIcon(file.label))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor(file.label))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .lineLimit(1)
                    if directory != "." && directory != "/" {
                        Text(directory)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let oldPath = file.oldPath {
                        Text("原路径：\(oldPath)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 6)

                Text(file.label)
                    .font(.caption2)
                    .foregroundStyle(statusColor(file.label))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusIcon(_ label: String) -> String {
        switch label {
        case "新增": "plus.square.fill"
        case "删除": "minus.square.fill"
        case "重命名": "arrow.right.square.fill"
        case "复制": "doc.on.doc.fill"
        case "冲突": "exclamationmark.triangle.fill"
        default: "pencil.square"
        }
    }

    private func statusColor(_ label: String) -> Color {
        switch label {
        case "新增": .green
        case "删除", "冲突": .red
        case "重命名", "复制": .blue
        default: .orange
        }
    }
}
