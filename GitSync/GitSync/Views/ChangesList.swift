import SwiftUI

struct ChangesList: View {
  @Bindable var model: AppModel
  @State private var conflictsOnly = false

  private var hasConflicts: Bool {
    model.files.contains { $0.kind == .conflict }
  }

  private var visibleFiles: [FileChange] {
    conflictsOnly && hasConflicts ? model.files.filter { $0.kind == .conflict } : model.files
  }

  private var allVisibleChecked: Bool {
    !visibleFiles.isEmpty && visibleFiles.allSatisfy { model.checkedPaths.contains($0.path) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L10n.text("变更 · \(visibleFiles.count)", "Changes · \(visibleFiles.count)"))
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button(
          allVisibleChecked ? L10n.text("取消全选", "Deselect All") : L10n.text("全选", "Select All")
        ) {
          let paths = Set(visibleFiles.map(\.path))
          if allVisibleChecked {
            model.checkedPaths.subtract(paths)
          } else {
            model.checkedPaths.formUnion(paths)
          }
        }
        .disabled(visibleFiles.isEmpty || model.isWorking)
        .buttonStyle(.borderless)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 6)

      if hasConflicts {
        Toggle(L10n.text("仅冲突", "Conflicts Only"), isOn: $conflictsOnly)
          .toggleStyle(.switch)
          .controlSize(.small)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.bottom, 6)
      }

      if model.files.isEmpty {
        Text(L10n.text("工作区没有修改", "No changes in the working tree"))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $model.selectedChangePaths) {
          ForEach(visibleFiles) { file in
            row(file)
              .tag(file.path)
          }
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: String.self) { paths in
          let targets = visibleFiles.filter { paths.contains($0.path) }
          if !targets.isEmpty {
            Button(L10n.text("放弃修改", "Discard Changes")) {
              model.dialog = .discardFiles(targets)
            }
            .disabled(model.isWorking)
            Button(L10n.text("忽略文件", "Ignore File")) {
              Task { await model.ignore(files: targets, folders: false) }
            }
            .disabled(model.isWorking)
            Button(L10n.text("忽略文件夹", "Ignore Folder")) {
              Task { await model.ignore(files: targets, folders: true) }
            }
            .disabled(
              model.isWorking
                || !targets.contains {
                  !($0.path as NSString).deletingLastPathComponent.isEmpty
                })
            Divider()
            Button(L10n.text("复制文件名", "Copy File Names")) {
              model.copyFiles(targets, value: .name)
            }
            Button(L10n.text("复制文件路径", "Copy File Paths")) {
              model.copyFiles(targets, value: .path)
            }
            Button(L10n.text("复制文件内容", "Copy File Contents")) {
              model.copyFiles(targets, value: .contents)
            }
            .disabled(targets.count != 1 || !targets.allSatisfy { model.fileExists($0) })
            Divider()
            if let file = targets.first {
              Button(L10n.text("在 Finder 中显示", "Show in Finder")) { model.reveal(file) }
                .disabled(targets.count != 1)
              Button(L10n.text("用 VS Code 打开", "Open in VS Code")) { model.openInVSCode(file) }
                .disabled(targets.count != 1 || !model.fileExists(file))
            }
          }
        }
        .onChange(of: model.selectedChangePaths) { previous, current in
          let added = current.subtracting(previous)
          if let file = visibleFiles.first(where: { added.contains($0.path) })
            ?? visibleFiles.first(where: { current.contains($0.path) })
          {
            model.selectChange(file.path)
          } else {
            model.selectedPath = nil
            model.diff = .empty
            model.diffTitle = ""
          }
        }
      }
    }
    .onChange(of: visibleFiles.map(\.path)) { _, paths in
      let visiblePaths = Set(paths)
      model.selectedChangePaths.formIntersection(visiblePaths)
      if let selectedPath = model.selectedPath, !visiblePaths.contains(selectedPath) {
        model.selectedPath = nil
        model.diff = .empty
        model.diffTitle = ""
      }
    }
    .onChange(of: hasConflicts) { _, hasConflicts in
      if !hasConflicts { conflictsOnly = false }
    }
    .onChange(of: model.repositoryPath) { _, _ in
      conflictsOnly = false
    }
  }

  private func row(_ file: FileChange) -> some View {
    HStack(spacing: 8) {
      Toggle(
        L10n.text("选择 \(file.path)", "Select \(file.path)"),
        isOn: Binding(
          get: { model.checkedPaths.contains(file.path) },
          set: { model.setChecked(file.path, $0) }
        )
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .disabled(model.isWorking)

      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(file.path)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
          if file.kind == .renamed, let oldPath = file.oldPath {
            Text(oldPath)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        Spacer(minLength: 8)
        Text(file.kind.title)
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(statusColor(file.kind).opacity(0.18), in: Capsule())
          .foregroundStyle(statusColor(file.kind))
      }
      .contentShape(Rectangle())
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 5)
  }

  private func statusColor(_ kind: ChangeKind) -> Color {
    switch kind {
    case .modified: .orange
    case .added: .green
    case .deleted, .conflict: .red
    case .untracked: .secondary
    case .renamed: .blue
    }
  }
}
