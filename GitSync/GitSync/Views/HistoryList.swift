import SwiftUI

struct HistoryList: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var relative: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LanguageSettings.shared.language.locale
        formatter.unitsStyle = .full
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(
                L10n.text("历史范围", "History scope"),
                selection: Binding(
                    get: { model.historyScope },
                    set: { model.setHistoryScope($0) }
                )
            ) {
                ForEach(HistoryScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isWorking)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            HStack {
                Text(scopeDescription)
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
                Text(model.isRefreshing ? L10n.text("正在读取提交历史…", "Loading commit history…") : L10n.text("还没有提交", "No commits yet"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let graphRows = model.commitGraphRows
                let maximumLaneCount = max(graphRows.values.map(\.laneCount).max() ?? 1, 1)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.commits) { commit in
                            commitRow(
                                commit,
                                graph: graphRows[commit.hash],
                                maximumLaneCount: maximumLaneCount
                            )
                        }
                        if model.canLoadMoreHistory {
                            Button(L10n.text("加载更多", "Load More")) {
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

    private var scopeDescription: String {
        switch model.historyScope {
        case .current: L10n.text("当前分支可到达的提交", "Commits reachable from the current branch")
        case .mainline: L10n.text("当前分支主线提交", "Mainline commits on the current branch")
        case .all: L10n.text("本地与远程所有分支", "All local and remote branches")
        }
    }

    private func commitRow(
        _ commit: CommitRecord,
        graph: CommitGraphRow?,
        maximumLaneCount: Int
    ) -> some View {
        let isSelected = model.selectedCommitHash == commit.hash
        let rowHeight: CGFloat = commit.references.isEmpty && !commit.isMerge ? 64 : 86
        return Button {
            Task { await model.selectCommit(commit.hash) }
        } label: {
            HStack(alignment: .top, spacing: 4) {
                if let graph {
                    CommitGraphView(
                        row: graph,
                        maximumLaneCount: maximumLaneCount,
                        isSelected: isSelected
                    )
                    .frame(width: graphWidth(maximumLaneCount), height: rowHeight)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if !commit.references.isEmpty || commit.isMerge {
                        HStack(spacing: 4) {
                            if commit.isMerge {
                                referenceBadge(L10n.text("合并", "Merge"), color: .orange, isSelected: isSelected)
                            }
                            ForEach(Array(commit.references.prefix(2)), id: \.self) { reference in
                                referenceBadge(
                                    reference,
                                    color: referenceColor(reference),
                                    isSelected: isSelected
                                )
                            }
                            if commit.references.count > 2 {
                                Text("+\(commit.references.count - 2)")
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                            }
                        }
                        .lineLimit(1)
                    }

                    Text(commit.subject.isEmpty ? L10n.text("（无说明）", "(No message)") : commit.subject)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle.fill")
                        Text(commit.authorName)
                            .lineLimit(1)
                        Text("·")
                        Text(relative.localizedString(for: commit.date, relativeTo: Date()))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(commit.shortHash)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                    .help(commit.authorEmail)
                }
                .padding(.vertical, 7)
            }
            .padding(.horizontal, 5)
            .frame(minHeight: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.text("创建 Tag…", "Create Tag…")) {
                Task { await model.presentNewTag(reference: commit.hash, label: commit.shortHash) }
            }
            .disabled(model.isWorking)
            Button(L10n.text("创建分支…", "Create Branch…")) {
                model.presentNewBranch(startCommit: commit.hash)
            }
            .disabled(model.isWorking)
            Button(L10n.text("差异对比", "Compare Changes")) {
                Task {
                    if let request = await model.prepareComparison(reference: commit.hash, label: commit.shortHash) {
                        openWindow(value: request)
                    }
                }
            }
            .disabled(model.isWorking)
        }
    }

    private func graphWidth(_ laneCount: Int) -> CGFloat {
        min(max(CGFloat(laneCount) * 14 + 10, 28), 86)
    }

    private func referenceBadge(_ title: String, color: Color, isSelected: Bool) -> some View {
        Label(title.hasPrefix("tag: ") ? String(title.dropFirst(5)) : title, systemImage: title.hasPrefix("tag: ") ? "tag.fill" : "arrow.triangle.branch")
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(isSelected ? Color.white : color)
            .background(
                isSelected ? Color.white.opacity(0.16) : color.opacity(0.14),
                in: Capsule()
            )
    }

    private func referenceColor(_ reference: String) -> Color {
        if reference == "HEAD" { return .red }
        if reference.hasPrefix("tag: ") { return .blue }
        if model.remoteBranchNames.contains(reference) { return .purple }
        return .green
    }
}

private struct CommitGraphView: View {
    let row: CommitGraphRow
    let maximumLaneCount: Int
    let isSelected: Bool

    private let palette: [Color] = [
        .blue, .orange, .green, .purple, .pink, .cyan, .yellow, .indigo,
    ]

    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2

            for edge in row.throughEdges {
                var path = Path()
                path.move(to: CGPoint(x: x(edge.fromLane, width: size.width), y: 0))
                path.addCurve(
                    to: CGPoint(x: x(edge.toLane, width: size.width), y: size.height),
                    control1: CGPoint(x: x(edge.fromLane, width: size.width), y: centerY),
                    control2: CGPoint(x: x(edge.toLane, width: size.width), y: centerY)
                )
                context.stroke(
                    path,
                    with: .color(lineColor(edge.fromLane)),
                    lineWidth: 1.5
                )
            }

            var incoming = Path()
            incoming.move(to: CGPoint(x: x(row.nodeLane, width: size.width), y: 0))
            incoming.addLine(to: CGPoint(x: x(row.nodeLane, width: size.width), y: centerY))
            context.stroke(
                incoming,
                with: .color(lineColor(row.nodeLane)),
                lineWidth: 1.8
            )

            for (index, parentLane) in row.parentLanes.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: x(row.nodeLane, width: size.width), y: centerY))
                path.addCurve(
                    to: CGPoint(x: x(parentLane, width: size.width), y: size.height),
                    control1: CGPoint(x: x(row.nodeLane, width: size.width), y: centerY + 10),
                    control2: CGPoint(x: x(parentLane, width: size.width), y: centerY + 10)
                )
                context.stroke(
                    path,
                    with: .color(lineColor(index == 0 ? row.nodeLane : parentLane)),
                    lineWidth: index == 0 ? 1.8 : 1.5
                )
            }

            let nodePoint = CGPoint(x: x(row.nodeLane, width: size.width), y: centerY)
            let nodeRect = CGRect(x: nodePoint.x - 4, y: nodePoint.y - 4, width: 8, height: 8)
            context.fill(
                Path(ellipseIn: nodeRect),
                with: .color(isSelected ? .white : palette[row.nodeLane % palette.count])
            )
        }
    }

    private func x(_ lane: Int, width: CGFloat) -> CGFloat {
        guard maximumLaneCount > 1 else { return width / 2 }
        let spacing = min(14, max((width - 12) / CGFloat(maximumLaneCount - 1), 5))
        return 6 + CGFloat(lane) * spacing
    }

    private func lineColor(_ lane: Int) -> Color {
        if isSelected { return .white.opacity(0.62) }
        return palette[lane % palette.count].opacity(0.82)
    }
}
