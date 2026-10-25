import SwiftUI

struct DiffView: View {
  var model: AppModel
  var comparison = false
  var comparisonRequest: ComparisonRequest?
  @State private var showsSource = false
  @State private var sourceText = ""
  @State private var sourceMessage: String?
  @State private var loadingSource = false

  private var sourceIdentity: String {
    "\(model.repositoryPath ?? comparisonRequest?.repositoryPath ?? "")-\(model.mode)-\(model.selectedHistoryHash ?? "")-\(model.diffTitle)-\(model.diff.hashValue)-\(showsSource)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !model.diffTitle.isEmpty {
        fileHeader
        Divider()
      }
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .textBackgroundColor))
    .task(id: sourceIdentity) {
      guard showsSource, !model.diffTitle.isEmpty else { return }
      await loadSource()
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.diffTitle.isEmpty {
      emptyState(
        L10n.text("选择一个文件查看差异", "Select a file to view its diff"),
        systemImage: "doc.text.magnifyingglass")
    } else if showsSource {
      if loadingSource {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let sourceMessage {
        emptyState(sourceMessage, systemImage: "doc.text")

      } else {
        SelectableSourceView(text: sourceText, identity: sourceIdentity)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else if model.diff.isBinary {
      emptyState(
        L10n.text("二进制文件，不显示差异", "Diff not available for binary files"), systemImage: "doc.zipper")
    } else if model.diff.lines.isEmpty {
      emptyState(L10n.text("没有差异", "No differences"), systemImage: "checkmark.circle")
    } else if model.diffLayoutMode == .split {
      splitContent
    } else {
      unifiedContent
    }
  }

  private var unifiedContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.diff.truncated {
        truncatedNotice
      }
      selectableContent
    }
  }

  private var splitContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Label(
          comparison ? L10n.text("当前分支", "Current branch") : L10n.text("旧文件", "Old file"),
          systemImage: "arrow.left"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        Label(
          comparison ? L10n.text("对比文件", "Comparison file") : L10n.text("新文件", "New file"),
          systemImage: "arrow.right"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(Color(nsColor: .controlBackgroundColor))
      Divider()
      if model.diff.truncated {
        truncatedNotice
      }
      selectableContent
    }
  }

  private var selectableContent: some View {
    SelectableDiffView(
      document: model.diff,
      mode: model.diffLayoutMode,
      identity: "\(model.mode)-\(model.selectedHistoryHash ?? "")-\(model.diffTitle)"
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var fileHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "doc.text")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          let fileName = (model.diffTitle as NSString).lastPathComponent
          HStack(spacing: 5) {
            Text(fileName)
              .font(.system(.body, design: .monospaced, weight: .semibold))
              .lineLimit(1)
              .truncationMode(.middle)
              .help(fileName)
            DiffHeaderCopyButton(
              text: fileName,
              title: L10n.text("复制文件名", "Copy file name")
            )
          }
          HStack(spacing: 5) {
            Text(model.diffTitle)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .help(model.diffTitle)
            DiffHeaderCopyButton(
              text: model.diffTitle,
              title: L10n.text("复制相对文件路径", "Copy relative file path")
            )
          }
        }

        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        Picker(L10n.text("文件内容", "File content"), selection: $showsSource) {
          Text(L10n.text("对比", "Diff")).tag(false)
          Text(L10n.text("原文", "Source")).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 110)
        .accessibilityIdentifier("diff.contentMode")

        Picker(
          L10n.text("显示模式", "Display mode"),
          selection: Binding(
            get: { model.diffLayoutMode },
            set: { model.diffLayoutMode = $0 }
          )
        ) {
          Text("Unified").tag(DiffLayoutMode.unified)
          Text("Split").tag(DiffLayoutMode.split)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 142)
        .disabled(showsSource)

        changeBadge("+\(model.diff.additionCount)", color: .green)
        changeBadge("−\(model.diff.deletionCount)", color: .red)
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(Color.primary.opacity(0.025))
  }

  private func loadSource() async {
    loadingSource = true
    sourceText = ""
    sourceMessage = nil
    let identity = sourceIdentity
    let path = model.diffTitle
    guard let repository = comparisonRequest?.repositoryPath ?? model.repositoryPath else {
      loadingSource = false
      return
    }
    let cwd = URL(fileURLWithPath: repository, isDirectory: true)
    let data: Data?
    if let request = comparisonRequest {
      let output = await GitClient.run(args: ["show", "\(request.headHash):\(path)"], cwd: cwd)
      if output.succeeded {
        data = output.stdout
      } else {
        let file = try? await GitComparison.files(request).first(where: { $0.path == path })
        if file?.labelText.chinese == "删除" {
          let previous = await GitClient.run(
            args: ["show", "\(request.baseHash):\(file?.oldPath ?? path)"], cwd: cwd)
          data = previous.succeeded ? previous.stdout : nil
        } else {
          data = nil
        }
      }
    } else if model.mode != .changes, let hash = model.selectedHistoryHash {
      let output = await GitClient.run(args: ["show", "\(hash):\(path)"], cwd: cwd)
      if output.succeeded {
        data = output.stdout
      } else if model.commitFiles[hash]?.first(where: { $0.path == path })?.labelText.chinese
        == "删除"
      {
        let previous = await GitClient.run(args: ["show", "\(hash)^:\(path)"], cwd: cwd)
        data = previous.succeeded ? previous.stdout : nil
      } else {
        data = nil
      }
    } else if model.files.first(where: { $0.path == path })?.kind == .deleted {
      let output = await GitClient.run(args: ["show", "HEAD:\(path)"], cwd: cwd)
      data = output.succeeded ? output.stdout : nil
    } else {
      let url = cwd.appendingPathComponent(path)
      data = await Task.detached { try? Data(contentsOf: url) }.value
    }
    guard !Task.isCancelled, identity == sourceIdentity else { return }
    loadingSource = false
    guard let data else {
      sourceMessage = L10n.text("无法读取文件原文", "Unable to read file source")
      return
    }
    guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
      sourceMessage = L10n.text(
        "二进制或非 UTF-8 文件，无法显示原文", "Source unavailable for binary or non-UTF-8 files")
      return
    }
    sourceText = text
  }

  private var truncatedNotice: some View {
    Text(L10n.text("差异过长，已截断", "Diff truncated because it is too long"))
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
  }

  private func changeBadge(_ title: String, color: Color) -> some View {
    Text(title)
      .font(.system(.caption, design: .monospaced, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.12), in: Capsule())
  }

  private func emptyState(_ title: String, systemImage: String) -> some View {
    VStack(spacing: 9) {
      Image(systemName: systemImage)
        .font(.system(size: 28))
        .foregroundStyle(.tertiary)
      Text(title)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}

private struct DiffHeaderCopyButton: View {
  let text: String
  let title: String
  @State private var copyID: UUID?

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setString(text, forType: .string) {
        copyID = UUID()
      }
    } label: {
      Image(systemName: copyID == nil ? "doc.on.doc" : "checkmark")
    }
    .buttonStyle(CommitCopyButtonStyle())
    .help(copyID == nil ? title : L10n.text("已复制", "Copied"))
    .accessibilityLabel(title)
    .task(id: copyID) {
      guard copyID != nil else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copyID = nil
    }
    .onChange(of: text) { copyID = nil }
  }
}
