import SwiftUI

struct CommitBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("提交说明", text: $model.commitMessage, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            Button(model.mergeInProgress ? "完成合并" : "提交 \(model.checkedCount) 个文件") {
                Task { await model.commit() }
            }
            .disabled(!model.canCommit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
