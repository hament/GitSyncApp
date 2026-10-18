import SwiftUI

struct ToolbarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BranchMenu(model: model)

                Spacer(minLength: 12)

                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.isBusy ? model.busyLabel : model.refreshLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("取消") {
                        model.cancelCurrentOperation()
                    }
                    .buttonStyle(.borderless)
                } else if let banner = model.banner {
                    Text(banner)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    ToolbarActionButton(
                        title: "刷新",
                        systemImage: "arrow.clockwise",
                        tint: .secondary,
                        isDisabled: model.isWorking,
                        help: "重新读取仓库状态和提交数"
                    ) {
                        model.refreshNow()
                    }

                    ToolbarActionButton(
                        title: "Fetch",
                        systemImage: "arrow.down.circle",
                        tint: .blue,
                        isDisabled: model.isWorking,
                        help: "获取远程更新"
                    ) {
                        Task { await model.fetch() }
                    }

                    ToolbarActionButton(
                        title: "Pull",
                        systemImage: "arrow.down.to.line",
                        tint: .indigo,
                        badge: model.remoteAheadCount,
                        isDisabled: model.isWorking,
                        help: pullHelp
                    ) {
                        Task { await model.pull() }
                    }

                    ToolbarActionButton(
                        title: "Push",
                        systemImage: "arrow.up.to.line",
                        tint: .green,
                        badge: model.unpushedCount,
                        isDisabled: model.isWorking,
                        help: pushHelp
                    ) {
                        Task { await model.push() }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                ProjectMenu(model: model)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repositoryName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(model.repositoryPath ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.repositoryPath ?? "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))
        }
    }

    private var repositoryName: String {
        guard let path = model.repositoryPath, !path.isEmpty else { return "未选择项目" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var pullHelp: String {
        guard let count = model.remoteAheadCount else {
            return "拉取远程提交；当前分支没有可比较的远程分支"
        }
        return count == 0 ? "拉取远程提交；远程没有领先提交" : "拉取远程提交；远程领先 \(count) 个提交"
    }

    private var pushHelp: String {
        guard let count = model.unpushedCount else {
            return "推送本地提交；当前分支没有可比较的远程分支"
        }
        return count == 0 ? "推送本地提交；没有未推送的提交" : "推送本地提交；有 \(count) 个提交尚未推送"
    }
}

struct ProjectMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Button {
                model.chooseRepository()
            } label: {
                Label("选择本机文件夹…", systemImage: "folder.badge.plus")
            }

            if !model.recentRepositoryPaths.isEmpty {
                Divider()
                Section("最近项目") {
                    ForEach(model.recentRepositoryPaths, id: \.self) { path in
                        Button {
                            model.openRecentRepository(path)
                        } label: {
                            Label(recentProjectTitle(path), systemImage: recentProjectIcon(path))
                        }
                    }
                }
            }
        } label: {
            Label("选择项目", systemImage: "folder")
        }
        .disabled(model.isWorking)
        .fixedSize()
        .help("选择本机 Git 仓库，或打开最近使用的项目")
    }

    private func recentProjectTitle(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return "\(url.lastPathComponent) — \(path)"
    }

    private func recentProjectIcon(_ path: String) -> String {
        path == model.repositoryPath ? "checkmark.circle.fill" : "clock.arrow.circlepath"
    }
}

private struct ToolbarActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badge: Int?
    let isDisabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(isHovering && !isDisabled ? 0.15 : 0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(isHovering && !isDisabled ? 0.38 : 0.2), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let badge, badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(.red, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                    }
                    .offset(x: 7, y: -7)
                    .accessibilityLabel("\(badge) 个提交")
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
