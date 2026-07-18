## ADDED Requirements

### Requirement: Codex 配置文件读写
系统 SHALL 支持读写 Codex CLI 的配置文件（`~/.codex/config.toml` 和 `~/.codex/auth.json`）。

#### Scenario: 读取 Codex config.toml
- **WHEN** 系统需要读取 Codex 配置
- **THEN** 系统 SHALL 解析 `~/.codex/config.toml`，提取 `model` 字段和 `[model_providers.*]` 段

#### Scenario: 读取 Codex auth.json
- **WHEN** 系统需要读取 Codex 认证信息
- **THEN** 系统 SHALL 解析 `~/.codex/auth.json`，提取 `OPENAI_API_KEY` 字段

#### Scenario: 写入 Codex config.toml（语法保留）
- **WHEN** 系统需要写入 Codex 配置
- **THEN** 系统 SHALL 仅修改 `model` 和 `[model_providers.<name>]` 相关字段，保留文件中其他内容和注释不变

#### Scenario: 写入 Codex auth.json
- **WHEN** 系统需要写入 Codex 认证信息
- **THEN** 系统 SHALL 使用原子写入策略（先写临时文件再 rename）

#### Scenario: Codex 配置目录不存在
- **WHEN** `~/.codex/` 目录不存在
- **THEN** 系统 SHALL 在首次写入时自动创建该目录

### Requirement: Codex Provider 映射
系统 SHALL 将 Provider 的配置映射为 Codex 格式。

#### Scenario: 带 Codex 字段的 Provider 写入
- **WHEN** 一个 Provider 包含 `CODEX_API_KEY`、`CODEX_BASE_URL`、`CODEX_MODEL` 字段且 apps 包含 `.codex`
- **THEN** 系统 SHALL 将 `CODEX_API_KEY` 写入 auth.json 的 `OPENAI_API_KEY`，将 `CODEX_BASE_URL` 写入 config.toml 的 `[model_providers.<providerName>]` 段，将 `CODEX_MODEL` 写入 config.toml 的顶层 `model` 字段

#### Scenario: Base URL 自动补全
- **WHEN** `CODEX_BASE_URL` 不以 `/v1` 结尾
- **THEN** 系统 SHALL 自动追加 `/v1` 后缀后写入 config.toml

#### Scenario: Provider 不含 Codex 字段
- **WHEN** 一个 Provider 的 settingsConfig 不包含 `CODEX_*` 前缀字段但 apps 包含 `.codex`
- **THEN** 系统 SHALL 回退使用 `ANTHROPIC_AUTH_TOKEN` 作为 API Key，`ANTHROPIC_BASE_URL` 作为 Base URL（追加 `/v1`），`ANTHROPIC_MODEL` 作为 model

### Requirement: Codex Provider 原子写入
系统 SHALL 使用原子操作写入 Codex 的 config.toml 和 auth.json。

#### Scenario: 协同原子写入
- **WHEN** 系统同时写入 auth.json 和 config.toml
- **THEN** 系统 SHALL 先备份 auth.json，写入 auth.json，再写入 config.toml；若 config.toml 写入失败，SHALL 使用备份回滚 auth.json

#### Scenario: 单文件写入失败回滚
- **WHEN** config.toml 写入过程中发生错误
- **THEN** 系统 SHALL 删除临时文件，恢复 auth.json 备份，并向调用方抛出错误

### Requirement: Codex Provider 首次导入
系统 SHALL 支持从已有的 Codex 配置中导入 Provider。

#### Scenario: 检测已有 Codex 配置
- **WHEN** 用户首次在 LaunchX 中启用 Codex 管理功能，且 `~/.codex/config.toml` 或 `~/.codex/auth.json` 已存在
- **THEN** 系统 SHALL 读取 Codex 配置，创建对应的 Provider 记录，标记 apps 为 `[.codex]`

### Requirement: Codex Provider 切换同步
系统 SHALL 在切换 Provider 时，如果新 Provider 的 apps 包含 `.codex`，自动同步到 Codex 配置。

#### Scenario: 切换到包含 Codex 的 Provider
- **WHEN** 用户切换到一个 apps 包含 `.codex` 的 Provider
- **THEN** 系统 SHALL 在写入 Claude Code 配置后，同步写入 Codex 的 config.toml 和 auth.json

#### Scenario: 切换到不包含 Codex 的 Provider
- **WHEN** 用户切换到一个 apps 不包含 `.codex` 的 Provider
- **THEN** 系统 SHALL 不修改 Codex 配置文件
