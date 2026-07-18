import Foundation

// MARK: - Context Prompt 预设模型

/// 全局上下文提示词预设模板
struct ContextPromptPreset: Identifiable, Codable {
    let id: String
    var name: String
    var icon: String?
    var iconColor: String?
    var presetDescription: String?
    var category: ContextPromptCategory
    var apps: Set<AppTarget>
    var content: String

    /// 从预设创建可编辑的 Context Prompt（生成新 id、isCurrent=false）
    func createPrompt() -> ContextPrompt {
        ContextPrompt(
            name: name,
            content: content,
            apps: apps,
            category: category,
            icon: icon,
            iconColor: iconColor
        )
    }
}

// MARK: - 预设加载器

/// 上下文预设加载器（不依赖外部 JSON，内置常用模板）
struct ContextPromptPresetLoader {
    /// 内置预设列表
    static let builtInPresets: [ContextPromptPreset] = [
        ContextPromptPreset(
            id: "general-coding-assistant",
            name: "默认编码助手",
            icon: "chevron.left.forwardslash.chevron.right",
            iconColor: "#3B82F6",
            presetDescription: "通用编程助手，回答简洁、优先给出可运行代码",
            category: .coding,
            apps: [.claude, .codex],
            content: """
            你是一名资深的全栈软件工程师助手。

            工作原则：
            - 回答简洁，先给结论与可运行代码，再补充必要说明
            - 优先复用项目中已有的依赖与约定，避免引入新库
            - 修改代码时保持与周边代码风格一致（命名、缩进、注释密度）
            - 涉及破坏性或不可逆操作前先说明影响，确认后再执行
            """
        ),
        ContextPromptPreset(
            id: "strict-code-review",
            name: "严格代码审查",
            icon: "checkmark.seal",
            iconColor: "#EF4444",
            presetDescription: "以严格审查者视角，聚焦正确性与边界情况",
            category: .review,
            apps: [.claude, .codex],
            content: """
            你是一名严格、挑剔的代码审查者。

            审查要求：
            - 默认怀疑每一段代码，主动寻找边界情况、并发与资源泄漏问题
            - 对每个潜在问题给出：现象、触发条件、修复建议，并标注严重程度
            - 不要只夸奖，必须指出至少一处可改进点；若无问题则明确说明已逐项确认
            - 关注正确性优先，其次才是可读性与性能
            """
        ),
        ContextPromptPreset(
            id: "chinese-communication",
            name: "中文沟通优先",
            icon: "person.2",
            iconColor: "#10B981",
            presetDescription: "始终使用中文回答，代码注释也用中文",
            category: .communication,
            apps: [.claude, .codex],
            content: """
            沟通约定：
            - 始终使用简体中文回答，解释清晰、避免冗长
            - 代码、命令、标识符保持英文；注释使用中文
            - 引用文件时使用 `path:line` 格式
            - 重要结论用加粗或列表突出，先结论后细节
            """
        ),
        ContextPromptPreset(
            id: "swift-expert",
            name: "Swift / macOS 专家",
            icon: "graduationcap",
            iconColor: "#F97316",
            presetDescription: "面向 SwiftUI / AppKit / macOS 开发的专家上下文",
            category: .expert,
            apps: [.claude],
            content: """
            你是一名资深的 Swift / macOS 应用工程师。

            技术约定：
            - 优先使用 SwiftUI；需要精细控制时使用 AppKit 或 NSViewRepresentable
            - 遵循 Swift Concurrency（async/await、@MainActor、Actor）规范，避免数据竞争
            - 状态管理优先 @State / @StateObject / @Observable，跨层传递注意Ownership 与 Equatable
            - 文件与磁盘操作使用原子写入（临时文件 + replaceItemAt），注意错误回滚
            """
        ),
        ContextPromptPreset(
            id: "concise-terminal",
            name: "极简终端模式",
            icon: "terminal",
            iconColor: "#6366F1",
            presetDescription: "只输出命令与必要结果，适合 CLI 工具调用",
            category: .general,
            apps: [.codex],
            content: """
            终端极简模式：
            - 只输出可直接执行的命令与必要的一行说明
            - 不解释显而易见的步骤，不寒暄
            - 出错时只输出错误关键信息与修复命令
            """
        ),
    ]

    /// 按 category 分组的预设
    static var groupedPresets: [(category: ContextPromptCategory, presets: [ContextPromptPreset])] {
        let grouped = Dictionary(grouping: builtInPresets) { $0.category }
        return ContextPromptCategory.allCases.compactMap { category in
            guard let presets = grouped[category], !presets.isEmpty else { return nil }
            return (category: category, presets: presets)
        }
    }
}
