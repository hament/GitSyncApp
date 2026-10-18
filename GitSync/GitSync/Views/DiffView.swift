import SwiftUI

struct DiffView: View {
    var model: AppModel

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
    }

    @ViewBuilder
    private var content: some View {
        if model.diffTitle.isEmpty {
            emptyState("选择一个文件查看差异", systemImage: "doc.text.magnifyingglass")
        } else if model.diff.isBinary {
            emptyState("二进制文件，不显示差异", systemImage: "doc.zipper")
        } else if model.diff.lines.isEmpty {
            emptyState("没有差异", systemImage: "checkmark.circle")
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.diff.truncated {
                        Text("差异过长，已截断")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    ForEach(Array(model.diff.lines.enumerated()), id: \.offset) { index, line in
                        diffRow(line, index: index)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var fileHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text((model.diffTitle as NSString).lastPathComponent)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                let directory = (model.diffTitle as NSString).deletingLastPathComponent
                if !directory.isEmpty {
                    Text(directory)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            Text(model.mode == .history ? "提交差异" : "工作区差异")
                .font(.caption)
                .foregroundStyle(.secondary)

            changeBadge("+\(model.diff.additionCount)", color: .green)
            changeBadge("−\(model.diff.deletionCount)", color: .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.025))
    }

    private func diffRow(_ line: DiffLine, index: Int) -> some View {
        Group {
            if line.kind == .hunk {
                HStack(spacing: 0) {
                    lineNumber(nil)
                    lineNumber(nil)
                    Text(line.text)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                        .padding(.leading, 10)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 0) {
                    lineNumber(line.oldLineNumber)
                    lineNumber(line.newLineNumber)

                    Text(marker(line))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(foreground(line.kind))
                        .frame(width: 24, alignment: .center)

                    Text(contentText(line))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(foreground(line.kind))
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)

                    Spacer(minLength: 16)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 22, alignment: .leading)
        .background(background(line.kind))
        .overlay(alignment: .bottom) {
            if line.kind == .hunk {
                Rectangle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(height: 1)
            }
        }
        .accessibilityLabel("第 \(index + 1) 行，\(line.text)")
    }

    private func lineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 46, height: 22, alignment: .trailing)
            .padding(.trailing, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
            }
    }

    private func marker(_ line: DiffLine) -> String {
        switch line.kind {
        case .add: "+"
        case .delete: "−"
        case .hunk, .context: ""
        }
    }

    private func contentText(_ line: DiffLine) -> String {
        guard line.kind != .hunk, !line.text.hasPrefix("\\") else { return line.text }
        if line.text.first == "+" || line.text.first == "-" || line.text.first == " " {
            let content = String(line.text.dropFirst())
            return content.isEmpty ? " " : content
        }
        return line.text.isEmpty ? " " : line.text
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

    private func foreground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .add: Color(nsColor: .systemGreen)
        case .delete: Color(nsColor: .systemRed)
        case .hunk: .blue
        case .context: .primary
        }
    }

    private func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .add: Color.green.opacity(0.13)
        case .delete: Color.red.opacity(0.11)
        case .hunk: Color.blue.opacity(0.08)
        case .context: .clear
        }
    }
}
