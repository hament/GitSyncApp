import SwiftUI

struct CommitFilesView: View {
  var model: AppModel
  @State private var copyToastID: UUID?

  var body: some View {
    VStack(spacing: 0) {
      if let commit = model.selectedCommit {
        commitHeader(commit)
        Divider()
        filesContent(commit)
      } else {
        emptyState(L10n.text("选择一条提交", "Select a commit"), systemImage: "clock.arrow.circlepath")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .bottom) {
      if copyToastID != nil {
        Label(L10n.text("提交号已复制", "Commit hash copied"), systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.primary)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
          .padding(12)
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.15), value: copyToastID != nil)
    .task(id: copyToastID) {
      guard copyToastID != nil else { return }
      do {
        try await Task.sleep(for: .seconds(2))
      } catch {
        return
      }
      copyToastID = nil
    }
    .onChange(of: model.selectedCommitHash) {
      copyToastID = nil
    }
  }

  private func commitHeader(_ commit: CommitRecord) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(commit.subject.isEmpty ? L10n.text("（无说明）", "(No message)") : commit.subject)
        .font(.headline)
        .lineLimit(2)

      HStack(spacing: 6) {
        Image(systemName: "person.crop.circle.fill")
          .foregroundStyle(.green)
        Text(commit.authorName)
          .lineLimit(1)
        Text("·")
          .foregroundStyle(.tertiary)
        Text(
          commit.date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
              .locale(LanguageSettings.shared.language.locale)
          )
        )
        .lineLimit(1)
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack(spacing: 5) {
        Image(systemName: "number")
        Text(commit.shortHash)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
        Button {
          NSPasteboard.general.clearContents()
          if NSPasteboard.general.setString(commit.hash, forType: .string) {
            copyToastID = UUID()
          }
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(CommitCopyButtonStyle())
        .help(L10n.text("复制完整提交号", "Copy full commit hash"))
        .accessibilityLabel(L10n.text("复制完整提交号", "Copy full commit hash"))
      }
      .foregroundStyle(.secondary)

      if !model.selectedCommitBranches.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.text("指向此提交的分支", "Branches pointing to this commit"))
            .font(.caption2)
            .foregroundStyle(.secondary)
          BranchTagLayout(spacing: 5) {
            ForEach(model.selectedCommitBranches.prefix(5), id: \.self) { branch in
              let isRemote = model.remoteBranchNames.contains(branch)
              Label(
                branch,
                systemImage: isRemote
                  ? "network"
                  : "arrow.triangle.branch"
              )
              .font(.system(size: 9, weight: .medium))
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .foregroundStyle(isRemote ? Color.purple : Color.green)
              .background(
                (isRemote ? Color.purple : Color.green).opacity(0.12),
                in: Capsule()
              )
            }
            if model.selectedCommitBranches.count > 5 {
              Text("...")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func filesContent(_ commit: CommitRecord) -> some View {
    if model.loadingCommitHash == commit.hash {
      VStack(spacing: 9) {
        ProgressView()
          .controlSize(.small)
        Text(L10n.text("正在读取修改文件…", "Loading changed files…"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.commitFiles[commit.hash] == nil {
      emptyState(L10n.text("正在等待文件列表", "Waiting for the file list"), systemImage: "doc.on.doc")
    } else if model.selectedCommitFiles.isEmpty {
      emptyState(L10n.text("这次提交没有修改文件", "No changed files in this commit"), systemImage: "doc")
    } else {
      VStack(spacing: 0) {
        HStack {
          Text(
            L10n.text(
              "\(model.selectedCommitFiles.count) 个修改文件",
              "\(model.selectedCommitFiles.count) changed files")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

        Divider()

        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(model.selectedCommitFiles.enumerated()), id: \.element.id) {
              index, file in
              fileRow(file, hash: commit.hash)
              if index < model.selectedCommitFiles.count - 1 {
                Divider()
              }
            }
          }
        }
      }
    }
  }

  private func fileRow(_ file: CommitFile, hash: String) -> some View {
    let isSelected =
      model.selectedHistoryHash == hash
      && model.selectedHistoryPath == file.path
    let fileName = (file.path as NSString).lastPathComponent
    let directory = (file.path as NSString).deletingLastPathComponent

    return Button {
      model.selectHistoryFile(hash: hash, path: file.path)
    } label: {
      HStack(spacing: 9) {
        Image(systemName: statusIcon(file.labelText.chinese))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(statusColor(file.labelText.chinese))
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 2) {
          Text(fileName)
            .font(.system(.callout, design: .monospaced, weight: .medium))
            .lineLimit(1)
          if directory != "." && directory != "/" {
            Text(directory)
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          if let oldPath = file.oldPath {
            Text(L10n.text("原路径：\(oldPath)", "Original path: \(oldPath)"))
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }

        Spacer(minLength: 6)

        Text(file.label)
          .font(.caption2)
          .foregroundStyle(statusColor(file.labelText.chinese))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }
    .buttonStyle(.plain)
  }

  private func emptyState(_ title: String, systemImage: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(.tertiary)
      Text(title)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func statusIcon(_ label: String) -> String {
    switch label {
    case "新增": "plus.square.fill"
    case "删除": "minus.square.fill"
    case "重命名": "arrow.right.square.fill"
    case "复制": "doc.on.doc.fill"
    case "冲突": "exclamationmark.triangle.fill"
    default: "pencil.square"
    }
  }

  private func statusColor(_ label: String) -> Color {
    switch label {
    case "新增": .green
    case "删除", "冲突": .red
    case "重命名", "复制": .blue
    default: .orange
    }
  }
}

struct CommitCopyButtonStyle: ButtonStyle {
  @Environment(\.projectTheme) private var theme
  @State private var isHovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 24, height: 24)
      .foregroundStyle(configuration.isPressed ? theme.color : Color.secondary)
      .background {
        RoundedRectangle(cornerRadius: 5)
          .fill(theme.color.opacity(configuration.isPressed ? 0.25 : (isHovering ? 0.12 : 0)))
      }
      .contentShape(Rectangle())
      .onHover { isHovering = $0 }
  }
}

private struct BranchTagLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrangement(width: proposal.width, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = arrangement(width: bounds.width, subviews: subviews)
    for (subview, frame) in zip(subviews, result.frames) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(frame.size)
      )
    }
  }

  private func arrangement(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect])
  {
    let availableWidth = max(0, width ?? .infinity)
    var frames: [CGRect] = []
    var positionX: CGFloat = 0
    var positionY: CGFloat = 0
    var rowHeight: CGFloat = 0
    var contentWidth: CGFloat = 0

    for subview in subviews {
      let idealSize = subview.sizeThatFits(.unspecified)
      let size = subview.sizeThatFits(
        ProposedViewSize(
          width: min(idealSize.width, availableWidth), height: nil
        ))
      if positionX > 0 && positionX + size.width > availableWidth {
        positionX = 0
        positionY += rowHeight + spacing
        rowHeight = 0
      }
      frames.append(CGRect(origin: CGPoint(x: positionX, y: positionY), size: size))
      contentWidth = max(contentWidth, positionX + size.width)
      positionX += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }

    return (CGSize(width: contentWidth, height: positionY + rowHeight), frames)
  }
}
