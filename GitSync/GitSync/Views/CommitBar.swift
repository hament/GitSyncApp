import AppKit
import SwiftUI

struct CommitBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.mergeInProgress ? L10n.text("合并提交说明", "Merge commit message") : L10n.text("提交说明", "Commit message"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.text("Shift + Enter 换行 · ⌘ Enter 提交", "Shift + Enter for a new line · ⌘ Enter to commit"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                CommitMessageTextView(text: $model.commitMessage) {
                    guard model.canCommit else { return }
                    Task { await model.commit() }
                }

                if model.commitMessage.isEmpty {
                    Text(L10n.text("输入本次提交说明…", "Enter a commit message…"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 62, maxHeight: 110)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            }

            HStack {
                Text(L10n.text("已选择 \(model.checkedCount) 个文件", "\(model.checkedCount) files selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.mergeInProgress ? L10n.text("完成合并", "Complete Merge") : L10n.text("提交 \(model.checkedCount) 个文件", "Commit \(model.checkedCount) Files")) {
                    Task { await model.commit() }
                }
                .disabled(!model.canCommit)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CommitMessageTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = CommitNSTextView()
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.string = text
        textView.setAccessibilityLabel(L10n.text("提交说明", "Commit message"))
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 7, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? CommitNSTextView else { return }
        textView.onCommit = onCommit
        textView.setAccessibilityLabel(L10n.text("提交说明", "Commit message"))
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(
                NSRange(
                    location: min(selection.location, (text as NSString).length),
                    length: 0
                )
            )
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class CommitNSTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76

        if isReturn, flags.contains(.command) {
            onCommit?()
            return
        }
        if isReturn, flags.contains(.shift) {
            insertNewline(nil)
            return
        }
        super.keyDown(with: event)
    }
}
