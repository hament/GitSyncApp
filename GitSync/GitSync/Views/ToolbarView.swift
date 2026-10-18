import SwiftUI

struct ToolbarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Button("选择项目") { model.chooseRepository() }
                .disabled(model.isBusy)
                .buttonStyle(.bordered)
                .controlSize(.regular)

            Text(model.repositoryPath ?? "")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.repositoryPath ?? "")
                .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)

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

            HStack(spacing: 7) {
                ToolbarActionButton(
                    title: "刷新",
                    systemImage: "arrow.clockwise",
                    tint: .secondary,
                    isDisabled: model.isBusy,
                    help: "重新读取仓库状态和提交数"
                ) {
                    model.refreshNow()
                }

                ToolbarActionButton(
                    title: "Fetch",
                    systemImage: "arrow.down.circle",
                    tint: .blue,
                    isDisabled: model.isBusy,
                    help: "获取远程更新"
                ) {
                    Task { await model.fetch() }
                }

                ToolbarActionButton(
                    title: "Pull",
                    systemImage: "arrow.down.to.line",
                    tint: .indigo,
                    badge: model.remoteAheadCount,
                    isDisabled: model.isBusy,
                    help: pullHelp
                ) {
                    Task { await model.pull() }
                }

                ToolbarActionButton(
                    title: "Push",
                    systemImage: "arrow.up.to.line",
                    tint: .green,
                    badge: model.unpushedCount,
                    isDisabled: model.isBusy,
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
