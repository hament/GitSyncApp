import SwiftUI

struct HistoryList: View {
    var model: AppModel

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        if model.commits.isEmpty {
            Text("还没有提交")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.commits) { commit in
                        commitRow(commit)
                    }
                    if model.canLoadMoreHistory {
                        Button("加载更多") {
                            Task { await model.loadMoreHistory() }
                        }
                        .disabled(model.isBusy)
                        .padding(.vertical, 8)
                    }
                }
                .padding(8)
            }
        }
    }

    private func commitRow(_ commit: CommitRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(commit.subject.isEmpty ? "（无说明）" : commit.subject)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(commit.shortHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(commit.authorName) · \(Self.relative.localizedString(for: commit.date, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(commit.authorEmail)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await model.toggleCommit(commit.hash) }
            }

            if model.expandedCommit == commit.hash {
                let files = model.commitFiles[commit.hash] ?? []
                if files.isEmpty {
                    Text("这次提交没有改动文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                } else {
                    ForEach(files) { file in
                        HStack(spacing: 8) {
                            Text(file.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(file.path)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            model.selectedHistoryHash == commit.hash && model.selectedHistoryPath == file.path
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectHistoryFile(hash: commit.hash, path: file.path)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}
