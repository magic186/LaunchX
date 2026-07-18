## Why

LaunchX 目前能像切换 Provider 一样在多套配置之间快速切换 Claude Code 与 Codex，但「全局上下文提示词」（Claude Code 的 `~/.claude/CLAUDE.md`、Codex 的 `~/.codex/AGENTS.md`）目前完全不在管理范围内。用户常常需要在不同的工作场景下使用不同的「人格/指令上下文」（例如：默认编码助手、严格代码审查、中文沟通、特定框架专家等），现在只能手动编辑这两个文件，既无法保存多套、也无法一键切换，容易覆盖误操作。

引入「上下文预设」管理，可以让用户像切换 Provider 一样为 Claude Code / Codex 保存、命名、切换多套全局上下文提示词，统一在一个面板里完成管理。

## What Changes

- 新增「上下文预设（Context Prompt）」数据模型：每条预设包含名称、Markdown 正文内容、`apps: Set<AppTarget>`（适用于 Claude 和/或 Codex）、`isCurrent` 激活标志、排序与创建时间
- 新增 `ContextPromptService`（`@MainActor ObservableObject` 单例）：负责加载/持久化预设、按 `apps` 范围切换激活项，并把激活预设写入对应的「全局指令文件」
- 切换激活预设时，系统 SHALL 将预设正文写入：
  - 适用于 `.claude` 的预设 → `~/.claude/CLAUDE.md`
  - 适用于 `.codex` 的预设 → `~/.codex/AGENTS.md`
- 写入前 SHALL 先备份现有文件到 Application Support 的 `backups/` 目录，避免丢失用户原有内容
- 新增内置预设库（例如「默认编码助手」「代码审查」「中文沟通」「特定框架专家」等），用户可基于预设一键创建
- 支持完整 CRUD：新增、编辑（名称 + Markdown 正文）、删除、复制、排序
- 在 Claude Code 与 Codex 两个设置面板中各新增「上下文」标签页，UI 形态对齐现有「Provider 列表 + 预设选择器 + 编辑表单」
- 新增持久化文件 `~/Library/Application Support/LaunchX/claude/context_prompts.json`

## Capabilities

### New Capabilities
- `context-prompt-management`: 上下文预设（全局上下文提示词）的完整管理能力——数据模型、内置预设库、CRUD、持久化、以及切换激活预设并将其内容写入 `~/.claude/CLAUDE.md` 和/或 `~/.codex/AGENTS.md` 的逻辑，复用 `AppTarget` 跨应用机制。

### Modified Capabilities
<!-- 不修改任何现有 spec 的需求级别行为；本变更为全新增能力，现有 claude/codex provider、mcp、skills 管理需求保持不变。 -->
- 无

## Impact

- **数据模型（新增）**: `LaunchX/Models/` 新增 `ContextPrompt.swift`、`ContextPromptPreset.swift`，结构对齐 `ClaudeProvider` / `ClaudeProviderPreset`（含向后兼容的 `init(from:)`，`apps` 缺失时默认 `[.claude]`）
- **服务层（新增）**: `LaunchX/Services/Features/ClaudeCode/` 新增 `ContextPromptService.swift`，切换算法对齐 `ClaudeProviderService.switchProvider(to:)` 的快照→备份→翻转 `isCurrent`→写盘→持久化流程
- **存储层（扩展）**: `ClaudeDataStore` 新增 `context_prompts.json` 的 `loadContextPrompts()` / `saveContextPrompts(_:)`，以及 `backupContextFile(app:)` 备份逻辑
- **配置文件读写（新增）**: 应用首次管理 `~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md`（原子写入：临时文件 + `replaceItemAt`）
- **UI 层（扩展）**: `ClaudeCodeTab` 与 `CodexMainTab` 各新增 `.context` 标签页；新增 `ContextPromptListView` / `ContextPromptPresetView` / `ContextPromptFormView`（编辑表单中用 `TextEditor` 录入 Markdown 正文）
- **依赖**: 无新增第三方依赖；Markdown 正文使用纯文本写入，复用既有原子写入工具

### Rollback Plan

- 本变更为全新增能力，不改动任何现有功能，删除新增的模型/服务/视图与 `ClaudeDataStore` 中新增的方法即可完全回滚
- 新增 `context_prompts.json` 与默认值 `apps = [.claude]` 保证向后兼容；旧版本读取旧数据不受影响
- 对 `~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md` 的任何写入操作，仅在用户主动「切换/启用」预设时执行，且写入前一定先备份原文件到 `backups/` 目录，用户可随时手动还原
- 若用户从未启用过本功能，两个全局指令文件保持原状，不受影响
