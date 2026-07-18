## Context

LaunchX 是一个 macOS 启动器应用，已内置 cc-switch 功能用于管理 Claude Code 的 Provider/MCP/Skills 配置。当前架构为：

- **数据层**: `ClaudeDataStore` 管理 JSON 文件存储
- **服务层**: 三个独立单例服务 (`ClaudeProviderService`, `ClaudeMcpService`, `ClaudeSkillService`) 管理 CRUD 和同步
- **模型层**: `ClaudeProvider`, `McpServer`, `ClaudeSkill` 纯 Codable 结构体
- **UI 层**: `ClaudeCodeSettingsView` 包含 Provider/MCP/Skills 三个 tab

现有设计假设所有配置仅面向 Claude Code（`~/.claude/settings.json`, `~/.claude.json`, `~/.claude/skills/`）。需要扩展为同时支持 OpenAI Codex CLI（`~/.codex/config.toml`, `~/.codex/auth.json`, `~/.codex/skills/`）。

cc-switch（独立 Tauri 应用）的实现提供了参考：它使用 SSOT（单一数据源）模式，集中管理配置后按应用分发同步。

## Goals / Non-Goals

**Goals:**
- 扩展现有 Provider/MCP/Skills 数据模型，增加"目标应用"概念（Claude Code / Codex）
- 实现 Codex 配置文件的读写（TOML config.toml + JSON auth.json）
- 在现有 UI 中增加应用选择器，允许每个配置项独立控制同步目标
- 保持对 Claude Code 现有功能的完全兼容

**Non-Goals:**
- 不支持 Gemini、OpenCode 等其他 AI 工具（后续可扩展）
- 不实现 cc-switch 的故障转移队列（failover queue）功能
- 不实现 cc-switch 的定价/用量查询功能
- 不修改现有的 Provider 预设系统（预设仍面向 Claude Code，用户可手动添加 Codex 专用 Provider）

## Decisions

### Decision 1: Apps 字段设计 — 使用 `Set<AppTarget>` 枚举

在 `ClaudeProvider`、`McpServer`、`ClaudeSkill` 模型中新增 `apps: Set<AppTarget>` 字段。

```swift
enum AppTarget: String, Codable, CaseIterable {
    case claude = "claude"
    case codex = "codex"
}
```

**理由**: 使用枚举而非字符串，获得编译时安全性和 UI 自动生成。使用 `Set` 而非 `Array` 因为顺序不重要且需去重。默认值为 `[.claude]` 确保向后兼容。

**备选方案**: 使用 `isForClaude: Bool` + `isForCodex: Bool` 两个布尔字段。拒绝原因：扩展性差，每增加一个应用就需加一个字段。

### Decision 2: TOML 处理 — 轻量手写解析器

Codex 的 `config.toml` 需要 TOML 读写支持。选择实现一个轻量级 TOML 解析/生成器，仅覆盖 LaunchX 需要操作的段（顶层 `model` 字段、`[model_providers.*]` 段、`[mcp_servers.*]` 段）。

**理由**: 不引入外部依赖（项目目前无 SPM 依赖），且只需处理有限的 TOML 子集。cc-switch 的 Rust 实现使用 `toml_edit` 实现语法保留编辑，Swift 端可用类似策略。

**备选方案**: 引入 Swift TOML 库（如 `swift-toml`）。拒绝原因：增加外部依赖，且大部分功能用不到。

### Decision 3: 同步策略 — 各服务内部处理多应用同步

在每个现有服务内部增加 Codex 同步逻辑，而非创建新的 "SyncService"。

```
ClaudeProviderService.switchProvider():
  → writeClaudeSettings()     // 写 ~/.claude/settings.json
  → writeCodexSettings()      // 写 ~/.codex/config.toml + auth.json
  → ClaudeMcpService.sync()   // 各自按 apps 字段分发
  → ClaudeSkillService.sync() // 各自按 apps 字段分发
```

**理由**: 改动最小，不需要引入新的服务层抽象。各服务已管理各自的数据和同步，只需扩展同步目标。

**备选方案**: 创建独立的 `CodexSyncService` 统一管理所有 Codex 同步。拒绝原因：过度工程化，增加维护负担。

### Decision 4: Codex Provider 配置映射

Codex 使用不同于 Claude Code 的配置格式：

| 字段 | Claude Code | Codex |
|------|------------|-------|
| API Key | `env.ANTHROPIC_AUTH_TOKEN` | `auth.json → OPENAI_API_KEY` |
| Base URL | `env.ANTHROPIC_BASE_URL` | `config.toml → [model_providers.<name>] → base_url` |
| Model | `env.ANTHROPIC_MODEL` | `config.toml → model` |

映射策略：在 Provider 的 `settingsConfig` 中增加 Codex 专用字段前缀 `CODEX_`：
- `CODEX_API_KEY` → 写入 auth.json 的 OPENAI_API_KEY
- `CODEX_BASE_URL` → 写入 config.toml 的 model_providers 段
- `CODEX_MODEL` → 写入 config.toml 的 model 字段

**理由**: 保持 Claude 和 Codex 配置在同一 Provider 实例中，用户可一键为两个应用配置同一个 Provider。前缀区分避免字段冲突。

### Decision 5: 原子写入策略

Codex 的 config.toml 和 auth.json 需要原子写入，且两个文件需要协同：

```
1. 写入 auth.json.tmp → rename auth.json
2. 写入 config.toml.tmp → rename config.toml
3. 如果 config.toml 失败，回滚 auth.json（用备份恢复）
```

**理由**: cc-switch 的 Rust 实现采用同样的策略，确保两个文件的一致性。

### Decision 6: UI 扩展 — 在现有 Tab 中增加应用选择器

在 Provider 列表项、MCP 列表项、Skill 列表项中增加应用选择器（两个小图标/按钮，显示 Claude 和 Codex 的启用状态）。不新增 Tab。

**理由**: 用户管理的是同一组配置（同一个 Provider/MCP/Skill），只是选择同步到哪些应用。新增 Tab 会导致数据重复和管理混乱。

## Risks / Trade-offs

- **[TOML 解析器健壮性]** → 手写解析器可能无法处理复杂的 TOML 文件（如嵌套数组、多行字符串）。缓解：仅解析 LaunchX 管理的段，其他段保持原样透传。
- **[数据迁移]** → 已有用户的 providers.json/mcp_servers.json/skills.json 没有 `apps` 字段。缓解：`Set<AppTarget>` 使用 `decodeWithDefault` 策略，缺失时默认为 `[.claude]`。
- **[Codex 配置文件冲突]** → 用户可能手动编辑 `~/.codex/config.toml`，LaunchX 写入时可能覆盖用户修改。缓解：采用"语法保留编辑"策略，仅修改 LaunchX 管理的段，保留其他内容。
- **[Codex CLI 版本差异]** → Codex 的配置格式可能随版本变化。缓解：将 TOML key 和文件路径集中定义为常量，便于后续调整。
