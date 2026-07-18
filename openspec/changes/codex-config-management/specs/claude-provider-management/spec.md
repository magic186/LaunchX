## MODIFIED Requirements

### Requirement: Provider 数据模型
系统 SHALL 定义 ClaudeProvider 数据模型，包含以下字段：
- id: 唯一标识符（UUID）
- name: Provider 显示名称
- settingsConfig: JSON 字典，包含 env 变量（ANTHROPIC_AUTH_TOKEN、ANTHROPIC_BASE_URL、ANTHROPIC_MODEL 等）以及可选的 Codex 字段（CODEX_API_KEY、CODEX_BASE_URL、CODEX_MODEL）
- category: 分类（official、cn_official、aggregator、third_party、cloud_provider）
- websiteUrl: 官网链接（可选）
- notes: 备注（可选）
- icon: 图标标识（可选）
- iconColor: 图标颜色（可选）
- isCurrent: 是否为当前激活的 Provider
- createdAt: 创建时间戳
- sortIndex: 排序索引
- apps: Set<AppTarget>，标识该 Provider 同步到哪些应用（默认 [.claude]）

#### Scenario: 创建 Provider 实例
- **WHEN** 用户通过表单填写 Provider 信息并提交
- **THEN** 系统生成唯一 id，保存到 providers.json，apps 默认为 [.claude]（如果用户未选择其他选项）

#### Scenario: Provider 数据持久化
- **WHEN** Provider 数据发生变化（增删改）
- **THEN** 系统 SHALL 将变更持久化到 `~/Library/Application Support/LaunchX/claude/providers.json`，包含 apps 字段

#### Scenario: 向后兼容加载旧数据
- **WHEN** 加载的 providers.json 中 Provider 记录不包含 apps 字段
- **THEN** 系统 SHALL 将 apps 默认设为 [.claude]，确保向后兼容

### Requirement: Provider 切换
系统 SHALL 支持在多个 Provider 之间切换，切换时自动更新配置文件，并根据 apps 字段决定同步到哪些应用。

#### Scenario: 切换到新 Provider
- **WHEN** 用户选择一个非当前激活的 Provider 并点击"启用"
- **THEN** 系统 SHALL 执行以下步骤：
  1. 读取当前 `~/.claude/settings.json`，将配置回填到当前激活的 Provider（backfill）
  2. 备份当前 `~/.claude/settings.json` 到 backups 目录
  3. 将新 Provider 的 settingsConfig 写入 `~/.claude/settings.json`（仅当 apps 包含 .claude）
  4. 将新 Provider 的配置映射并写入 `~/.codex/config.toml` 和 `~/.codex/auth.json`（仅当 apps 包含 .codex）
  5. 更新 providers.json 中的 isCurrent 标志
  6. 触发 MCP 同步和 Skills 同步

#### Scenario: 首次使用导入
- **WHEN** LaunchX 首次打开 Claude Code 管理功能，且 `~/.claude/settings.json` 已存在
- **THEN** 系统 SHALL 自动读取该文件并创建一个名为"default"的 Provider，标记为当前激活，apps 默认为 [.claude]
