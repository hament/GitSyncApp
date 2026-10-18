import SwiftUI

struct DiffView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.diffTitle.isEmpty {
                Text(model.diffTitle)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
            Text("选择一个文件查看差异")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.diff.isBinary {
            Text("二进制文件，不显示差异")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.diff.lines.isEmpty {
            Text("没有差异")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    ForEach(Array(model.diff.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(foreground(line.kind))
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(line.kind))
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func foreground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .add: Color(red: 0.0, green: 0.38, blue: 0.12)
        case .delete: Color(red: 0.62, green: 0.08, blue: 0.08)
        case .hunk: .secondary
        case .context: .primary
        }
    }

    private func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .add: Color.green.opacity(0.16)
        case .delete: Color.red.opacity(0.14)
        case .hunk: Color.primary.opacity(0.04)
        case .context: .clear
        }
    }
}
