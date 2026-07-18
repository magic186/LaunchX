## ADDED Requirements

### Requirement: Codex Skills 同步目录
系统 SHALL 将启用的 Skills 同步到 `~/.codex/skills/` 目录。

#### Scenario: 同步 Skill 到 Codex
- **WHEN** 一个 Skill 的 `apps` 包含 `.codex` 且处于启用状态
- **THEN** 系统 SHALL 在 `~/.codex/skills/<directory>` 创建 symlink 指向 LaunchX 本地主副本

#### Scenario: 从 Codex 移除 Skill
- **WHEN** 一个 Skill 的 `apps` 不再包含 `.codex` 或被禁用
- **THEN** 系统 SHALL 从 `~/.codex/skills/<directory>` 移除 symlink 或复制的文件

### Requirement: Codex Skills 全量同步
系统 SHALL 在 Provider 切换时自动同步所有 Skills 到 Codex。

#### Scenario: Provider 切换触发的 Codex Skills 同步
- **WHEN** Provider 切换成功完成
- **THEN** 系统 SHALL 遍历所有已安装且启用的 Skills，对 `apps` 包含 `.codex` 的 Skill 确保其 symlink 存在于 `~/.codex/skills/` 中

### Requirement: Codex Skills 目录初始化
系统 SHALL 在首次同步时自动创建 Codex skills 目录。

#### Scenario: 创建 Codex skills 目录
- **WHEN** 首次向 Codex 同步 Skill，且 `~/.codex/skills/` 目录不存在
- **THEN** 系统 SHALL 自动创建 `~/.codex/skills/` 目录

### Requirement: 从 Codex 导入 Skills
系统 SHALL 支持从 `~/.codex/skills/` 目录导入已有的 Skills。

#### Scenario: 扫描 Codex 未管理的 Skills
- **WHEN** 用户触发导入 Codex Skills 操作
- **THEN** 系统 SHALL 扫描 `~/.codex/skills/` 目录，发现不在 skills.json 中的 Skills，列出供用户选择导入
