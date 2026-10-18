import AppKit
import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.repositoryPath == nil {
                emptyState
            } else {
                workspace
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .navigationTitle(model.windowTitle)
        .background(WindowAutosave())
        .task { await model.restoreLastIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshIfIdle()
        }
        .sheet(item: $model.failure) { report in
            FailureSheet(report: report) { model.failure = nil }
        }
        .sheet(isPresented: $model.showNewBranch) {
            NewBranchSheet(model: model)
        }
        .sheet(isPresented: $model.showMerge) {
            MergeSheet(model: model)
        }
        .alert(dialogTitle, isPresented: dialogPresented) {
            dialogButtons
        } message: {
            Text(dialogMessage)
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model)
            if model.mergeInProgress {
                mergeBanner
            }
            Divider()
            HSplitView {
                sidebar
                    .frame(
                        minWidth: model.mode == .history ? 230 : 280,
                        idealWidth: model.mode == .history ? 270 : 340,
                        maxWidth: model.mode == .history ? 380 : 520
                    )
                if model.mode == .history {
                    CommitFilesView(model: model)
                        .frame(minWidth: 250, idealWidth: 310, maxWidth: 460)
                }
                DiffView(model: model)
                    .frame(minWidth: 420)
            }
            if model.showsCommitBar {
                Divider()
                CommitBar(model: model)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("列表", selection: Binding(
                get: { model.mode },
                set: { model.setMode($0) }
            )) {
                Text("变更").tag(SidebarMode.changes)
                Text("历史").tag(SidebarMode.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            if model.mode == .changes {
                ChangesList(model: model)
            } else {
                HistoryList(model: model)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var mergeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
            Text("正在合并 \(model.mergeSource)")
            Spacer()
            Button("中止合并") {
                model.dialog = .abortMerge
            }
            .disabled(model.isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("选择一个本地 Git 仓库")
                .font(.title3)
            Text("打开文件夹后，可以查看分支、变更和提交历史。")
                .foregroundStyle(.secondary)
            if model.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.refreshLabel)
                        .foregroundStyle(.secondary)
                    Button("取消") {
                        model.cancelCurrentOperation()
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                ProjectMenu(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dialogPresented: Binding<Bool> {
        Binding(
            get: { model.dialog != nil },
            set: { if !$0 { model.dialog = nil } }
        )
    }

    private var dialogTitle: String {
        switch model.dialog {
        case .discard: "放弃修改"
        case .removeFromIndex: "忽略已跟踪文件"
        case .merge: "合并分支"
        case .abortMerge: "中止合并"
        case .notRepository: "无法打开"
        case .vscodeMissing: "未找到 VS Code"
        case .plain(let title, _): title
        case nil: ""
        }
    }

    private var dialogMessage: String {
        switch model.dialog {
        case .discard(let file):
            if file.kind == .untracked {
                return "将把「\(file.path)」移到废纸篓。"
            }
            if file.kind == .conflict {
                return "放弃「\(file.path)」的修改会丢掉冲突中的两边内容。"
            }
            return "放弃「\(file.path)」的修改？此操作不能撤销。"
        case .removeFromIndex(let file):
            return "「\(file.path)」已被 Git 跟踪。已写入 .gitignore，但在从索引移除前仍会显示为变更。是否从索引中移除并保留工作区文件？"
        case .merge(let source):
            let target = model.currentBranchName ?? model.branchDisplayName
            return "将把「\(source)」合并到「\(target)」。"
        case .abortMerge:
            return "中止合并会丢弃这次合并中的改动，工作区回到合并前。"
        case .notRepository:
            return "这不是 Git 仓库。"
        case .vscodeMissing:
            return "未找到 Visual Studio Code。"
        case .plain(_, let message):
            return message
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var dialogButtons: some View {
        switch model.dialog {
        case .discard(let file):
            Button("放弃修改", role: .destructive) {
                Task { await model.discard(file) }
            }
            Button("取消", role: .cancel) {}
        case .removeFromIndex(let file):
            Button("移除索引并保留文件") {
                Task { await model.removeFromIndex(file) }
            }
            Button("仅保留 .gitignore", role: .cancel) {}
        case .merge(let source):
            Button("合并") {
                Task { await model.merge(source: source) }
            }
            Button("取消", role: .cancel) {}
        case .abortMerge:
            Button("中止合并", role: .destructive) {
                Task { await model.abortMerge() }
            }
            Button("取消", role: .cancel) {}
        case .notRepository, .vscodeMissing, .plain, nil:
            Button("好") {}
        }
    }
}

private struct WindowAutosave: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName("GitSyncMain")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window?.frameAutosaveName != "GitSyncMain" {
            nsView.window?.setFrameAutosaveName("GitSyncMain")
        }
    }
}
