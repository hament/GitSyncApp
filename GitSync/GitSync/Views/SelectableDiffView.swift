import AppKit
import SwiftUI

struct DiffTextRow {
    var text: String
    var kind: DiffLineKind?
    var oldNumber: Int?
    var newNumber: Int?

    init(_ line: DiffLine?, oldSide: Bool? = nil) {
        kind = line?.kind
        oldNumber = oldSide == false ? nil : line?.oldLineNumber
        newNumber = oldSide == true ? nil : line?.newLineNumber
        guard let line else {
            text = ""
            return
        }
        if line.kind != .hunk, !line.text.hasPrefix("\\"),
           let first = line.text.first, first == "+" || first == "-" || first == " " {
            text = String(line.text.dropFirst())
        } else {
            text = line.text
        }
    }
}

struct SelectableDiffView: NSViewRepresentable {
    var document: DiffDocument
    var mode: DiffLayoutMode
    var identity: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.distribution = .fillEqually
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.document != document || coordinator.mode != mode || coordinator.identity != identity else { return }
        let resetPosition = coordinator.mode != mode || coordinator.identity != identity
        coordinator.document = document
        coordinator.mode = mode
        coordinator.identity = identity
        let columns: [[DiffTextRow]]
        if mode == .unified {
            columns = [document.lines.map { DiffTextRow($0) }]
        } else {
            let rows = document.splitRows
            columns = [true, false].map { oldSide in
                rows.map { row in
                    switch row {
                    case .hunk(let text):
                        return DiffTextRow(DiffLine(kind: .hunk, text: text), oldSide: oldSide)
                    case .lines(let old, let new):
                        return DiffTextRow(oldSide ? old : new, oldSide: oldSide)
                    }
                }
            }
        }
        if stack.arrangedSubviews.count != columns.count {
            coordinator.stopObserving()
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for _ in columns {
                let scroll = DiffScrollView()
                scroll.hasVerticalScroller = true
                scroll.hasHorizontalScroller = true
                scroll.autohidesScrollers = true
                scroll.borderType = .noBorder
                let text = DiffTextView(frame: .zero)
                text.isEditable = false
                text.isSelectable = true
                text.isRichText = false
                text.allowsUndo = false
                text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                text.isHorizontallyResizable = true
                text.isVerticallyResizable = true
                text.textContainer?.widthTracksTextView = false
                text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                text.textContainer?.lineFragmentPadding = 0
                text.backgroundColor = .textBackgroundColor
                scroll.documentView = text
                stack.addArrangedSubview(scroll)
            }
            coordinator.observe(stack.arrangedSubviews.compactMap { $0 as? DiffScrollView })
        }
        for (view, rows) in zip(stack.arrangedSubviews, columns) {
            guard let scroll = view as? DiffScrollView,
                  let text = scroll.documentView as? DiffTextView else { continue }
            text.setRows(rows, unified: mode == .unified)
            scroll.tile()
            if resetPosition {
                text.setSelectedRange(NSRange(location: 0, length: 0))
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    final class Coordinator {
        var document: DiffDocument?
        var mode: DiffLayoutMode?
        var identity: String?
        private var observers: [NSObjectProtocol] = []
        private var syncing = false

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        func observe(_ scrolls: [DiffScrollView]) {
            for source in scrolls {
                source.contentView.postsBoundsChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: source.contentView,
                    queue: .main
                ) { [weak self, weak source] _ in
                    MainActor.assumeIsolated {
                        guard let self, let source, !self.syncing else { return }
                        self.syncing = true
                        defer { self.syncing = false }
                        for target in scrolls where target !== source {
                            let position = NSPoint(x: target.contentView.bounds.minX, y: source.contentView.bounds.minY)
                            target.contentView.scroll(to: position)
                            target.reflectScrolledClipView(target.contentView)
                        }
                    }
                })
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

final class DiffScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let text = documentView as? DiffTextView else { return }
        text.setFrameSize(NSSize(
            width: max(contentSize.width, text.contentWidth),
            height: max(contentSize.height, text.contentHeight)
        ))
    }
}

final class DiffTextView: NSTextView {
    private var rows: [DiffTextRow] = []
    private var unified = true
    private let rowHeight: CGFloat = 22
    private var gutterWidth: CGFloat { unified ? 130 : 77 }
    private(set) var contentWidth: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0

    func setRows(_ rows: [DiffTextRow], unified: Bool) {
        let previousSelection = selectedRange()
        self.rows = rows
        self.unified = unified
        textContainerInset = NSSize(width: gutterWidth, height: 4)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = rowHeight
        paragraph.maximumLineHeight = rowHeight
        let content = NSMutableAttributedString(string: "")
        var widest: CGFloat = 0
        for (index, row) in rows.enumerated() {
            content.append(NSAttributedString(string: row.text + (index == rows.count - 1 ? "" : "\n"), attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: foreground(row.kind),
            ]))
            widest = max(widest, (row.text as NSString).size(withAttributes: [.font: font]).width)
        }
        textStorage?.setAttributedString(content)
        contentWidth = ceil(widest) + gutterWidth + 24
        contentHeight = CGFloat(rows.count) * rowHeight + 16
        let location = min(previousSelection.location, content.length)
        setSelectedRange(NSRange(location: location, length: min(previousSelection.length, content.length - location)))
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        backgroundColor.setFill()
        rect.fill()
        let start = max(0, Int(floor((rect.minY - textContainerInset.height) / rowHeight)))
        let end = min(rows.count, Int(ceil((rect.maxY - textContainerInset.height) / rowHeight)))
        guard start < end else { return }
        let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        for index in start..<end {
            let row = rows[index]
            let top = textContainerInset.height + CGFloat(index) * rowHeight
            let lineRect = NSRect(x: 0, y: top, width: bounds.width, height: rowHeight)
            background(row.kind).setFill()
            lineRect.fill()
            NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
            NSRect(x: 0, y: top, width: gutterWidth - 24, height: rowHeight).fill()
            let numbers = unified ? [row.oldNumber, row.newNumber] : [row.oldNumber ?? row.newNumber]
            for (column, number) in numbers.enumerated() {
                let label = number.map(String.init) ?? ""
                let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
                let width = (label as NSString).size(withAttributes: attributes).width
                (label as NSString).draw(at: NSPoint(x: CGFloat(column + 1) * 53 - 7 - width, y: top + 4), withAttributes: attributes)
            }
            let marker = row.kind == .add ? "+" : (row.kind == .delete ? "−" : "")
            (marker as NSString).draw(at: NSPoint(x: gutterWidth - 19, y: top + 4), withAttributes: [
                .font: numberFont, .foregroundColor: foreground(row.kind),
            ])
        }
    }

    private func foreground(_ kind: DiffLineKind?) -> NSColor {
        switch kind {
        case .add: .systemGreen
        case .delete: .systemRed
        case .hunk: .systemBlue
        default: .textColor
        }
    }

    private func background(_ kind: DiffLineKind?) -> NSColor {
        switch kind {
        case .add: NSColor.systemGreen.withAlphaComponent(0.13)
        case .delete: NSColor.systemRed.withAlphaComponent(0.11)
        case .hunk: NSColor.systemBlue.withAlphaComponent(0.08)
        default: .textBackgroundColor
        }
    }
}
