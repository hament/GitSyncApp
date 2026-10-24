import SwiftUI

struct ToolbarView: View {
    @Bindable var model: AppModel
    @State private var pathCopyID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(repositoryName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(model.projectTheme.headerColor)
                            .lineLimit(1)
                        ProjectMenu(model: model)
                        CloneButton(model: model)
                    }
                    HStack(spacing: 5) {
                        Text(model.repositoryPath ?? "")
                            .font(.system(size: NSFont.preferredFont(forTextStyle: .caption1).pointSize + 1, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.repositoryPath ?? "")
                        Button {
                            guard let path = model.repositoryPath, !path.isEmpty else { return }
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setString(path, forType: .string) {
                                pathCopyID = UUID()
                            }
                        } label: {
                            Image(systemName: pathCopyID == nil ? "doc.on.doc" : "checkmark")
                        }
                        .buttonStyle(CommitCopyButtonStyle())
                        .disabled(model.repositoryPath?.isEmpty != false)
                        .help(pathCopyID == nil ? L10n.text("复制项目路径", "Copy project path") : L10n.text("项目路径已复制", "Project path copied"))
                        .accessibilityLabel(L10n.text("复制项目路径", "Copy project path"))
                        .task(id: pathCopyID) {
                            guard pathCopyID != nil else { return }
                            do { try await Task.sleep(for: .seconds(2)) } catch { return }
                            pathCopyID = nil
                        }
                        .onChange(of: model.repositoryPath) { pathCopyID = nil }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text((model.isBusy ? model.busyLabel : model.refreshLabel).localized)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button(L10n.text("取消", "Cancel")) {
                        model.cancelCurrentOperation()
                    }
                    .buttonStyle(.borderless)
                } else if let banner = model.banner {
                    Text(banner.localized)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    ToolbarActionButton(
                        title: "Refresh",
                        systemImage: "arrow.clockwise",
                        tint: .secondary,
                        isDisabled: model.isWorking,
                        help: L10n.text("重新读取仓库状态和提交数", "Reload repository status and commit counts")
                    ) {
                        model.refreshNow()
                    }

                    ToolbarActionButton(
                        title: "Fetch",
                        systemImage: "arrow.down.circle",
                        tint: .blue,
                        isDisabled: model.isWorking,
                        help: L10n.text("获取远程更新", "Fetch remote updates")
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
                SettingsButton(model: model)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(model.projectTheme.headerBackground)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                BranchMenu(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))
        }
    }

    private var repositoryName: String {
        guard let path = model.repositoryPath, !path.isEmpty else { return L10n.text("未选择项目", "No Project Selected") }
        return model.repositoryDisplayName.isEmpty
            ? URL(fileURLWithPath: path).lastPathComponent
            : model.repositoryDisplayName
    }

    private var pullHelp: String {
        guard let count = model.remoteAheadCount else {
            return L10n.text("拉取远程提交；当前分支没有可比较的远程分支", "Pull remote commits; no comparable remote branch")
        }
        return count == 0
            ? L10n.text("拉取远程提交；远程没有领先提交", "Pull remote commits; no incoming commits")
            : L10n.text("拉取远程提交；远程领先 \(count) 个提交", "Pull remote commits; \(count) incoming commits")
    }

    private var pushHelp: String {
        guard let count = model.unpushedCount else {
            return L10n.text("推送本地提交；当前分支没有可比较的远程分支", "Push local commits; no comparable remote branch")
        }
        return count == 0
            ? L10n.text("推送本地提交；没有未推送的提交", "Push local commits; no unpushed commits")
            : L10n.text("推送本地提交；有 \(count) 个提交尚未推送", "Push local commits; \(count) unpushed commits")
    }
}

struct CloneButton: View {
    var model: AppModel

    var body: some View {
        Button {
            model.presentClone()
        } label: {
            Label("Clone", systemImage: "square.and.arrow.down")
        }
        .disabled(model.isWorking)
        .fixedSize()
        .help(L10n.text("从 HTTP、HTTPS 或 SSH 地址克隆 Git 仓库", "Clone a Git repository over HTTP, HTTPS, or SSH"))
    }
}

struct ProjectMenu: View {
    @Bindable var model: AppModel
    @State private var isHovering = false
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            HStack(spacing: 4) {
                Label(L10n.text("选择项目", "Choose Project"), systemImage: "folder")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
        .disabled(model.isWorking)
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(model.projectTheme.color.opacity(isHovering && !model.isWorking ? 0.12 : 0))
        }
        .onHover { isHovering = $0 }
        .help(L10n.text("选择本机 Git 仓库，或打开最近使用的项目", "Choose a local Git repository or open a recent project"))
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    shown = false
                    model.chooseRepository()
                } label: {
                    Label(L10n.text("选择本机文件夹…", "Choose Local Folder…"), systemImage: "folder.badge.plus")
                }
                if !model.recentRepositoryPaths.isEmpty {
                    Divider()
                    Text(L10n.text("最近项目", "Recent Projects"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.recentRepositoryPaths, id: \.self) { path in
                                recentProjectRow(path)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(model.recentRepositoryPaths.count, 6)) * 52)
                }
            }
            .padding(12)
            .frame(width: 420)
            .disabled(model.isWorking)
        }
    }

    private func recentProjectRow(_ path: String) -> some View {
        HStack(spacing: 8) {
            Button {
                shown = false
                model.openRecentRepository(path)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recentProjectIcon(path))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(path)
            Button {
                model.removeRecentRepository(path)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(L10n.text("从最近项目移除，不删除本地文件", "Remove from recent projects without deleting local files"))
            .accessibilityLabel(L10n.text("移除最近项目 \(path)", "Remove recent project \(path)"))
            .accessibilityIdentifier("project.recent.remove.\(path)")
        }
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
                    .accessibilityLabel(L10n.text("\(badge) 个提交", "\(badge) commits"))
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
