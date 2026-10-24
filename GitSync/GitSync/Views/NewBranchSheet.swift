import SwiftUI

struct NewBranchSheet: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var check: BranchNameCheck = .empty
  @State private var validateTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("新建分支", "New Branch"))
        .font(.headline)
      Text(
        model.newBranchStartCommit.map {
          L10n.text(
            "从提交 \($0.prefix(7)) 创建，并切换过去。",
            "Create a branch from commit \($0.prefix(7)) and switch to it.")
        }
          ?? L10n.text(
            "从当前提交创建，并切换过去。", "Create a branch from the current commit and switch to it.")
      )
      .foregroundStyle(.secondary)
      TextField(L10n.text("分支名称", "Branch name"), text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit { create() }
      Text(hint)
        .font(.caption)
        .foregroundStyle(
          check == .ok || check == .empty || check == .checking ? Color.secondary : Color.red)
      HStack {
        Spacer()
        Button(L10n.text("取消", "Cancel")) { dismiss() }
        Button(L10n.text("创建并切换", "Create and Switch")) { create() }
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
    case .empty: L10n.text("请输入分支名称", "Enter a branch name")
    case .checking: L10n.text("正在检查名称…", "Checking name…")
    case .ok: L10n.text("可以创建", "Ready to create")
    case .duplicate: L10n.text("已存在", "Branch already exists")
    case .invalid: L10n.text("名称不合法", "Invalid branch name")
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
    let startCommit = model.newBranchStartCommit
    Task { await model.createBranch(named: name, startCommit: startCommit) }
  }
}
