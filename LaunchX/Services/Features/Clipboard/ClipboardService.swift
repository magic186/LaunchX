import AppKit
import Combine
import Foundation

/// 剪贴板服务 - 负责剪贴板监听、内容解析、数据存储
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    // MARK: - Published 属性

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var totalSize: Int64 = 0

    // MARK: - 私有属性

    private var monitorTimer: Timer?
    private var saveTimer: Timer?  // 防抖动保存定时器
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    // 缓存 ClipboardSettings，避免每次轮询都从 UserDefaults 反序列化
    private var cachedSettings: ClipboardSettings = ClipboardSettings.load()
    private var settingsObserver: NSObjectProtocol?

    // 数据存储路径
    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let clipboardDir = appSupport.appendingPathComponent(
            "LaunchX/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: clipboardDir, withIntermediateDirectories: true)
        return clipboardDir
    }()

    private let itemsFileURL: URL
    private let imagesDir: URL

    private init() {
        self.itemsFileURL = storageURL.appendingPathComponent("items.json")
        self.imagesDir = storageURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        loadItems()

        // 监听设置变化，更新缓存
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cachedSettings = ClipboardSettings.load()
        }

        print("[ClipboardService] Initialized with \(items.count) items")
    }

    // MARK: - 监听控制

    /// 开始监听剪贴板变化
    func startMonitoring() {
        guard !isMonitoring else { return }

        guard cachedSettings.isEnabled else {
            print("[ClipboardService] Monitoring disabled in settings")
            return
        }

        lastChangeCount = pasteboard.changeCount

        // 使用 Timer 轮询检测剪贴板变化（0.5秒间隔，与 Alfred / Maccy 同级的即时响应）
        // macOS 的 NSPasteboard 不提供变更通知，只能轮询 changeCount；0.5s 是社区主流平衡点
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }
        // 加入 .common 模式，避免在拖拽 / 滚动面板等 modal 交互时轮询被暂停
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer

        isMonitoring = true
        print("[ClipboardService] Started monitoring")
    }

    /// 停止监听
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
        print("[ClipboardService] Stopped monitoring")
    }

    /// 重启监听（设置变化时调用）
    func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    // MARK: - 剪贴板检测

    private func checkClipboardChange() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 只检查用户配置的忽略列表中的应用
        if shouldIgnoreCurrentApp() {
            print("[ClipboardService] Ignored clipboard from excluded app")
            return
        }

        // 图片解析（PNG 重编码）移到后台线程，避免轮询时阻塞主线程
        if hasImageInClipboard() {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if let item = self?.parseClipboardContent() {
                    DispatchQueue.main.async {
                        self?.addItem(item)
                        print("[ClipboardService] Added new item: \(item.contentType.displayName)")
                    }
                }
            }
        } else {
            // 非图片内容在主线程直接解析（开销很小）
            if let item = parseClipboardContent() {
                addItem(item)
                print("[ClipboardService] Added new item: \(item.contentType.displayName)")
            }
        }
    }

    /// 快速检测剪贴板是否包含图片（不进行完整的图片解析）
    private func hasImageInClipboard() -> Bool {
        let types = pasteboard.types ?? []
        for type in types {
            let raw = type.rawValue.lowercased()
            if raw.contains("image") || raw.contains("png") || raw.contains("tiff")
                || raw.contains("jpeg") || raw.contains("heic")
            {
                return true
            }
        }
        return false
    }

    /// 检查是否应该忽略当前前台应用
    private func shouldIgnoreCurrentApp() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
            let bundleId = frontApp.bundleIdentifier
        else {
            return false
        }

        return cachedSettings.ignoredAppBundleIds.contains(bundleId)
    }

    /// 获取当前前台应用信息
    private func getCurrentAppInfo() -> (bundleId: String?, name: String?) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        return (frontApp.bundleIdentifier, frontApp.localizedName)
    }

    // MARK: - 内容解析

    private func parseClipboardContent() -> ClipboardItem? {
        let appInfo = getCurrentAppInfo()

        // 调试：打印剪贴板中的所有类型
        let types = pasteboard.types ?? []
        print("[ClipboardService] Available pasteboard types: \(types.map { $0.rawValue })")

        // 1. 检查文件（优先级最高）
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !fileURLs.isEmpty
        {
            // 检查是否是单个图片文件（微信等应用复制图片时会以文件形式放入剪贴板）
            let imageExtensions = [
                "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp",
            ]
            if fileURLs.count == 1,
                let fileURL = fileURLs.first,
                imageExtensions.contains(fileURL.pathExtension.lowercased()),
                let imageData = try? Data(contentsOf: fileURL),
                let image = NSImage(data: imageData)
            {
                print("[ClipboardService] Found image file from clipboard: \(fileURL.path)")
                // 转换为 PNG 格式存储
                if let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                {
                    return ClipboardItem(
                        contentType: .image,
                        imageData: pngData,
                        sourceAppBundleId: appInfo.bundleId,
                        sourceAppName: appInfo.name
                    )
                }
            }

            // 不是图片文件，按普通文件处理
            let paths = fileURLs.map { $0.path }
            return ClipboardItem(
                contentType: .file,
                filePaths: paths,
                sourceAppBundleId: appInfo.bundleId,
                sourceAppName: appInfo.name
            )
        }

        // 2. 检查图片（支持多种图片格式）
        // 尝试从多种常见的图片类型中读取
        var imageData: Data? = nil

        // 首先尝试直接读取常见的图片格式
        if let data = pasteboard.data(forType: .png) {
            print("[ClipboardService] Found PNG data")
            imageData = data
        } else if let data = pasteboard.data(forType: .tiff) {
            print("[ClipboardService] Found TIFF data")
            imageData = data
        } else if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            print("[ClipboardService] Found JPEG data")
            imageData = data
        } else if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            print("[ClipboardService] Found HEIC data")
            imageData = data
        }

        // 如果没有找到标准格式，尝试使用 NSImage 类从剪贴板读取图片
        // 这可以处理更多的图片格式，包括某些应用特殊的剪贴板格式
        if imageData == nil {
            if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)
                as? [NSImage],
                let image = images.first
            {
                print("[ClipboardService] Found image via NSImage class")
                if let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                {
                    imageData = pngData
                }
            }
        }

        // 最后尝试检查是否有任何图片相关的类型
        if imageData == nil {
            for type in types {
                let typeString = type.rawValue.lowercased()
                if typeString.contains("image") || typeString.contains("png")
                    || typeString.contains("tiff") || typeString.contains("jpeg")
                    || typeString.contains("jpg") || typeString.contains("heic")
                {
                    if let data = pasteboard.data(forType: type) {
                        print("[ClipboardService] Found image data for type: \(type.rawValue)")
                        // 尝试用 NSImage 解析
                        if let image = NSImage(data: data),
                            let tiffData = image.tiffRepresentation,
                            let bitmap = NSBitmapImageRep(data: tiffData),
                            let pngData = bitmap.representation(using: .png, properties: [:])
                        {
                            imageData = pngData
                            break
                        }
                    }
                }
            }
        }

        if let imageData = imageData {
            // 转换为 PNG 存储
            var pngData = imageData
            // 如果不是 PNG 格式，转换为 PNG
            if pasteboard.data(forType: .png) == nil {
                if let image = NSImage(data: imageData),
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let png = bitmap.representation(using: .png, properties: [:])
                {
                    pngData = png
                }
            }

            print("[ClipboardService] Successfully parsed image, size: \(pngData.count) bytes")

            return ClipboardItem(
                contentType: .image,
                imageData: pngData,
                sourceAppBundleId: appInfo.bundleId,
                sourceAppName: appInfo.name
            )
        }

        // 3. 检查 URL（http/https）
        if let urlString = pasteboard.string(forType: .URL) {
            return ClipboardItem(
                contentType: .link,
                textContent: urlString,
                sourceAppBundleId: appInfo.bundleId,
                sourceAppName: appInfo.name
            )
        }

        // 4. 检查普通文本
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // 检查是否为 URL
            if let url = URL(string: text),
                url.scheme == "http" || url.scheme == "https"
            {
                // 读取富文本格式数据
                let rtfData = pasteboard.data(forType: .rtf)
                let htmlData = pasteboard.data(forType: .html)

                return ClipboardItem(
                    contentType: .link,
                    textContent: text,
                    rtfData: rtfData,
                    htmlData: htmlData,
                    sourceAppBundleId: appInfo.bundleId,
                    sourceAppName: appInfo.name
                )
            }

            // 检查是否为颜色（十六进制格式）
            let colorPattern = "^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"
            if let regex = try? NSRegularExpression(pattern: colorPattern),
                regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            {
                let hex = text.hasPrefix("#") ? text : "#\(text)"
                return ClipboardItem(
                    contentType: .color,
                    colorHex: hex,
                    sourceAppBundleId: appInfo.bundleId,
                    sourceAppName: appInfo.name
                )
            }

            // 普通文本 - 读取富文本格式数据
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html)

            return ClipboardItem(
                contentType: .text,
                textContent: text,
                rtfData: rtfData,
                htmlData: htmlData,
                sourceAppBundleId: appInfo.bundleId,
                sourceAppName: appInfo.name
            )
        }

        return nil
    }

    // MARK: - 项目管理

    /// 添加新项目
    func addItem(_ item: ClipboardItem) {
        // 检查重复（相同内容不重复添加，但更新时间）
        if let existingIndex = findDuplicateIndex(for: item) {
            var existing = items[existingIndex]
            let existingDataSize = existing.dataSize
            // 创建新项目，更新时间和来源
            existing = ClipboardItem(
                id: existing.id,
                contentType: existing.contentType,
                createdAt: Date(),
                isPinned: existing.isPinned,
                textContent: existing.textContent,
                rtfData: item.rtfData ?? existing.rtfData,
                htmlData: item.htmlData ?? existing.htmlData,
                imageData: existing.imageData,
                filePaths: existing.filePaths,
                colorHex: existing.colorHex,
                sourceAppBundleId: item.sourceAppBundleId,
                sourceAppName: item.sourceAppName
            )
            if existing.contentType == .image {
                existing.dataSize = max(existingDataSize, item.dataSize)
            }
            items.remove(at: existingIndex)
            items.insert(existing, at: 0)
        } else {
            var itemToStore = item

            // 如果是图片，保存到磁盘
            if item.contentType == .image, let imageData = item.imageData {
                saveImageToDisk(id: item.id, data: imageData)
                itemToStore.imageData = nil
            }

            items.insert(itemToStore, at: 0)
        }

        // 执行清理策略
        applyRetentionPolicy()

        // 防抖动保存（延迟 2 秒）
        scheduleSave()
        updateTotalSize()

        // 发送通知
        NotificationCenter.default.post(
            name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
    }

    /// 查找重复项
    private func findDuplicateIndex(for item: ClipboardItem) -> Int? {
        return items.firstIndex { existing in
            switch (existing.contentType, item.contentType) {
            case (.text, .text), (.link, .link):
                return existing.textContent == item.textContent
            case (.color, .color):
                return existing.colorHex == item.colorHex
            case (.file, .file):
                return existing.filePaths == item.filePaths
            case (.image, .image):
                // 图片比较使用数据大小（简化处理）
                return existing.dataSize == item.dataSize
            default:
                return false
            }
        }
    }

    /// 删除项目
    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }

        // 删除图片文件
        if item.contentType == .image {
            deleteImageFromDisk(id: item.id)
        }

        scheduleSave()
        updateTotalSize()

        NotificationCenter.default.post(
            name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
    }

    /// 删除多个项目
    func removeItems(_ itemsToRemove: [ClipboardItem]) {
        for item in itemsToRemove {
            items.removeAll { $0.id == item.id }
            if item.contentType == .image {
                deleteImageFromDisk(id: item.id)
            }
        }

        scheduleSave()
        updateTotalSize()

        NotificationCenter.default.post(
            name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
    }

    /// 清空所有历史（保留固定项）
    func clearHistory() {
        let pinnedItems = items.filter { $0.isPinned }

        // 删除非固定项的图片
        for item in items where !item.isPinned && item.contentType == .image {
            deleteImageFromDisk(id: item.id)
        }

        items = pinnedItems
        scheduleSave()
        updateTotalSize()

        NotificationCenter.default.post(
            name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
    }

    /// 切换固定状态
    func togglePin(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isPinned.toggle()
            scheduleSave()

            NotificationCenter.default.post(
                name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
        }
    }

    // MARK: - 粘贴功能

    /// 复制指定项目到剪贴板（保持原始格式）
    func copyToClipboard(_ item: ClipboardItem) {
        writeToClipboard(item, asPlainText: false)
        moveItemToFront(item)
    }

    /// 复制为纯文本到剪贴板
    func copyAsPlainText(_ item: ClipboardItem) {
        writeToClipboard(item, asPlainText: true)
        moveItemToFront(item)
    }

    /// 将项目移到最前面（LRU行为）
    private func moveItemToFront(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        // 如果已经在最前面，不需要移动
        if index == 0 { return }

        // 移除原位置，插入到最前面
        var movedItem = items.remove(at: index)
        let dataSize = movedItem.dataSize
        // 更新时间
        movedItem = ClipboardItem(
            id: movedItem.id,
            contentType: movedItem.contentType,
            createdAt: Date(),
            isPinned: movedItem.isPinned,
            textContent: movedItem.textContent,
            rtfData: movedItem.rtfData,
            htmlData: movedItem.htmlData,
            imageData: movedItem.imageData,
            filePaths: movedItem.filePaths,
            colorHex: movedItem.colorHex,
            sourceAppBundleId: movedItem.sourceAppBundleId,
            sourceAppName: movedItem.sourceAppName
        )
        movedItem.dataSize = dataSize
        items.insert(movedItem, at: 0)

        // 防抖动保存并通知更新
        scheduleSave()
        NotificationCenter.default.post(
            name: NSNotification.Name("ClipboardItemsDidChange"), object: nil)
    }

    /// 粘贴指定项目（保持原始格式）
    func paste(_ item: ClipboardItem) {
        writeToClipboard(item, asPlainText: false)

        // 延迟执行粘贴，确保剪贴板写入完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.simulatePaste()
        }
    }

    /// 粘贴为纯文本
    func pasteAsPlainText(_ item: ClipboardItem) {
        writeToClipboard(item, asPlainText: true)

        // 延迟执行粘贴，确保剪贴板写入完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.simulatePaste()
        }
    }

    /// 写入剪贴板
    func writeToClipboard(_ item: ClipboardItem, asPlainText: Bool) {
        pasteboard.clearContents()

        switch item.contentType {
        case .text, .link:
            if let text = item.textContent {
                if asPlainText {
                    // 纯文本模式：只写入纯文本
                    pasteboard.setString(text, forType: .string)
                } else {
                    // 保留格式模式：按优先级写入多种格式
                    if let rtfData = item.rtfData {
                        pasteboard.setData(rtfData, forType: .rtf)
                    }
                    if let htmlData = item.htmlData {
                        pasteboard.setData(htmlData, forType: .html)
                    }
                    // 始终写入纯文本作为兜底
                    pasteboard.setString(text, forType: .string)
                }
            }
        case .color:
            if let hex = item.colorHex {
                pasteboard.setString(hex, forType: .string)
            }
        case .image:
            if asPlainText {
                // 纯文本模式下不粘贴图片
                return
            }
            if let data = imageData(for: item) {
                pasteboard.setData(data, forType: .png)
            }
        case .file:
            if asPlainText {
                // 纯文本模式粘贴文件路径
                if let paths = item.filePaths {
                    pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
                }
            } else {
                if let paths = item.filePaths {
                    let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                    pasteboard.writeObjects(urls)
                }
            }
        }

        // 更新 changeCount 避免重复记录
        lastChangeCount = pasteboard.changeCount
    }

    /// 模拟 Cmd+V 粘贴（公开方法）
    func simulatePasteCommand() {
        simulatePaste()
    }

    /// 同步 lastChangeCount 到当前剪贴板状态（避免监控逻辑重复记录）
    func syncChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    /// 模拟 Cmd+V 粘贴
    private func simulatePaste() {
        // 使用 combinedSessionState 而不是 hidSystemState，更适合模拟用户输入
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V key
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }

    // MARK: - 搜索

    /// 搜索剪贴板历史
    func search(query: String, filter: ClipboardContentType? = nil) -> [ClipboardItem] {
        var results = items

        // 类型过滤
        if let filter = filter {
            results = results.filter { $0.contentType == filter }
        }

        // 关键词搜索
        if !query.isEmpty {
            let lowercased = query.lowercased()
            results = results.filter { item in
                switch item.contentType {
                case .text, .link:
                    return item.textContent?.lowercased().contains(lowercased) ?? false
                case .color:
                    return item.colorHex?.lowercased().contains(lowercased) ?? false
                case .file:
                    return item.filePaths?.contains { $0.lowercased().contains(lowercased) }
                        ?? false
                case .image:
                    return false  // 图片不支持文本搜索
                }
            }
        }

        return results
    }

    // MARK: - 清理策略

    private func applyRetentionPolicy() {
        let settings = cachedSettings

        // 1. 时间限制
        if settings.retentionDays != .forever {
            let cutoffDate = Calendar.current.date(
                byAdding: .day, value: -settings.retentionDays.rawValue, to: Date())!
            let expiredItems = items.filter { !$0.isPinned && $0.createdAt < cutoffDate }
            for item in expiredItems {
                items.removeAll { $0.id == item.id }
                if item.contentType == .image {
                    deleteImageFromDisk(id: item.id)
                }
            }
        }

        // 2. 条数限制
        if settings.historyLimit != .unlimited {
            let limit = settings.historyLimit.rawValue
            let nonPinnedItems = items.filter { !$0.isPinned }

            if nonPinnedItems.count > limit {
                let itemsToRemove = Array(nonPinnedItems.suffix(nonPinnedItems.count - limit))
                for item in itemsToRemove {
                    items.removeAll { $0.id == item.id }
                    if item.contentType == .image {
                        deleteImageFromDisk(id: item.id)
                    }
                }
            }
        }

        // 3. 容量限制
        updateTotalSize()
        while totalSize > settings.capacityLimit.rawValue {
            // 删除最旧的非固定项
            if let oldest = items.last(where: { !$0.isPinned }) {
                items.removeAll { $0.id == oldest.id }
                if oldest.contentType == .image {
                    deleteImageFromDisk(id: oldest.id)
                }
                updateTotalSize()
            } else {
                break
            }
        }
    }

    // MARK: - 持久化

    /// 防抖动保存：延迟后保存，合并多次操作
    ///
    /// **磁盘写入优化的核心功能**
    ///
    /// ## 原理
    /// 使用 Timer 延迟保存机制，将短时间内的多次保存操作合并为一次。
    /// 每次调用时取消之前的定时器，重新设置延迟，确保只有在操作停止后才真正保存。
    ///
    /// ## 优化效果
    /// - 减少磁盘写入频率：从每次操作都保存，降低到每 2 秒最多保存一次
    /// - 降低 I/O 开销：合并多次写入，减少文件系统调用
    /// - 预期效果：剪贴板写入量降低 80-90%
    ///
    /// ## 权衡
    /// - **数据延迟**：最多延迟 2 秒保存数据
    /// - **崩溃风险**：应用崩溃可能丢失最后 2 秒的数据
    /// - **缓解措施**：
    ///   - 应用进入后台时立即保存（applicationDidResignActive）
    ///   - 应用终止前立即保存（applicationWillTerminate）
    ///   - 系统休眠前立即保存（NSWorkspace.willSleepNotification）
    ///
    /// ## 配置
    /// 可通过 `DiskWriteOptimizationSettings.debounceClipboardSaveEnabled` 开关控制
    ///
    private func scheduleSave() {
        let optimizationSettings = DiskWriteOptimizationSettings.shared

        // 如果防抖动功能被禁用，立即保存
        guard optimizationSettings.debounceClipboardSaveEnabled else {
            saveItems()
            return
        }

        // 取消之前的定时器
        saveTimer?.invalidate()

        // 创建新的延迟保存定时器
        let interval = optimizationSettings.clipboardDebounceInterval
        saveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
            [weak self] _ in
            self?.saveItems()
        }
    }

    /// 立即保存（用于应用进入后台或终止前）
    /// 外部可访问，供 AppDelegate 调用
    func saveImmediately() {
        // 取消待执行的延迟保存
        saveTimer?.invalidate()
        saveTimer = nil

        // 立即保存数据
        saveItems()
    }

    private func loadItems() {
        guard let data = try? Data(contentsOf: itemsFileURL),
            let loadedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else {
            return
        }

        // 不再在启动时全量加载所有历史图片的 PNG 到内存。
        // 图片改为按需读取：显示/粘贴时通过 imageData(for:) 经 NSCache → 磁盘懒加载。
        items = loadedItems
        updateTotalSize()
    }

    private func saveItems() {
        // 保存时不包含图片数据（图片单独存储）
        var itemsToSave = items
        for i in 0..<itemsToSave.count {
            if itemsToSave[i].contentType == .image {
                itemsToSave[i].imageData = nil
            }
        }

        if let data = try? JSONEncoder().encode(itemsToSave) {
            try? data.write(to: itemsFileURL)

            // 记录磁盘写入量（磁盘写入优化：监控）
            DiskWriteMonitor.shared.recordWrite(bytes: Int64(data.count))
        }
    }

    private func saveImageToDisk(id: UUID, data: Data) {
        let imageURL = imagesDir.appendingPathComponent("\(id.uuidString).png")
        try? data.write(to: imageURL)
    }

    private func loadImageFromDisk(id: UUID) -> Data? {
        let imageURL = imagesDir.appendingPathComponent("\(id.uuidString).png")
        return try? Data(contentsOf: imageURL)
    }

    // MARK: - 图片懒加载（避免历史图片 PNG 全量常驻内存）

    /// 剪贴板图片内存缓存（有界，系统内存压力时自动淘汰）。
    private lazy var imageCache: NSCache<NSUUID, NSData> = {
        let cache = NSCache<NSUUID, NSData>()
        cache.countLimit = 30  // 最多缓存 30 张图的解码数据
        return cache
    }()

    /// 按需获取剪贴板图片数据：内存(item.imageData，刚复制的新图) → NSCache → 磁盘，读后缓存。
    /// 取代过去 loadItems 时全量预加载所有历史图片到内存的做法（曾造成大量内存常驻）。
    func imageData(for item: ClipboardItem) -> Data? {
        guard item.contentType == .image else { return nil }
        if let data = item.imageData { return data }  // 刚复制的新图仍持有数据
        let key = item.id as NSUUID
        if let cached = imageCache.object(forKey: key) {
            return cached as Data
        }
        if let data = loadImageFromDisk(id: item.id) {
            imageCache.setObject(data as NSData, forKey: key)
            return data
        }
        return nil
    }

    private func deleteImageFromDisk(id: UUID) {
        let imageURL = imagesDir.appendingPathComponent("\(id.uuidString).png")
        try? FileManager.default.removeItem(at: imageURL)
        imageCache.removeObject(forKey: id as NSUUID)  // 同步清理内存缓存
    }

    private func updateTotalSize() {
        totalSize = items.reduce(0) { $0 + $1.dataSize }
    }

    // MARK: - 统计信息

    /// 获取各类型的数量
    func getTypeCounts() -> [ClipboardContentType: Int] {
        var counts: [ClipboardContentType: Int] = [:]
        for type in ClipboardContentType.allCases {
            counts[type] = items.filter { $0.contentType == type }.count
        }
        return counts
    }
}
