import Foundation

/// Claude Code 数据存储管理器
/// 负责读写 JSON 配置文件，支持原子写入
final class ClaudeDataStore {
    static let shared = ClaudeDataStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.launchx.clauddatastore", qos: .userInitiated)

    // MARK: - 目录路径

    /// Claude Code 数据根目录
    let claudeDir: URL

    /// 备份目录
    let backupsDir: URL

    /// Skills 主副本目录
    let skillsDir: URL

    // MARK: - 文件路径

    private var providersFile: URL { claudeDir.appendingPathComponent("providers.json") }
    private var mcpServersFile: URL { claudeDir.appendingPathComponent("mcp_servers.json") }
    private var skillsFile: URL { claudeDir.appendingPathComponent("skills.json") }
    private var skillReposFile: URL { claudeDir.appendingPathComponent("skill_repos.json") }
    private var contextPromptsFile: URL { claudeDir.appendingPathComponent("context_prompts.json") }

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        claudeDir = appSupport.appendingPathComponent("LaunchX/claude", isDirectory: true)
        backupsDir = claudeDir.appendingPathComponent("backups", isDirectory: true)
        skillsDir = claudeDir.appendingPathComponent("skills", isDirectory: true)
        initializeDirectories()
    }

    // MARK: - 目录初始化

    private func initializeDirectories() {
        try? fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    }

    // MARK: - 通用读写

    /// 原子写入 JSON 文件
    func writeJSON<T: Encodable>(_ data: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)

        // 原子写入：先写临时文件，再替换目标文件
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)")
        // 不用 .atomic，直接写入临时文件（避免 .atomic 内部 rename 与后续 moveItem 冲突）
        try jsonData.write(to: tempURL, options: [])
        // 原子替换：如果目标已存在先删除，再将临时文件移动过去
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tempURL, to: url)
    }

    /// 读取 JSON 文件
    func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Provider 操作

    func loadProviders() -> [ClaudeProvider] {
        queue.sync {
            readJSON([ClaudeProvider].self, from: providersFile) ?? []
        }
    }

    func saveProviders(_ providers: [ClaudeProvider]) throws {
        try queue.sync {
            try writeJSON(providers, to: providersFile)
        }
    }

    // MARK: - Context Prompt 操作

    func loadContextPrompts() -> [ContextPrompt] {
        queue.sync {
            readJSON([ContextPrompt].self, from: contextPromptsFile) ?? []
        }
    }

    func saveContextPrompts(_ prompts: [ContextPrompt]) throws {
        try queue.sync {
            try writeJSON(prompts, to: contextPromptsFile)
        }
    }

    // MARK: - MCP Server 操作

    func loadMcpServers() -> [McpServer] {
        queue.sync {
            readJSON([McpServer].self, from: mcpServersFile) ?? []
        }
    }

    func saveMcpServers(_ servers: [McpServer]) throws {
        try queue.sync {
            try writeJSON(servers, to: mcpServersFile)
        }
    }

    // MARK: - Skills 操作

    func loadSkills() -> [ClaudeSkill] {
        queue.sync {
            readJSON([ClaudeSkill].self, from: skillsFile) ?? []
        }
    }

    func saveSkills(_ skills: [ClaudeSkill]) throws {
        try queue.sync {
            try writeJSON(skills, to: skillsFile)
        }
    }

    // MARK: - Skill Repos 操作

    func loadSkillRepos() -> [SkillRepo] {
        queue.sync {
            readJSON([SkillRepo].self, from: skillReposFile) ?? SkillRepo.defaults
        }
    }

    func saveSkillRepos(_ repos: [SkillRepo]) throws {
        try queue.sync {
            try writeJSON(repos, to: skillReposFile)
        }
    }

    // MARK: - 备份操作

    /// 备份 Claude Code 的 settings.json
    func backupClaudeSettings() throws {
        let claudeSettingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard fileManager.fileExists(atPath: claudeSettingsPath.path) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupFile = backupsDir.appendingPathComponent("settings_\(timestamp).json")

        try? fileManager.copyItem(at: claudeSettingsPath, to: backupFile)
        cleanupOldBackups()
    }

    /// 清理旧备份，保留最近 10 个
    private func cleanupOldBackups() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: [.creationDateKey])
            .filter({ $0.path.contains("settings_") })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        else { return }

        if files.count > 10 {
            for file in files.dropFirst(10) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// 获取备份列表
    func listBackups() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: nil)
            .filter { $0.path.contains("settings_") }
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })) ?? []
    }

    /// 备份全局上下文指令文件（CLAUDE.md / AGENTS.md）到 backups/ 目录
    /// 文件不存在时静默跳过（返回 false）
    @discardableResult
    func backupContextFile(for app: AppTarget) throws -> Bool {
        let source = contextFilePath(for: app)
        guard fileManager.fileExists(atPath: source.path) else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let appTag: String
        switch app {
        case .claude: appTag = "claude"
        case .codex: appTag = "codex"
        }
        let backupFile = backupsDir.appendingPathComponent("context_\(appTag)_\(timestamp).md")

        try? fileManager.copyItem(at: source, to: backupFile)
        cleanupOldContextBackups()
        return true
    }

    /// 清理旧的全局上下文备份，每个应用保留最近 10 个
    private func cleanupOldContextBackups() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("context_") })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        else { return }

        // 按 app 分组，各自保留最近 10 个
        for app in AppTarget.allCases {
            let appTag = app == .claude ? "claude" : "codex"
            let appFiles = files.filter { $0.lastPathComponent.contains("_\(appTag)_") }
            if appFiles.count > 10 {
                for file in appFiles.dropFirst(10) {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - Codex 配置路径

    /// Codex 配置根目录
    var codexDir: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Codex config.toml 路径
    var codexConfigPath: URL {
        codexDir.appendingPathComponent("config.toml")
    }

    /// Codex auth.json 路径
    var codexAuthPath: URL {
        codexDir.appendingPathComponent("auth.json")
    }

    /// Codex skills 目录路径（标准 Agent Skills 路径）
    var codexSkillsDir: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
    }

    // MARK: - 全局上下文指令文件路径

    /// Claude Code 全局上下文文件：~/.claude/CLAUDE.md
    var claudeContextFilePath: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/CLAUDE.md")
    }

    /// Codex 全局上下文文件：~/.codex/AGENTS.md
    var codexContextFilePath: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/AGENTS.md")
    }

    /// 按应用返回对应的全局上下文文件路径
    func contextFilePath(for app: AppTarget) -> URL {
        switch app {
        case .claude: return claudeContextFilePath
        case .codex: return codexContextFilePath
        }
    }

    // MARK: - Codex 配置读写

    /// 读取 Codex config.toml
    func readCodexConfig() -> TomlDocument? {
        guard fileManager.fileExists(atPath: codexConfigPath.path),
              let content = try? String(contentsOf: codexConfigPath, encoding: .utf8) else {
            return nil
        }
        return TomlDocument(content: content)
    }

    /// 原子写入 Codex config.toml
    func writeCodexConfig(_ doc: TomlDocument) throws {
        try ensureCodexDir()
        let content = doc.serialize()
        guard let data = content.data(using: .utf8) else { return }
        let tempPath = codexConfigPath.deletingLastPathComponent()
            .appendingPathComponent(".tmp_config_\(UUID().uuidString)")
        do {
            try data.write(to: tempPath, options: [])
            if fileManager.fileExists(atPath: codexConfigPath.path) {
                _ = try? fileManager.replaceItemAt(codexConfigPath, withItemAt: tempPath)
            } else {
                try fileManager.moveItem(at: tempPath, to: codexConfigPath)
            }
        } catch {
            try? fileManager.removeItem(at: tempPath)
            throw error
        }
    }

    /// 读取 Codex auth.json
    func readCodexAuth() -> [String: String]? {
        readJSON([String: String].self, from: codexAuthPath)
    }

    /// 原子写入 Codex auth.json
    func writeCodexAuth(_ auth: [String: String]) throws {
        try ensureCodexDir()
        try writeJSON(auth, to: codexAuthPath)
    }

    /// 确保 Codex 目录存在
    func ensureCodexDir() throws {
        try fileManager.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexSkillsDir, withIntermediateDirectories: true)
    }

    /// 协同原子写入 Codex 配置（auth.json + config.toml）
    func writeCodexAtomic(auth: [String: String], config: TomlDocument) throws {
        try ensureCodexDir()

        // 1. 备份 auth.json
        let authBackup = codexAuthPath.appendingPathExtension("bak")
        if fileManager.fileExists(atPath: codexAuthPath.path) {
            try? fileManager.removeItem(at: authBackup)
            try? fileManager.copyItem(at: codexAuthPath, to: authBackup)
        }

        // 2. 写入 auth.json
        do {
            try writeCodexAuth(auth)
        } catch {
            throw error
        }

        // 3. 写入 config.toml，失败则回滚 auth.json
        do {
            try writeCodexConfig(config)
        } catch {
            // 回滚 auth.json
            if fileManager.fileExists(atPath: authBackup.path) {
                try? fileManager.removeItem(at: codexAuthPath)
                try? fileManager.moveItem(at: authBackup, to: codexAuthPath)
            }
            throw error
        }

        // 4. 清理备份
        try? fileManager.removeItem(at: authBackup)
    }
}
