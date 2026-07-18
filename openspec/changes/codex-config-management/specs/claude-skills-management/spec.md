## MODIFIED Requirements

### Requirement: Skill 数据模型
系统 SHALL 定义 Skill 数据模型，包含以下字段：
- id: 唯一标识符（UUID）
- name: Skill 名称
- description: 描述（可选）
- directory: 在本地存储中的目录名
- repoOwner: 来源仓库 owner
- repoName: 来源仓库名称
- repoBranch: 来源分支（默认 main）
- readmeUrl: README 链接（可选）
- isEnabled: 是否启用（控制是否同步）
- installedAt: 安装时间戳
- apps: Set<AppTarget>，标识该 Skill 同步到哪些应用（默认 [.claude]）

#### Scenario: Skill 数据持久化
- **WHEN** Skill 数据发生变化
- **THEN** 系统 SHALL 将变更持久化到 `~/Library/Application Support/LaunchX/claude/skills.json`，包含 apps 字段

#### Scenario: 向后兼容加载旧数据
- **WHEN** 加载的 skills.json 中记录不包含 apps 字段
- **THEN** 系统 SHALL 将 apps 默认设为 [.claude]，确保向后兼容

### Requirement: Skill 安装
系统 SHALL 支持一键安装 Skills，安装后按 apps 字段同步到对应应用。

#### Scenario: 从仓库安装 Skill
- **WHEN** 用户选择一个可用 Skill 并点击安装
- **THEN** 系统 SHALL：
  1. 从 GitHub 下载 Skill 的 SKILL.md 内容
  2. 保存到 `~/Library/Application Support/LaunchX/claude/skills/<directory>/SKILL.md`
  3. 按 apps 字段在对应目录创建 symlink（apps 包含 .claude → `~/.claude/skills/<directory>`，apps 包含 .codex → `~/.codex/skills/<directory>`）
  4. 记录安装信息到 skills.json

### Requirement: Skill 卸载
系统 SHALL 支持卸载已安装的 Skills，卸载时从所有同步目录中移除。

#### Scenario: 卸载 Skill
- **WHEN** 用户卸载一个已安装的 Skill
- **THEN** 系统 SHALL：
  1. 从 `~/.claude/skills/<directory>` 移除（如果存在）
  2. 从 `~/.codex/skills/<directory>` 移除（如果存在）
  3. 删除 `~/Library/Application Support/LaunchX/claude/skills/<directory>` 中的主副本
  4. 从 skills.json 中移除记录

### Requirement: Skill 启用/禁用
系统 SHALL 支持单个 Skill 的启用/禁用切换，切换时按 apps 字段操作对应目录。

#### Scenario: 启用 Skill
- **WHEN** 用户将一个已安装但未启用的 Skill 设置为启用
- **THEN** 系统 SHALL 按 apps 字段在对应目录创建 symlink（.claude → `~/.claude/skills/`，.codex → `~/.codex/skills/`）

#### Scenario: 禁用 Skill
- **WHEN** 用户将一个启用的 Skill 设置为禁用
- **THEN** 系统 SHALL 从所有同步目录中移除 symlink 或文件，但保留 LaunchX 本地主副本

### Requirement: Skills 同步
系统 SHALL 在 Provider 切换时自动同步 Skills 状态到所有 apps 对应的目录。

#### Scenario: Provider 切换时的 Skills 同步
- **WHEN** Provider 切换成功完成
- **THEN** 系统 SHALL 遍历所有已启用的 Skills，按每个 Skill 的 apps 字段，确保对应目录中存在 symlink 或文件副本

### Requirement: Skills 管理界面
系统 SHALL 在 Skills 管理界面中增加应用选择器。

#### Scenario: 已安装 Skills 列表中的应用标记
- **WHEN** 用户查看已安装 Skills 列表
- **THEN** 每个 Skill 条目 SHALL 显示其同步到的应用图标（Claude/Codex），用户可点击切换
