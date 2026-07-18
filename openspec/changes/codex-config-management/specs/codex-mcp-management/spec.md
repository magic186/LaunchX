## ADDED Requirements

### Requirement: Codex MCP 配置同步
系统 SHALL 将启用的 MCP 服务器同步到 Codex 的 config.toml 中的 `[mcp_servers]` 段。

#### Scenario: 同步 MCP 服务器到 Codex
- **WHEN** 一个 MCP 服务器的 `apps` 包含 `.codex` 且处于启用状态
- **THEN** 系统 SHALL 将该服务器的配置写入 `~/.codex/config.toml` 的 `[mcp_servers.<name>]` 段

#### Scenario: 从 Codex 移除 MCP 服务器
- **WHEN** 一个 MCP 服务器的 `apps` 不再包含 `.codex` 或被禁用
- **THEN** 系统 SHALL 从 `~/.codex/config.toml` 的 `[mcp_servers]` 段中移除该服务器条目

### Requirement: Codex MCP 全量同步
系统 SHALL 支持全量同步所有 MCP 服务器到 Codex 配置。

#### Scenario: 全量同步到 Codex
- **WHEN** 触发 Codex MCP 全量同步
- **THEN** 系统 SHALL 读取 config.toml，保留非 `[mcp_servers]` 段内容，用所有 `apps` 包含 `.codex` 且启用的 MCP 服务器替换 `[mcp_servers]` 段

#### Scenario: 无 Codex MCP 服务器
- **WHEN** 全量同步时没有任何 MCP 服务器的 `apps` 包含 `.codex`
- **THEN** 系统 SHALL 确保 config.toml 中没有 `[mcp_servers]` 段（或该段为空）

### Requirement: 从 Codex 导入 MCP 配置
系统 SHALL 支持从 `~/.codex/config.toml` 导入已有的 MCP 服务器配置。

#### Scenario: 导入 Codex MCP
- **WHEN** 用户触发从 Codex 导入 MCP 操作
- **THEN** 系统 SHALL 解析 `~/.codex/config.toml` 的 `[mcp_servers]` 段，为每个服务器创建 McpServer 记录，标记 `apps` 为 `[.codex]`

#### Scenario: 导入时合并
- **WHEN** 导入的 MCP 服务器名称与已有服务器重名
- **THEN** 系统 SHALL 仅为已有服务器的 `apps` 添加 `.codex`，不覆盖已有配置
