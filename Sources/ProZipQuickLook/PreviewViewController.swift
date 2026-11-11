import AppKit
import Foundation
import QuickLookUI

@MainActor
public final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController, NSTableViewDataSource, NSTableViewDelegate {
    private let nameLabel = NSTextField(labelWithString: "归档预览")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "正在读取归档目录…")
    private let table = NSTableView()
    private var entries: [ArchivePreviewEntry] = []
    private var sourceURL: URL?
    private var requestID = UUID()
    private var previewTask: Task<Void, Never>?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public override func loadView() {
        preferredContentSize = NSSize(width: 640, height: 440)
        let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let icon = NSImageView()
        if let url = Bundle(for: Self.self).url(forResource: "AppIcon-Preview", withExtension: "png") { icon.image = NSImage(contentsOf: url) }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("ProZip")
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [nameLabel, sizeLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 4
        let open = NSButton(title: "在 ProZip 中打开", target: self, action: #selector(openInProZip))
        open.bezelStyle = .rounded
        open.contentTintColor = NSColor(srgbRed: 0.35, green: 0.62, blue: 0.02, alpha: 1)
        let header = NSStackView(views: [icon, identity, open])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let columns: [(String, String, CGFloat)] = [("name", "名称", 350), ("size", "大小", 100), ("date", "修改日期", 150)]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 140 : 70
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.frame = NSRect(x: 0, y: 0, width: 608, height: 0)
        table.autoresizingMask = [.width]
        table.rowHeight = 26
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel("归档目录")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.borderType = .bezelBorder
        let stack = NSStackView(views: [header, statusLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        view = root
    }

    public func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()
        requestID = UUID()
        let request = requestID
        _ = view
        sourceURL = url
        entries = []
        table.reloadData()
        nameLabel.stringValue = url.lastPathComponent
        sizeLabel.stringValue = ""
        statusLabel.stringValue = "正在读取归档目录…"
        previewTask = Task.detached(priority: .userInitiated) { [weak self] in
            let listing = ArchivePreviewReader.read(url)
            await MainActor.run { [weak self] in
                guard let self, self.requestID == request, listing.status != .cancelled else {
                    handler(CocoaError(.userCancelled))
                    return
                }
                self.previewTask = nil
                self.entries = listing.entries
                self.nameLabel.stringValue = listing.archiveName
                self.sizeLabel.stringValue = listing.sourceSize.map { "本机文件 · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "无法读取本机文件大小"
                self.statusLabel.stringValue = listing.status.message(visibleCount: listing.entries.count)
                self.table.reloadData()
                handler(nil)
            }
        }
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        requestID = UUID()
        previewTask?.cancel()
        previewTask = nil
    }

    @objc private func openInProZip() {
        guard let sourceURL, let url = ArchivePreviewReader.mainAppURL(for: sourceURL), let context = extensionContext else {
            statusLabel.stringValue = "请使用 ProZip 主应用打开此归档。"
            return
        }
        context.open(url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.statusLabel.stringValue = "无法从快速预览打开 ProZip，请在主应用中打开此归档。" }
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "name":
            let suffix: String
            switch entry.kind {
            case .symbolicLink: suffix = "  ↗ 符号链接"
            case .hardLink: suffix = "  ↗ 硬链接"
            case .special: suffix = "  特殊文件"
            default: suffix = ""
            }
            value = entry.path.replacingOccurrences(of: "\n", with: "↵").replacingOccurrences(of: "\r", with: "␍").replacingOccurrences(of: "\t", with: "⇥") + suffix
        case "size": value = entry.kind == .directory ? "—" : entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        case "date": value = entry.modifiedAt.map(dateFormatter.string(from:)) ?? "—"
        default: return nil
        }
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.setAccessibilityLabel(value)
        return label
    }

    deinit { previewTask?.cancel() }
}
