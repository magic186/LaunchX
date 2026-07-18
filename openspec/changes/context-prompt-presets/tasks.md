# Implementation Tasks

## 1. 数据模型

- [x] 1.1 新建 `LaunchX/Models/ContextPrompt.swift`，定义 `ContextPrompt: Identifiable, Codable, Equatable`，字段：`id: UUID`、`name: String`、`content: String`、`apps: Set<AppTarget>`、`isCurrent: Bool`、`sortIndex: Int`、`createdAt: Date`
- [x] 1.2 实现向后兼容 `init(from:)`：`apps` 缺失时默认 `[.claude]`；`Equatable` 仅按 `id` 比较（对齐 `ClaudeProvider`）
- [x] 1.3 新建 `LaunchX/Models/ContextPromptPreset.swift`，定义 `ContextPromptPreset`（id/name/content/apps/category）与 `ContextPromptPresetLoader`（`static let builtInPresets`、`static var groupedPresets`）；内置预设至少包含：默认编码助手、严格代码审查、中文沟通优先、特定框架专家
- [x] 1.4 为 `ContextPromptPreset` 实现 `createPrompt() -> ContextPrompt`（生成新 id、`isCurrent=false`）

## 2. 存储层（ClaudeDataStore 扩展）

- [x] 2.1 在 `ClaudeDataStore` 新增 `contextPromptsPath`（`claudeDir/context_prompts.json`）
- [x] 2.2 实现 `loadContextPrompts() -> [ContextPrompt]` 与 `saveContextPrompts(_:)`，复用既有 `writeJSON`/`readJSON` 原子写入
- [x] 2.3 新增 `backupContextFile(app: AppTarget) throws`：把现有 `~/.claude/CLAUDE.md` 或 `~/.codex/AGENTS.md` 复制到 `backups/`（带时间戳后缀），文件不存在时静默跳过
- [x] 2.4 新增只读路径访问器：`claudeContextFilePath`（`~/.claude/CLAUDE.md`）、`codexContextFilePath`（`~/.codex/AGENTS.md`）

## 3. 服务层（ContextPromptService）

- [x] 3.1 新建 `LaunchX/Services/Features/ClaudeCode/ContextPromptService.swift`：`@MainActor final class ContextPromptService: ObservableObject`，`static let shared`，`@Published var prompts: [ContextPrompt]`，`init` 中 `loadData()`
- [x] 3.2 实现计算属性 `currentClaudePrompt` / `currentCodexPrompt`（`prompts.first { $0.isCurrent && $0.apps.contains(.xxx) }`）
- [x] 3.3 定义 `ContextSwitchError: LocalizedError`（`promptNotFound` / `writeFailed(Error)` / `persistFailed(Error)`），文案对齐 `ProviderSwitchError`
- [x] 3.4 实现 `func switchPrompt(to target: ContextPrompt) throws`，复刻设计中的 8 步流程：快照 → 备份 → 按 `apps` 交集翻转 `isCurrent` → 按 `apps` 写入对应全局指令文件 → 持久化 → 失败用快照回滚
- [x] 3.5 实现 CRUD：`addPrompt`、`updatePrompt`（激活态变更时同步重写全局指令文件）、`deletePrompt`（拒绝删除激活项）、`duplicatePrompt`

## 4. 全局指令文件写入（核心安全逻辑）

- [x] 4.1 实现 `writeContextFile(content:promptId:app:) throws`：原子写（临时文件 + `replaceItemAt`/`moveItem`），正文末尾追加管理标记 `<!-- managed-by: launchx-context-prompt; id: <UUID> -->`
- [x] 4.2 实现 `isFileManaged(at:) -> Bool`：检测文件是否含 LaunchX 管理标记
- [x] 4.3 在写入前判断：目标文件存在且**非托管** → 必须先 `backupContextFile` 再写；含管理标记 → 直接替换内容并更新标记 id（仍记录备份）
- [x] 4.4 管理标记缺失/损坏的容错：按「用户手写」处理（先备份再写），不崩溃、不静默覆盖
- [ ] 4.5 验证写入后的 `~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md` 能被 Claude Code / Codex 正确识别为全局指令

## 5. UI 层

- [x] 5.1 新建 `LaunchX/Views/ClaudeCodeSettings/ContextPromptListView.swift`（仿 `ProviderListView`）：`@StateObject` 绑定 `ContextPromptService.shared`，按 `apps` 过滤，`LazyVStack` 行视图含名称/激活徽标/「启用」按钮/编辑/复制/删除，顶部 `+ 添加` 按钮
- [x] 5.2 新建 `ContextPromptRowView`：展示名称、应用图标（apps）、激活态徽标、操作按钮（删除按钮在激活态时禁用）
- [x] 5.3 新建 `ContextPromptPresetView.swift`（仿 `ProviderPresetView`）：内置预设分组画廊，选中后一键创建为可编辑预设
- [x] 5.4 新建 `ContextPromptFormView.swift`（仿 `ProviderFormView`）：名称 `TextField` + 应用选择器（Claude/Codex 可多选）+ Markdown 正文 `TextEditor`；支持新增与编辑两种模式
- [x] 5.5 在 `ClaudeCodeTab` 枚举新增 `.context` case（含图标与标题），并在内容 `switch` 中渲染 `ContextPromptListView`（按 `.claude` 过滤）
- [x] 5.6 在 `CodexMainTab` 枚举新增 `.context` case，渲染 `ContextPromptListView`（按 `.codex` 过滤）

## 6. 集成与验证

- [x] 6.1 编译通过（Debug & Release），无新警告；确认 `ContextPromptService` 与 `ClaudeProviderService` 互不耦合
- [ ] 6.2 手动验证：创建两条预设（apps={claude}、apps={codex}），分别启用，确认 `~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md` 内容正确且含管理标记
- [ ] 6.3 手动验证：启用 apps={claude,codex} 预设，确认两侧文件同时更新、两侧激活徽标正确
- [ ] 6.4 手动验证：首次接管一个已存在且非托管的 CLAUDE.md，确认原文件被备份到 `backups/` 后才覆盖
- [ ] 6.5 手动验证：删除激活态预设被拒绝并提示；编辑激活态预设后全局指令文件同步更新
- [ ] 6.6 验证向后兼容：在 `context_prompts.json` 手动构造缺失 `apps` 字段的记录，确认加载不崩溃且默认 `[.claude]`
