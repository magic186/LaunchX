import Combine
import Foundation

/// Claude Code MCP 服务器管理服务
@MainActor
final class ClaudeMcpService: ObservableObject {
    static let shared = ClaudeMcpService()

    @Published var servers: [McpServer] = []

    private let store = ClaudeDataStore.shared
    private let fileManager = FileManager.default

    private init() {
        loadData()
    }

    // MARK: - 数据加载

    private func loadData() {
        servers = store.loadMcpServers()
    }

    private func persistData() throws {
        try store.saveMcpServers(servers)
    }

    // MARK: - Claude Code MCP 配置路径

    private var claudeJsonPath: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    // MARK: - 验证

    /// 验证 MCP 服务器配置
    func validateConfig(_ config: [String: AnyCodable]) -> String? {
        let typeStr = config["type"]?.stringValue ?? ""
        if typeStr == "http" || typeStr == "sse" {
            guard let url = config["url"]?.stringValue, !url.isEmpty else {
                return "HTTP/SSE 类型服务器必须包含 url 字段"
            }
            return nil
        }
        // stdio（默认）
        guard let command = config["command"]?.stringValue, !command.isEmpty else {
            return "stdio 类型服务器必须包含 command 字段"
        }
        return nil
    }

    // MARK: - CRUD

    /// 添加 MCP
    @discardableResult
    func addServer(_ server: McpServer) throws -> String? {
        if let error = validateConfig(server.serverConfig) {
            return error
        }
        servers.append(server)
        try persistData()
        if server.isEnabled {
            try syncAll()
        }
        return nil
    }

    /// 更新 MCP
    func updateServer(_ server: McpServer) throws {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        try persistData()
        if server.isEnabled {
            try syncAll()
        }
    }

    /// 删除 MCP
    func deleteServer(_ server: McpServer) throws {
        servers.removeAll { $0.id == server.id }
        try persistData()
        try syncAll()
    }

    // MARK: - 启用/禁用

    /// 切换 MCP 服务器启用状态
    func toggleEnabled(_ server: McpServer) throws {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].isEnabled.toggle()
        try persistData()
        try syncAll()
    }

    // MARK: - 同步

    /// 按各服务器的 apps 字段分发同步
    func syncAll() throws {
        // 收集需要同步到 Claude 的服务器
        let claudeServers = servers.filter { $0.isEnabled && $0.apps.contains(.claude) }
        // 收集需要同步到 Codex 的服务器
        let codexServers = servers.filter { $0.isEnabled && $0.apps.contains(.codex) }

        try syncToClaude(servers: claudeServers)
        try syncToCodex(servers: codexServers)
    }

    /// 读取 ~/.claude.json
    func readClaudeJson() -> [String: Any]? {
        guard fileManager.fileExists(atPath: claudeJsonPath.path),
            let data = try? Data(contentsOf: claudeJsonPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    /// 将指定的 MCP 服务器同步到 ~/.claude.json
    private func syncToClaude(servers: [McpServer]) throws {
        var config = readClaudeJson() ?? [:]

        var mcpServers: [String: Any] = [:]
        for server in servers {
            var serverConfig: [String: Any] = [:]
            for (key, value) in server.serverConfig {
                serverConfig[key] = value.value
            }
            mcpServers[server.name] = serverConfig
        }

        config["mcpServers"] = mcpServers

        let jsonData = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys])

        let tempPath = claudeJsonPath.deletingLastPathComponent()
            .appendingPathComponent(".tmp_claude_json_\(UUID().uuidString)")
        do {
            let dir = claudeJsonPath.deletingLastPathComponent()
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            try jsonData.write(to: tempPath, options: [])
            if fileManager.fileExists(atPath: claudeJsonPath.path) {
                _ = try? fileManager.replaceItemAt(claudeJsonPath, withItemAt: tempPath)
            } else {
                try fileManager.moveItem(at: tempPath, to: claudeJsonPath)
            }
        } catch {
            try? fileManager.removeItem(at: tempPath)
            throw error
        }
    }

    /// 将指定的 MCP 服务器同步到 ~/.codex/config.toml
    /// Codex MCP TOML 格式:
    ///   [mcp_servers.name]
    ///   command = "npx"
    ///   args = ["-y", "server"]
    ///   env = { "KEY" = "value" }
    private func syncToCodex(servers: [McpServer]) throws {
        let doc = store.readCodexConfig() ?? TomlDocument()

        // 移除旧的 mcp_servers 段
        let existingSections = doc.sectionsWithPrefix("mcp_servers.")
        for section in existingSections {
            doc.removeSection(section)
        }

        // 写入新的 mcp_servers 段
        for server in servers {
            let section = "mcp_servers.\(server.name)"
            for (key, value) in server.serverConfig {
                let tomlValue = anyCodableToToml(value)
                doc.setRaw(key, value: tomlValue, in: section)
            }
        }

        try store.ensureCodexDir()
        try store.writeCodexConfig(doc)
    }

    /// 将 AnyCodable 值转换为 TOML 格式字符串
    private func anyCodableToToml(_ value: AnyCodable) -> String {
        if let str = value.stringValue {
            return str.tomlQuoted
        }
        if let bool = value.value as? Bool {
            return bool ? "true" : "false"
        }
        if let num = value.value as? Int {
            return String(num)
        }
        if let num = value.value as? Double {
            return String(num)
        }
        if let dict = value.value as? [String: Any] {
            let items = dict.map { k, v in
                "\(k) = \(anyCodableToToml(AnyCodable(v)))"
            }.joined(separator: ", ")
            return "{ \(items) }"
        }
        let arr = value.arrayValue
        if !arr.isEmpty {
            let items = arr.map { anyCodableToToml($0) }.joined(separator: ", ")
            return "[\(items)]"
        }
        return String(describing: value.value).tomlQuoted
    }

    // MARK: - 导入

    /// 从 ~/.claude.json 导入 MCP
    func importFromClaude() -> Int {
        guard let config = readClaudeJson(),
            let mcpServers = config["mcpServers"] as? [String: Any]
        else {
            return 0
        }

        var imported = 0
        for (name, serverConfig) in mcpServers {
            if servers.contains(where: { $0.name == name }) {
                // 已存在，仅添加 .claude 到 apps
                if let idx = servers.firstIndex(where: { $0.name == name }) {
                    servers[idx].apps.insert(.claude)
                }
                continue
            }

            var config: [String: AnyCodable] = [:]
            if let dict = serverConfig as? [String: Any] {
                for (key, value) in dict {
                    config[key] = AnyCodable(value)
                }
            }

            if validateConfig(config) != nil { continue }

            let server = McpServer(
                name: name,
                serverConfig: config,
                isEnabled: true,
                apps: [.claude]
            )
            servers.append(server)
            imported += 1
        }

        if imported > 0 {
            try? persistData()
        }
        return imported
    }

    /// 从 ~/.codex/config.toml 导入 MCP
    func importFromCodex() -> Int {
        guard let doc = store.readCodexConfig() else { return 0 }

        let sections = doc.sectionsWithPrefix("mcp_servers.")
        var imported = 0

        for section in sections {
            let name = section.replacingOccurrences(of: "mcp_servers.", with: "")

            if servers.contains(where: { $0.name == name }) {
                // 已存在，仅添加 .codex 到 apps
                if let idx = servers.firstIndex(where: { $0.name == name }) {
                    servers[idx].apps.insert(.codex)
                }
                continue
            }

            let keyValues = doc.getAllKeyValues(in: section)
            var config: [String: AnyCodable] = [:]
            for (key, value) in keyValues {
                config[key] = AnyCodable(value)
            }

            if validateConfig(config) != nil { continue }

            let server = McpServer(
                name: name,
                serverConfig: config,
                isEnabled: true,
                apps: [.codex]
            )
            servers.append(server)
            imported += 1
        }

        if imported > 0 {
            try? persistData()
        }
        return imported
    }
}
