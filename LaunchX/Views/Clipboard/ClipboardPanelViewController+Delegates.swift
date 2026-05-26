import Cocoa

// MARK: - NSTextFieldDelegate

extension ClipboardPanelViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // 处理搜索框中的特殊按键
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
        -> Bool
    {
        // Escape: 关闭面板
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            ClipboardPanelManager.shared.forceHidePanel()
            return true
        }

        // 上箭头: 向上移动
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(by: -1)
            return true
        }

        // 下箭头: 向下移动
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(by: 1)
            return true
        }

        // Return: 粘贴
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let selectedRow = tableView.selectedRowIndexes.first,
                selectedRow < filteredItems.count
            {
                let item = filteredItems[selectedRow]
                pasteItem(item)
                return true
            }
        }

        return false
    }
}

// MARK: - ClipboardSearchFieldNavigationDelegate

extension ClipboardPanelViewController: ClipboardSearchFieldNavigationDelegate {
    func searchFieldDidPressUpArrow() {
        moveSelection(by: -1)
    }

    func searchFieldDidPressDownArrow() {
        moveSelection(by: 1)
    }

    func searchFieldDidPressControlP() {
        moveSelection(by: -1)
    }

    func searchFieldDidPressControlN() {
        moveSelection(by: 1)
    }

    func searchFieldDidPressReturn(withCommand: Bool) {
        guard let selectedRow = tableView.selectedRowIndexes.first,
            selectedRow < filteredItems.count
        else { return }

        let item = filteredItems[selectedRow]

        if withCommand {
            pasteItemAsPlainText(item)
        } else {
            pasteItem(item)
        }
    }

    func searchFieldDidPressEscape() {
        ClipboardPanelManager.shared.forceHidePanel()
    }

    func searchFieldDidSelectFilter(at index: Int) {
        let targetTag = index == 0 ? -1 : index - 1
        if let item = filterMenu.items.first(where: { $0.tag == targetTag }) {
            selectFilter(item)
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension ClipboardPanelViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        guard row < filteredItems.count else { return nil }

        let item = filteredItems[row]

        // 创建或复用单元格
        let cellIdentifier = NSUserInterfaceItemIdentifier("ClipboardCell")
        var cell =
            tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? ClipboardCellView

        if cell == nil {
            cell = ClipboardCellView()
            cell?.identifier = cellIdentifier
        }

        cell?.configure(with: item)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < filteredItems.count else { return rowHeight }

        let item = filteredItems[row]

        // 5行文字高度: 5 * 17 (13pt字体 + 行间距) + 16 (上下各8pt padding) = 101
        let maxMultilineHeight: CGFloat = 101

        // 图片类型根据实际图片尺寸计算高度
        if item.contentType == .image {
            if let data = ClipboardService.shared.imageData(for: item),
                let image = NSImage(data: data)
            {
                // 图片预览最大宽度200，最小宽度50
                let maxPreviewWidth: CGFloat = 200
                let aspectRatio = image.size.width / max(image.size.height, 1)

                // 计算图片预览的实际尺寸
                // 如果图片很宽（宽高比 > 1），宽度受限，高度较小
                // 如果图片很高（宽高比 < 1），高度受限于 maxMultilineHeight - padding
                let maxImageHeight: CGFloat = 85  // 最大图片高度
                let imageWidth = min(maxImageHeight * aspectRatio, maxPreviewWidth)
                let imageHeight = imageWidth / max(aspectRatio, 0.1)

                // 行高 = 图片高度 + 上下 padding (8pt each)
                let height = min(imageHeight, maxImageHeight) + 16
                return max(rowHeight, height)
            }
            return maxMultilineHeight
        }

        // 文本类型根据内容计算高度
        if item.contentType == .text || item.contentType == .link {
            if let text = item.textContent {
                // 计算实际显示行数（考虑换行符和长文本自动换行）
                let newlineCount = text.components(separatedBy: .newlines).count

                // 估算每行可显示的字符数（假设平均每字符约8pt宽度，可用宽度约350pt）
                let charsPerLine = 44
                let estimatedLines = max(
                    newlineCount, (text.count + charsPerLine - 1) / charsPerLine)
                let lineCount = min(estimatedLines, 5)

                if lineCount > 1 {
                    // 每行约 17pt (13pt 字体 + 行间距)，上下各 8pt padding
                    let height = CGFloat(lineCount) * 17 + 16
                    return max(rowHeight, min(height, maxMultilineHeight))
                }
            }
        }

        return rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // 使用自定义 rowView，始终保持蓝色高亮（即使窗口不是 key window）
        let rowView = EmphasizedTableRowView()
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatusLabel()

        // 注意：单击模式的粘贴由 tableView 的 action 处理，而不是 selectionDidChange
        // 这样可以避免键盘导航时意外触发粘贴
    }
}
