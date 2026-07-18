## 1. 数据模型扩展

- [x] 1.1 定义 `AppTarget` 枚举（claude / codex），支持 Codable、CaseIterable、Hashable
- [x] 1.2 为 `ClaudeProvider` 添加 `apps: Set<AppTarget>` 字段，默认值 `[.claude]`，实现向后兼容解码
- [x] 1.3 为 `McpServer` 添加 `apps: Set<AppTarget>` 字段，默认值 `[.claude]`，实现向后兼容解码
- [x] 1.4 为 `ClaudeSkill` 添加 `apps: Set<AppTarget>` 字段，默认值 `[.claude]`，实现向后兼容解码

## 2. TOML 处理工具

- [x] 2.1 实现轻量 TOML 解析器：支持顶层键值对、`[section]`、`[nested.section]` 格式的读取
- [x] 2.2 实现 TOML 生成/编辑器：支持修改指定 section 的键值对，保留非管理段的内容和注释
- [x] 2.3 编写 TOML 解析/生成的单元测试（覆盖嵌套段、特殊字符、空文件等场景）

## 3. Codex 配置文件读写

- [x] 3.1 在 `ClaudeDataStore` 中添加 Codex 配置路径常量（config.toml、auth.json、skills/ 目录）
- [x] 3.2 实现 `readCodexConfig()` 方法：解析 `~/.codex/config.toml` 提取 model 和 model_providers 段
- [x] 3.3 实现 `writeCodexConfig()` 方法：语法保留编辑 `~/.codex/config.toml`，原子写入
- [x] 3.4 实现 `readCodexAuth()` / `writeCodexAuth()` 方法：读写 `~/.codex/auth.json`
- [x] 3.5 实现协同原子写入：auth.json + config.toml 写入时，失败回滚机制

## 4. Codex Provider 同步

- [x] 4.1 在 `ClaudeProviderService` 中实现 Provider → Codex 配置映射（CODEX_API_KEY → OPENAI_API_KEY、CODEX_BASE_URL → model_providers、CODEX_MODEL → model）
- [x] 4.2 实现 Base URL 自动补全 `/v1` 后缀逻辑
- [x] 4.3 修改 `switchProvider()` 方法：切换时如果新 Provider apps 包含 .codex，同步写入 Codex 配置
- [x] 4.4 实现 `importDefaultCodexConfig()`：首次使用时从 `~/.codex/` 导入已有配置

## 5. Codex MCP 同步

- [x] 5.1 在 `ClaudeMcpService` 中实现单个 MCP 服务器到 Codex config.toml `[mcp_servers]` 段的同步
- [x] 5.2 修改 `syncToClaude()` 为 `syncAll()`：按每个服务器的 apps 字段分发同步到 Claude 和/或 Codex
- [x] 5.3 修改 CRUD 方法（add/update/delete）：操作后按 apps 字段同步到对应配置文件
- [x] 5.4 实现从 Codex config.toml 导入 MCP 服务器的方法

## 6. Codex Skills 同步

- [x] 6.1 在 `ClaudeSkillService` 中实现 Skill 到 `~/.codex/skills/` 目录的 symlink 创建/移除
- [x] 6.2 修改 `syncAllEnabled()` 方法：按每个 Skill 的 apps 字段同步到对应目录
- [x] 6.3 修改 install/uninstall/enable/disable 方法：操作时同时处理所有 apps 对应的目录
- [x] 6.4 实现从 `~/.codex/skills/` 目录导入未管理 Skills 的方法
- [x] 6.5 实现 `~/.codex/skills/` 目录的自动创建（首次同步时）

## 7. UI 扩展

- [x] 7.1 创建 `AppTargetPickerView` 组件：显示 Claude/Codex 两个可切换的应用图标
- [x] 7.2 在 `ProviderListView` 和 `ProviderFormView` 中集成 AppTargetPickerView
- [x] 7.3 在 `McpServerListView` 和 `McpServerFormView` 中集成 AppTargetPickerView
- [x] 7.4 在 `SkillListView` 中集成 AppTargetPickerView
- [x] 7.5 在 Provider 编辑表单中添加 Codex 专用字段（CODEX_API_KEY、CODEX_BASE_URL、CODEX_MODEL）输入区，仅当 apps 包含 .codex 时显示

## 8. 集成测试与验证

- [x] 8.1 验证已有 Claude Code 功能不受影响（向后兼容：apps 默认 [.claude]）
- [x] 8.2 验证 Codex Provider 切换时 config.toml 和 auth.json 正确写入
- [x] 8.3 验证 Codex MCP 同步：启禁用和 CRUD 操作正确更新 config.toml
- [x] 8.4 验证 Codex Skills 同步：安装/卸载/启禁用正确操作 ~/.codex/skills/ 目录
- [x] 8.5 验证 TOML 语法保留编辑：手动编辑的注释和非管理段内容不被覆盖
