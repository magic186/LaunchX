import Foundation
import Combine

/// 上下文切换错误
enum ContextSwitchError: LocalizedError {
    case promptNotFound
    case writeFailed(Error)
    case persistFailed(Error)

    var errorDescription: String? {
        switch self {
        case .promptNotFound:
            return "未找到目标上下文预设"
        case .writeFailed(let error):
            return "写入全局上下文文件失败：\(error.localizedDescription)"
        case .persistFailed(let error):
            return "保存上下文预设数据失败：\(error.localizedDescription)"
        }
    }
}

/// 全局上下文提示词（Context Prompt）管理服务
///
/// 设计对齐 `ClaudeProviderService`：
/// - 单例 + `@Published var prompts` 作为唯一事实源
/// - 复用 `AppTarget` 跨应用机制，Claude / Codex 可独立激活，也可一条预设同时作用于两者
/// - 切换流程复刻 `switchProvider(to:)`
@MainActor
final class ContextPromptService: ObservableObject {
    static let shared = ContextPromptService()

    @Published var prompts: [ContextPrompt] = []

    /// 当前激活的 Claude 上下文预设
    var currentClaudePrompt: ContextPrompt? {
        prompts.first { $0.isCurrent && $0.apps.contains(.claude) }
    }

    /// 当前激活的 Codex 上下文预设
    var currentCodexPrompt: ContextPrompt? {
        prompts.first { $0.isCurrent && $0.apps.contains(.codex) }
    }

    /// 写入全局指令文件末尾的管理标记前缀（用于识别 LaunchX 托管的文件）
    static let managedMarkerPrefix = "<!-- managed-by: launchx-context-prompt"

    private let store = ClaudeDataStore.shared
    private let fileManager = FileManager.default

    private init() {
        loadData()
    }

    // MARK: - 数据加载

    private func loadData() {
        prompts = store.loadContextPrompts()
    }

    private func persistData() throws {
        try store.saveContextPrompts(prompts)
    }

    // MARK: - 切换激活预设

    /// 切换到指定上下文预设（复刻 switchProvider 的流程）
    func switchPrompt(to target: ContextPrompt) throws {
        // 目标已是当前激活 → 无需操作
        guard !target.isCurrent else { return }
        guard prompts.contains(where: { $0.id == target.id }) else {
            throw ContextSwitchError.promptNotFound
        }

        // 1. 快照（用于失败回滚）
        let snapshot = prompts

        // 2. 按 apps 交集翻转 isCurrent（仅影响与目标 apps 有交集的预设）
        let targetApps = target.apps
        for i in prompts.indices {
            if !prompts[i].apps.intersection(targetApps).isEmpty {
                prompts[i].isCurrent = (prompts[i].id == target.id)
            }
        }

        // 3. 取切换后的目标
        guard let activated = prompts.first(where: { $0.id == target.id }) else {
            prompts = snapshot
            throw ContextSwitchError.promptNotFound
        }

        // 4. 写入全局指令文件（按 apps）。写入内部会先备份已有文件
        do {
            for app in activated.apps {
                try writeContextFile(content: activated.content, promptId: activated.id, for: app)
            }
        } catch {
            prompts = snapshot
            throw ContextSwitchError.writeFailed(error)
        }

        // 5. 持久化
        do {
            try persistData()
        } catch {
            throw ContextSwitchError.persistFailed(error)
        }
    }

    // MARK: - CRUD

    /// 添加预设（不会自动激活）
    func addPrompt(_ prompt: ContextPrompt) throws {
        var newPrompt = prompt
        newPrompt.isCurrent = false
        newPrompt.sortIndex = (prompts.map(\.sortIndex).max() ?? -1) + 1
        prompts.append(newPrompt)
        try persistData()
    }

    /// 更新预设。若被更新的是当前激活预设，SHALL 同步重写其对应的全局指令文件
    func updatePrompt(_ prompt: ContextPrompt) throws {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
            throw ContextSwitchError.promptNotFound
        }
        prompts[index] = prompt

        // 激活态变更时同步全局指令文件
        if prompt.isCurrent {
            for app in prompt.apps {
                try writeContextFile(content: prompt.content, promptId: prompt.id, for: app)
            }
        }
        try persistData()
    }

    /// 删除预设。删除当前激活预设 SHALL 被拒绝（返回 false）
    @discardableResult
    func deletePrompt(_ prompt: ContextPrompt) throws -> Bool {
        guard !prompt.isCurrent else { return false }
        prompts.removeAll { $0.id == prompt.id }
        try persistData()
        return true
    }

    /// 复制预设（生成新 id、isCurrent=false，名称加「副本」后缀）
    func duplicatePrompt(_ prompt: ContextPrompt) throws {
        var copy = prompt
        copy = ContextPrompt(
            name: prompt.name + " 副本",
            content: prompt.content,
            apps: prompt.apps,
            category: prompt.category,
            icon: prompt.icon,
            iconColor: prompt.iconColor,
            isCurrent: false,
            sortIndex: (prompts.map(\.sortIndex).max() ?? -1) + 1
        )
        prompts.append(copy)
        try persistData()
    }

    // MARK: - 全局指令文件写入（核心安全逻辑）

    /// 原子写入全局上下文指令文件，并在正文末尾追加不可见管理标记。
    /// 写入前 SHALL 先备份已有文件（无论是否托管），避免丢失用户内容。
    func writeContextFile(content: String, promptId: UUID, for app: AppTarget) throws {
        let path = store.contextFilePath(for: app)

        // 写入前备份已有文件（托管与非托管均备份，便于撤销 & 保护用户内容）
        if fileManager.fileExists(atPath: path.path) {
            _ = try? store.backupContextFile(for: app)
        }

        // 确保父目录存在
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 组装正文 + 末尾管理标记
        let marker = "<!-- managed-by: launchx-context-prompt; id: \(promptId.uuidString) -->"
        var fullContent = content
        if !fullContent.isEmpty && !fullContent.hasSuffix("\n") {
            fullContent += "\n"
        }
        fullContent += "\n\(marker)\n"

        guard let data = fullContent.data(using: .utf8) else { return }

        // 原子写入：临时文件 + replaceItemAt（存在）/ moveItem（不存在）
        let tempPath = path.deletingLastPathComponent()
            .appendingPathComponent(".tmp_context_\(UUID().uuidString)")
        do {
            try data.write(to: tempPath, options: [])
            if fileManager.fileExists(atPath: path.path) {
                _ = try? fileManager.replaceItemAt(path, withItemAt: tempPath)
            } else {
                try fileManager.moveItem(at: tempPath, to: path)
            }
        } catch {
            try? fileManager.removeItem(at: tempPath)
            throw error
        }
    }

    /// 检测文件是否由 LaunchX 托管（含管理标记）
    func isFileManaged(at path: URL) -> Bool {
        guard fileManager.fileExists(atPath: path.path),
              let text = try? String(contentsOf: path, encoding: .utf8) else {
            return false
        }
        return text.contains(Self.managedMarkerPrefix)
    }
}
