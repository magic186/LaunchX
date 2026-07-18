import Foundation

// MARK: - Context Prompt 分类

/// 上下文预设分类
enum ContextPromptCategory: String, Codable, CaseIterable {
    case general
    case coding
    case review
    case communication
    case expert

    var displayName: String {
        switch self {
        case .general: return "通用"
        case .coding: return "编码"
        case .review: return "代码审查"
        case .communication: return "沟通"
        case .expert: return "专家"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "text.bubble"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .review: return "checkmark.seal"
        case .communication: return "person.2"
        case .expert: return "graduationcap"
        }
    }
}

// MARK: - Context Prompt

/// 全局上下文提示词（Context Prompt）数据模型
/// 对齐 ClaudeProvider 的设计范式，复用 AppTarget 跨应用机制
struct ContextPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String           // Markdown 格式的全局上下文提示词正文
    var apps: Set<AppTarget>      // 适用应用（.claude 和/或 .codex）
    var category: ContextPromptCategory
    var icon: String?
    var iconColor: String?
    var isCurrent: Bool
    var createdAt: Date
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        content: String = "",
        apps: Set<AppTarget> = [.claude],
        category: ContextPromptCategory = .general,
        icon: String? = nil,
        iconColor: String? = nil,
        isCurrent: Bool = false,
        createdAt: Date = Date(),
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.apps = apps
        self.category = category
        self.icon = icon
        self.iconColor = iconColor
        self.isCurrent = isCurrent
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, content, apps, category, icon, iconColor, isCurrent, createdAt, sortIndex
    }

    // 向后兼容：apps 字段缺失时默认为 [.claude]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        apps = (try? container.decode(Set<AppTarget>.self, forKey: .apps)) ?? [.claude]
        category = (try? container.decode(ContextPromptCategory.self, forKey: .category)) ?? .general
        icon = try? container.decodeIfPresent(String.self, forKey: .icon)
        iconColor = try? container.decodeIfPresent(String.self, forKey: .iconColor)
        isCurrent = (try? container.decode(Bool.self, forKey: .isCurrent)) ?? false
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        sortIndex = (try? container.decode(Int.self, forKey: .sortIndex)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(apps, forKey: .apps)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(iconColor, forKey: .iconColor)
        try container.encode(isCurrent, forKey: .isCurrent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sortIndex, forKey: .sortIndex)
    }

    static func == (lhs: ContextPrompt, rhs: ContextPrompt) -> Bool {
        lhs.id == rhs.id
    }
}
