## Why

LaunchX 目前已支持 Claude Code 的 provider/MCP/skills 配置管理（cc-switch 功能），但用户越来越多地同时使用 OpenAI Codex CLI。cc-switch（独立 Tauri 应用）已实现了 Codex 的配置管理，包括 TOML 格式的 config.toml、auth.json 以及 skills 目录的同步。将 Codex 配置管理集成到 LaunchX 中，可以让用户在一个工具内统一管理 Claude Code 和 Codex 的配置，避免重复切换工具。

## What Changes

- 新增 Codex provider 管理：支持 OpenAI 官方和第三方代理提供商的配置，写入 `~/.codex/config.toml` 和 `~/.codex/auth.json`
- 新增 Codex MCP 服务器管理：支持在 Codex 的 config.toml 中管理 `[mcp_servers]` 段
- 新增 Codex skills 管理：支持将技能文件同步到 `~/.codex/skills/` 目录
- 扩展现有 Claude Code 配置视图，增加应用选择器，允许用户为 Claude Code 和/或 Codex 启用/禁用每个配置项
- 扩展现有数据模型（Provider、McpServer、Skill），增加 `apps` 字段标识配置项适用于哪些应用

## Capabilities

### New Capabilities
- `codex-provider-management`: Codex 提供商的 CRUD 操作，包括 TOML 格式的 config.toml 和 auth.json 的读写、原子写入、语法保留编辑
- `codex-mcp-management`: Codex MCP 服务器的管理，同步到 config.toml 的 [mcp_servers] 段
- `codex-skills-management`: Codex 技能管理，支持从 SSOT 目录同步到 ~/.codex/skills/

### Modified Capabilities
- `claude-provider-management`: 扩展 provider 模型增加 apps 字段，支持跨应用启用/禁用
- `claude-mcp-management`: 扩展 MCP 服务器模型增加 apps 字段，支持跨应用启用/禁用
- `claude-skills-management`: 扩展 skills 模型增加 apps 字段，支持跨应用启用/禁用

## Impact

- **数据模型**: ClaudeProvider、McpServer、ClaudeSkill 需增加 `apps` 字段，需要数据迁移
- **服务层**: ClaudeProviderService、ClaudeMcpService、ClaudeSkillService 需增加 Codex 同步逻辑
- **存储层**: ClaudeDataStore 需扩展支持 Codex 配置文件的读写（TOML + JSON）
- **UI 层**: ClaudeCodeSettingsView 及各子视图需增加应用选择器 UI
- **依赖**: 可能需要引入 TOML 解析库（如 swift-collections 或手写轻量解析器）
- **配置文件**: 新增对 `~/.codex/config.toml`、`~/.codex/auth.json`、`~/.codex/skills/` 的读写

### Rollback Plan

- 所有 Codex 配置操作均在用户明确选择时才执行，不影响现有 Claude Code 功能
- 新增的 `apps` 字段使用默认值 `["claude"]`，确保向后兼容
- 数据迁移在首次加载时执行，迁移前自动备份原始数据文件
- 如需回滚，删除 Codex 相关代码即可，Claude Code 功能不受影响
