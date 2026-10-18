import SwiftUI

struct NewBranchSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var check: BranchNameCheck = .empty
    @State private var validateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建分支")
                .font(.headline)
            Text("从当前提交创建，并切换过去。")
                .foregroundStyle(.secondary)
            TextField("分支名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { create() }
            Text(hint)
                .font(.caption)
                .foregroundStyle(check == .ok || check == .empty || check == .checking ? Color.secondary : Color.red)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建并切换") { create() }
                    .disabled(check != .ok || model.isWorking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: name) { _, newValue in
            scheduleValidation(newValue)
        }
    }

    private var hint: String {
        switch check {
        case .empty: "请输入分支名称"
        case .checking: "正在检查名称…"
        case .ok: "可以创建"
        case .duplicate: "已存在"
        case .invalid: "名称不合法"
        }
    }

    private func scheduleValidation(_ raw: String) {
        validateTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            check = .empty
            return
        }
        check = .checking
        validateTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let result = await model.validateBranchName(raw)
            guard !Task.isCancelled else { return }
            check = result
        }
    }

    private func create() {
        guard check == .ok else { return }
        Task { await model.createBranch(named: name) }
    }
}
