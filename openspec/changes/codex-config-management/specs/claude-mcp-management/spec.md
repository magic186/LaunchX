## MODIFIED Requirements

### Requirement: MCP 服务器数据模型
系统 SHALL 定义 McpServer 数据模型，包含以下字段：
- id: 唯一标识符（UUID）
- name: 服务器名称
- serverConfig: JSON 字典，包含 MCP 服务器配置（command、args、url 等）
- description: 描述（可选）
- homepage: 主页链接（可选）
- docs: 文档链接（可选）
- tags: 标签数组
- isEnabled: 是否启用（控制是否同步）
- apps: Set<AppTarget>，标识该 MCP 服务器同步到哪些应用（默认 [.claude]）

#### Scenario: MCP 服务器数据持久化
- **WHEN** MCP 服务器数据发生变化
- **THEN** 系统 SHALL 将变更持久化到 `~/Library/Application Support/LaunchX/claude/mcp_servers.json`，包含 apps 字段

#### Scenario: 向后兼容加载旧数据
- **WHEN** 加载的 mcp_servers.json 中记录不包含 apps 字段
- **THEN** 系统 SHALL 将 apps 默认设为 [.claude]，确保向后兼容

### Requirement: MCP 同步到 Claude Code
系统 SHALL 将所有启用的 MCP 服务器同步到对应的配置文件，根据 apps 字段决定同步目标。

#### Scenario: 全量同步
- **WHEN** Provider 切换触发 MCP 同步，或用户手动触发同步
- **THEN** 系统 SHALL 按 apps 字段分发：apps 包含 .claude 的同步到 `~/.claude.json`，apps 包含 .codex 的同步到 `~/.codex/config.toml`

### Requirement: MCP CRUD 操作
系统 SHALL 支持对 MCP 服务器的完整增删改查操作，CRUD 后按 apps 字段同步到对应应用。

#### Scenario: 添加 MCP 服务器
- **WHEN** 用户填写 MCP 服务器名称和配置并保存
- **THEN** 系统创建新的 McpServer 记录，保存到 mcp_servers.json，并按 apps 字段同步到对应的配置文件

#### Scenario: 删除 MCP 服务器
- **WHEN** 用户删除一个 MCP 服务器
- **THEN** 系统从 mcp_servers.json 中移除记录，并从该服务器 apps 字段对应的所有配置文件中移除该条目

### Requirement: MCP 管理界面
系统 SHALL 在 MCP 管理界面中增加应用选择器。

#### Scenario: MCP 服务器列表中的应用标记
- **WHEN** 用户查看 MCP 服务器列表
- **THEN** 每个服务器条目 SHALL 显示其同步到的应用图标（Claude/Codex），用户可点击切换
