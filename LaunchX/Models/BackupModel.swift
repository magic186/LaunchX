import Foundation

/// 高级扩展配置备份模型，仅包含高级扩展模块的配置和数据
struct BackupModel: Codable {
    /// 备份元数据
    struct Metadata: Codable {
        let version: String
        let exportDate: Date
        let appVersion: String?
        let deviceName: String?
    }

    let metadata: Metadata

    // 高级扩展 - 剪贴板
    let clipboardSettings: ClipboardSettings

    // 高级扩展 - Snippets
    let snippetSettings: SnippetSettings
    let snippets: [SnippetItem]

    // 高级扩展 - AI 翻译
    let aiTranslateSettings: AITranslateSettings

    // 高级扩展 - 书签搜索
    let bookmarkSettings: BookmarkSettings

    // 高级扩展 - 2FA 短信
    let twoFactorAuthSettings: TwoFactorAuthSettings

    // 高级扩展 - 终端
    let terminalSettings: TerminalSettings

    // 高级扩展 - 提醒事项
    let remindersSettings: RemindersSettings

    // 高级扩展 - Claude Code
    let claudeCodeSwitcherSettings: ClaudeCodeSwitcherSettings
    let claudeProviders: [ClaudeProvider]
    let mcpServers: [McpServer]?

    /// 备份文件版本校验错误
    struct UnsupportedVersionError: Error, LocalizedError {
        let version: String
        var errorDescription: String? {
            "不支持的备份版本（\(version)），请使用 v2.0 格式导出的文件"
        }
    }

    /// 自定义解码器，校验版本号
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = try container.decode(Metadata.self, forKey: .metadata)

        guard metadata.version == "2.0" else {
            throw UnsupportedVersionError(version: metadata.version)
        }

        self.metadata = metadata
        clipboardSettings = try container.decode(ClipboardSettings.self, forKey: .clipboardSettings)
        snippetSettings = try container.decode(SnippetSettings.self, forKey: .snippetSettings)
        snippets = try container.decode([SnippetItem].self, forKey: .snippets)
        aiTranslateSettings = try container.decode(AITranslateSettings.self, forKey: .aiTranslateSettings)
        bookmarkSettings = try container.decode(BookmarkSettings.self, forKey: .bookmarkSettings)
        twoFactorAuthSettings = try container.decode(TwoFactorAuthSettings.self, forKey: .twoFactorAuthSettings)
        terminalSettings = try container.decode(TerminalSettings.self, forKey: .terminalSettings)
        remindersSettings = try container.decode(RemindersSettings.self, forKey: .remindersSettings)
        claudeCodeSwitcherSettings = try container.decode(ClaudeCodeSwitcherSettings.self, forKey: .claudeCodeSwitcherSettings)
        claudeProviders = try container.decode([ClaudeProvider].self, forKey: .claudeProviders)
        mcpServers = try container.decodeIfPresent([McpServer].self, forKey: .mcpServers)
    }

    // 用于 createCurrent() 的直接初始化
    init(
        metadata: Metadata,
        clipboardSettings: ClipboardSettings,
        snippetSettings: SnippetSettings,
        snippets: [SnippetItem],
        aiTranslateSettings: AITranslateSettings,
        bookmarkSettings: BookmarkSettings,
        twoFactorAuthSettings: TwoFactorAuthSettings,
        terminalSettings: TerminalSettings,
        remindersSettings: RemindersSettings,
        claudeCodeSwitcherSettings: ClaudeCodeSwitcherSettings,
        claudeProviders: [ClaudeProvider],
        mcpServers: [McpServer]? = nil
    ) {
        self.metadata = metadata
        self.clipboardSettings = clipboardSettings
        self.snippetSettings = snippetSettings
        self.snippets = snippets
        self.aiTranslateSettings = aiTranslateSettings
        self.bookmarkSettings = bookmarkSettings
        self.twoFactorAuthSettings = twoFactorAuthSettings
        self.terminalSettings = terminalSettings
        self.remindersSettings = remindersSettings
        self.claudeCodeSwitcherSettings = claudeCodeSwitcherSettings
        self.claudeProviders = claudeProviders
        self.mcpServers = mcpServers
    }
}

extension BackupModel {
    /// 创建当前高级扩展配置的备份
    static func createCurrent() -> BackupModel {
        BackupModel(
            metadata: Metadata(
                version: "2.0",
                exportDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                deviceName: Host.current().localizedName
            ),
            clipboardSettings: ClipboardSettings.load(),
            snippetSettings: SnippetSettings.load(),
            snippets: SnippetService.shared.snippets,
            aiTranslateSettings: AITranslateSettings.load(),
            bookmarkSettings: BookmarkSettings.load(),
            twoFactorAuthSettings: TwoFactorAuthSettings.load(),
            terminalSettings: TerminalSettings.load(),
            remindersSettings: RemindersSettings.load(),
            claudeCodeSwitcherSettings: ClaudeCodeSwitcherSettings.load(),
            claudeProviders: ClaudeDataStore.shared.loadProviders(),
            mcpServers: ClaudeDataStore.shared.loadMcpServers()
        )
    }

    /// 将备份应用到当前系统
    func apply() throws {
        // 逐一还原各高级扩展模块配置
        clipboardSettings.save()
        snippetSettings.save()
        aiTranslateSettings.save()
        bookmarkSettings.save()
        twoFactorAuthSettings.save()
        terminalSettings.save()
        remindersSettings.save()
        claudeCodeSwitcherSettings.save()

        // 还原 Claude Providers
        try? ClaudeDataStore.shared.saveProviders(claudeProviders)

        // 还原 MCP 服务器配置（仅当备份中包含时）
        if let mcpServers {
            try? ClaudeDataStore.shared.saveMcpServers(mcpServers)
            try? ClaudeMcpService.shared.syncAll()
        }

        // 保存 snippets 数组到文件
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let snippetsDir = appSupport.appendingPathComponent("LaunchX/Snippets", isDirectory: true)
        try? FileManager.default.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
        let snippetsURL = snippetsDir.appendingPathComponent("snippets.json")

        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: snippetsURL)
        }

        // 触发全局刷新通知
        NotificationCenter.default.post(
            name: NSNotification.Name("AppConfigDidImport"), object: nil)
    }
}
