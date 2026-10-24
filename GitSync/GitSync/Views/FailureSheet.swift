import AppKit
import SwiftUI

struct FailureSheet: View {
    let report: FailureReport
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.title.localized)
                .font(.headline)
            Text(report.reason.localized)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(report.log.localized)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.12))
            }
            HStack {
                Button {
                    let text = [report.title.localized, report.reason.localized, report.log.localized]
                        .joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label(L10n.text("复制报告", "Copy Report"), systemImage: "doc.on.doc")
                }
                Spacer()
                Button(L10n.text("好", "OK"), action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 460)
    }
}
