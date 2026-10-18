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
        VStack(spacing: 0) {
            HStack {
                Text("提交历史")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.commits.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if model.commits.isEmpty {
                Text("还没有提交")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.commits) { commit in
                            commitRow(commit)
                        }
                        if model.canLoadMoreHistory {
                            Button("加载更多") {
                                Task { await model.loadMoreHistory() }
                            }
                            .disabled(model.isWorking)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func commitRow(_ commit: CommitRecord) -> some View {
        let isSelected = model.selectedCommitHash == commit.hash
        return Button {
            Task { await model.selectCommit(commit.hash) }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Rectangle()
                        .fill(isSelected ? Color.white.opacity(0.45) : Color.secondary.opacity(0.2))
                        .frame(width: 1)
                        .frame(minHeight: 34)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(commit.subject.isEmpty ? "（无说明）" : commit.subject)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle.fill")
                        Text(commit.authorName)
                            .lineLimit(1)
                        Text("·")
                        Text(Self.relative.localizedString(for: commit.date, relativeTo: Date()))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(commit.shortHash)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                    .help(commit.authorEmail)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
