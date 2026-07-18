## ADDED Requirements

### Requirement: Context Prompt 数据模型
系统 SHALL 定义 `ContextPrompt` 数据模型，包含以下字段：
- id: 唯一标识符（UUID）
- name: 上下文预设显示名称
- content: Markdown 格式的全局上下文提示词正文
- apps: 适用应用集合（`Set<AppTarget>`，取值 `.claude` 和/或 `.codex`）
- isCurrent: 是否为当前激活的预设
- sortIndex: 排序索引
- createdAt: 创建时间戳

`ContextPrompt` SHALL 实现向后兼容解码：当历史数据缺失 `apps` 字段时，默认解析为 `[.claude]`。

#### Scenario: 创建 Context Prompt 实例
- **GIVEN** 用户在编辑表单填写名称、Markdown 正文并选择适用应用
- **WHEN** 用户提交保存
- **THEN** 系统生成唯一 id，创建 `ContextPrompt` 记录，`content` 为用户输入的 Markdown 正文

#### Scenario: 向后兼容解码
- **GIVEN** `context_prompts.json` 中某条记录缺少 `apps` 字段
- **WHEN** 系统加载该文件
- **THEN** 该记录的 `apps` SHALL 被解析为 `[.claude]`，不抛出解码错误

### Requirement: Context Prompt 持久化
系统 SHALL 将所有 `ContextPrompt` 记录持久化到 `~/Library/Application Support/LaunchX/claude/context_prompts.json`，写入采用原子方式（临时文件 + `replaceItemAt`）。

#### Scenario: 持久化变更
- **GIVEN** Context Prompt 列表发生增删改
- **WHEN** 变更完成后
- **THEN** 系统 SHALL 原子写入最新的 `[ContextPrompt]` 数组到 `context_prompts.json`

#### Scenario: 首次加载初始化
- **GIVEN** `context_prompts.json` 不存在
- **WHEN** 应用首次加载上下文预设
- **THEN** 系统 SHALL 以空数组（或内置预设）初始化，且不触碰任何全局指令文件

### Requirement: 内置预设系统
系统 SHALL 提供内置 Context Prompt 预设库，每条预设包含 id、name、Markdown 正文 content、适用 apps。预设 SHALL 按分类分组展示，用户可基于任一预设一键创建为可编辑的 `ContextPrompt`。

#### Scenario: 从内置预设创建
- **GIVEN** 用户在预设选择器选择某个内置预设
- **WHEN** 用户确认创建
- **THEN** 系统 SHALL 基于该预设生成一条新的可编辑 `ContextPrompt`（生成新 id、`isCurrent=false`），并加入列表

#### Scenario: 预设列表展示
- **GIVEN** 用户打开「添加上下文」界面
- **WHEN** 界面渲染
- **THEN** 系统 SHALL 按分类分组展示所有内置预设供选择

### Requirement: Context Prompt CRUD 操作
系统 SHALL 支持对 Context Prompt 的完整增删改查操作。

#### Scenario: 添加自定义 Context Prompt
- **GIVEN** 用户填写名称与 Markdown 正文并保存
- **WHEN** 提交表单
- **THEN** 系统 SHALL 创建新记录并持久化到 `context_prompts.json`

#### Scenario: 编辑 Context Prompt
- **GIVEN** 用户修改已有预设的名称或正文
- **WHEN** 保存修改
- **THEN** 系统 SHALL 更新该记录。若被编辑的预设当前处于激活态，系统 SHALL 同步将其新正文写入对应的全局指令文件

#### Scenario: 复制 Context Prompt
- **GIVEN** 用户选择复制某条预设
- **WHEN** 执行复制
- **THEN** 系统 SHALL 创建一条新记录（新 id、`isCurrent=false`、名称后缀标识为副本）并持久化

#### Scenario: 删除非激活 Context Prompt
- **GIVEN** 用户删除一个未激活的预设
- **WHEN** 确认删除
- **THEN** 系统 SHALL 从 `context_prompts.json` 移除该记录

#### Scenario: 删除当前激活的 Context Prompt
- **GIVEN** 用户尝试删除一个处于 `isCurrent=true` 的预设
- **WHEN** 触发删除
- **THEN** 系统 SHALL 拒绝删除并提示用户先切换到其他预设

#### Scenario: 查询 Context Prompt 列表
- **GIVEN** 用户打开上下文管理界面
- **WHEN** 界面渲染
- **THEN** 系统 SHALL 按 `apps` 过滤展示对应应用的预设，当前激活项标记为选中状态

### Requirement: Context Prompt 切换
系统 SHALL 支持在多个 Context Prompt 之间切换，切换时 SHALL 按 `apps` 范围更新激活态，并将激活预设的正文写入对应的全局指令文件。

每条 Context Prompt 仅维护单个 `isCurrent` 标志；当前激活项按应用分别计算：当前 Claude 预设 = `apps.contains(.claude) && isCurrent`，当前 Codex 预设 = `apps.contains(.codex) && isCurrent`。

#### Scenario: 切换到新预设
- **GIVEN** 用户选择一个非当前激活的预设 P 并点击「启用」
- **WHEN** 系统执行切换
- **THEN** 系统 SHALL 执行以下步骤：
  1. 对当前 `prompts` 列表做快照（用于失败回滚）
  2. 备份现有全局指令文件（若存在）到 `backups/` 目录
  3. 仅对 `apps` 与 P 的 `apps` 存在交集的预设，将 `isCurrent` 置为「是否等于 P 的 id」
  4. 将 P 的正文 content 原子写入对应全局指令文件（apps 含 `.claude` → `~/.claude/CLAUDE.md`；含 `.codex` → `~/.codex/AGENTS.md`）
  5. 持久化 `context_prompts.json`
  6. 若写入失败，SHALL 用快照回滚内存状态并抛出错误

#### Scenario: 独立激活不同应用
- **GIVEN** 预设 A 的 apps=`{.claude}` 已激活，预设 B 的 apps=`{.codex}`
- **WHEN** 用户启用预设 B
- **THEN** 预设 A 的 `isCurrent` 保持不变，预设 B 的 `isCurrent` 置为 true；最终 Claude 侧激活 A、Codex 侧激活 B

#### Scenario: 跨应用预设同时接管两侧
- **GIVEN** 预设 C 的 apps=`{.claude, .codex}`
- **WHEN** 用户启用预设 C
- **THEN** 系统 SHALL 取消当前 Claude 激活项与 Codex 激活项，将 C 置为两侧激活，并分别写入 `~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md`

### Requirement: 全局指令文件写入与备份
系统在写入 `~/.claude/CLAUDE.md` 或 `~/.codex/AGENTS.md` 时 SHALL 采用原子写入（临时文件 + `replaceItemAt`/`moveItem`），并在写入内容末尾追加不可见的管理标记，标记 SHALL 至少包含固定标识与来源预设 id。

#### Scenario: 首次接管用户手写文件
- **GIVEN** 目标全局指令文件已存在且不含管理标记（即非 LaunchX 托管）
- **WHEN** 系统准备写入激活预设正文
- **THEN** 系统 SHALL 先将该文件备份到 `backups/` 目录（带时间戳）后再写入，绝不静默覆盖

#### Scenario: 管理已托管文件
- **GIVEN** 目标文件已含 LaunchX 管理标记
- **WHEN** 系统写入新激活预设正文
- **THEN** 系统 SHALL 替换文件内容并更新管理标记中的来源预设 id（同时记录备份以便撤销）

#### Scenario: 管理标记缺失的容错
- **GIVEN** 目标文件存在但管理标记被删除/损坏
- **WHEN** 系统准备写入
- **THEN** 系统 SHALL 按「用户手写」处理（先备份再写入），不因标记缺失而崩溃或静默覆盖
