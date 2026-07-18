import AppKit
import Foundation

// MARK: - 剪贴板内容类型

/// 剪贴板内容类型
enum ClipboardContentType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case link = "link"
    case color = "color"
    case file = "file"

    var displayName: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文档"
        case .link: return "链接"
        case .color: return "颜色"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .link: return "link"
        case .color: return "paintpalette"
        }
    }
}

// MARK: - 剪贴板项目

/// 剪贴板项目
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let contentType: ClipboardContentType
    let createdAt: Date
    var isPinned: Bool

    // 文本内容（文本、链接）
    var textContent: String?

    // 富文本格式数据
    var rtfData: Data?
    var htmlData: Data?

    // 图片数据（PNG 格式存储，不保存到 JSON，单独存储）
    var imageData: Data?

    // 文件路径
    var filePaths: [String]?

    // 颜色值（十六进制格式）
    var colorHex: String?

    // 来源应用信息
    var sourceAppBundleId: String?
    var sourceAppName: String?

    // 数据大小（字节）
    var dataSize: Int64

    // MARK: - CodingKeys（排除 imageData，单独存储）

    enum CodingKeys: String, CodingKey {
        case id, contentType, createdAt, isPinned
        case textContent, rtfData, htmlData, filePaths, colorHex
        case sourceAppBundleId, sourceAppName, dataSize
    }

    // MARK: - 初始化

    init(
        id: UUID = UUID(),
        contentType: ClipboardContentType,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        textContent: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageData: Data? = nil,
        filePaths: [String]? = nil,
        colorHex: String? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.textContent = textContent
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageData = imageData
        self.filePaths = filePaths
        self.colorHex = colorHex
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName

        // 计算数据大小
        var size: Int64 = 0
        if let text = textContent {
            size += Int64(text.utf8.count)
        }
        if let rtf = rtfData {
            size += Int64(rtf.count)
        }
        if let html = htmlData {
            size += Int64(html.count)
        }
        if let data = imageData {
            size += Int64(data.count)
        }
        if let paths = filePaths {
            size += Int64(paths.joined(separator: "\n").utf8.count)
        }
        self.dataSize = size
    }

    // MARK: - 显示相关

    /// 显示标题（用于列表）
    var displayTitle: String {
        switch contentType {
        case .text:
            // 移除多余空白，最多显示 100 个字符
            let cleaned =
                textContent?
                .replacingOccurrences(
                    of: "\\s+", with: " ", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if cleaned.count > 100 {
                return String(cleaned.prefix(100)) + "..."
            }
            return cleaned
        case .image:
            // 启动后图片可能尚未加载到内存，使用持久化的数据大小展示。
            if dataSize > 0 {
                return
                    "图片 (\(ByteCountFormatter.string(fromByteCount: dataSize, countStyle: .file)))"
            }
            return "图片"
        case .file:
            if let paths = filePaths, paths.count == 1 {
                return URL(fileURLWithPath: paths[0]).lastPathComponent
            } else if let paths = filePaths {
                return "\(paths.count) 个文件"
            }
            return "文件"
        case .link:
            return textContent ?? ""
        case .color:
            return colorHex ?? ""
        }
    }

    /// 显示副标题
    var displaySubtitle: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        let timeStr = formatter.localizedString(for: createdAt, relativeTo: Date())

        if let appName = sourceAppName {
            return "\(timeStr) · \(appName)"
        }
        return timeStr
    }

    /// 格式化的数据大小
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: dataSize, countStyle: .file)
    }

    /// 获取图标
    var icon: NSImage {
        switch contentType {
        case .text:
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: "文本")
                ?? NSImage()
        case .image:
            // 列表小图标统一用通用 photo 图标；实际图片预览由 UI 层通过
            // ClipboardService.imageData(for:) 按需懒加载，避免历史图片常驻内存。
            return NSImage(systemSymbolName: "photo", accessibilityDescription: "图片") ?? NSImage()
        case .file:
            // 如果是单个文件，返回文件图标
            if let paths = filePaths, paths.count == 1 {
                return NSWorkspace.shared.icon(forFile: paths[0])
            }
            return NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "文件")
                ?? NSImage()
        case .link:
            return NSImage(systemSymbolName: "link", accessibilityDescription: "链接") ?? NSImage()
        case .color:
            // 创建颜色图标
            if let hex = colorHex, let color = NSColor(hex: hex) {
                let image = NSImage(size: NSSize(width: 16, height: 16))
                image.lockFocus()
                color.drawSwatch(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                image.unlockFocus()
                return image
            }
            return NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "颜色")
                ?? NSImage()
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - NSColor 扩展（十六进制支持）

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        switch hexSanitized.count {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF00_0000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF_0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000_FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x0000_00FF) / 255.0
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - 剪贴板设置相关枚举

/// 鼠标点击粘贴方式
enum ClipboardClickMode: String, Codable, CaseIterable {
    case doubleClick = "double"
    case singleClick = "single"

    var displayName: String {
        switch self {
        case .doubleClick: return "双击"
        case .singleClick: return "单击"
        }
    }
}

/// 记录保留条数
enum ClipboardHistoryLimit: Int, Codable, CaseIterable {
    case limit100 = 100
    case limit200 = 200
    case limit400 = 400
    case limit800 = 800
    case unlimited = -1

    var displayName: String {
        if self == .unlimited {
            return "无限制"
        }
        return "\(rawValue)"
    }
}

/// 记录保留时长
enum ClipboardRetentionDays: Int, Codable, CaseIterable {
    case days7 = 7
    case days30 = 30
    case forever = -1

    var displayName: String {
        switch self {
        case .days7: return "7 天"
        case .days30: return "30 天"
        case .forever: return "永久"
        }
    }
}

/// 容量限制
enum ClipboardCapacityLimit: Int64, Codable, CaseIterable {
    case gb2 = 2_147_483_648  // 2GB
    case gb4 = 4_294_967_296  // 4GB

    var displayName: String {
        switch self {
        case .gb2: return "2 GB"
        case .gb4: return "4 GB"
        }
    }
}

// MARK: - 剪贴板设置

/// 剪贴板设置
struct ClipboardSettings: Codable {
    var isEnabled: Bool
    var alias: String
    var hotKeyCode: UInt32
    var hotKeyModifiers: UInt32
    var plainTextHotKeyCode: UInt32
    var plainTextHotKeyModifiers: UInt32
    var clickMode: ClipboardClickMode
    var historyLimit: ClipboardHistoryLimit
    var retentionDays: ClipboardRetentionDays
    var capacityLimit: ClipboardCapacityLimit
    var ignoredAppBundleIds: [String]

    // 面板尺寸（用户可拖拽调整）
    var panelWidth: CGFloat
    var panelHeight: CGFloat

    static let `default` = ClipboardSettings(
        isEnabled: true,
        alias: "cb",
        hotKeyCode: 0,
        hotKeyModifiers: 0,
        plainTextHotKeyCode: 0,
        plainTextHotKeyModifiers: 0,
        clickMode: .doubleClick,
        historyLimit: .limit200,
        retentionDays: .days30,
        capacityLimit: .gb2,
        ignoredAppBundleIds: [
            "com.apple.keychainaccess",  // 钥匙串访问
            "com.apple.Passwords",  // 密码 app
        ],
        panelWidth: 400,
        panelHeight: 500
    )

    static func load() -> ClipboardSettings {
        if let data = UserDefaults.standard.data(forKey: "clipboardSettings"),
            let settings = try? JSONDecoder().decode(ClipboardSettings.self, from: data)
        {
            return settings
        }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "clipboardSettings")
        }
    }
}
