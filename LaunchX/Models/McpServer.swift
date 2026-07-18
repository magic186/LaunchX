import Foundation

/// MCP 服务器类型
enum McpServerType: String, CaseIterable {
    case stdio
    case http
    case sse

    var displayName: String {
        switch self {
        case .stdio: return "stdio"
        case .http: return "HTTP"
        case .sse: return "SSE"
        }
    }
}

/// Claude Code MCP 服务器数据模型
struct McpServer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var serverConfig: [String: AnyCodable]
    var serverDescription: String?
    var homepage: String?
    var docs: String?
    var tags: [String]
    var isEnabled: Bool
    var apps: Set<AppTarget>

    var serverType: McpServerType {
        if serverConfig["url"] != nil {
            return .sse
        }
        return .stdio
    }

    var configSummary: String {
        switch serverType {
        case .stdio:
            let command = serverConfig["command"]?.stringValue ?? ""
            let args = (serverConfig["args"]?.arrayValue ?? []).compactMap { $0.stringValue }.joined(separator: " ")
            return args.isEmpty ? command : command
        case .http, .sse:
            return serverConfig["url"]?.stringValue ?? ""
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        serverConfig: [String: AnyCodable] = [:],
        serverDescription: String? = nil,
        homepage: String? = nil,
        docs: String? = nil,
        tags: [String] = [],
        isEnabled: Bool = true,
        apps: Set<AppTarget> = [.claude]
    ) {
        self.id = id
        self.name = name
        self.serverConfig = serverConfig
        self.serverDescription = serverDescription
        self.homepage = homepage
        self.docs = docs
        self.tags = tags
        self.isEnabled = isEnabled
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, serverConfig, serverDescription, homepage, docs
        case tags, isEnabled, apps
    }

    // 向后兼容：apps 字段缺失时默认为 [.claude]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        serverConfig = try container.decode([String: AnyCodable].self, forKey: .serverConfig)
        serverDescription = try container.decodeIfPresent(String.self, forKey: .serverDescription)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        docs = try container.decodeIfPresent(String.self, forKey: .docs)
        tags = try container.decode([String].self, forKey: .tags)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        apps = (try? container.decode(Set<AppTarget>.self, forKey: .apps)) ?? [.claude]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverConfig, forKey: .serverConfig)
        try container.encodeIfPresent(serverDescription, forKey: .serverDescription)
        try container.encodeIfPresent(homepage, forKey: .homepage)
        try container.encodeIfPresent(docs, forKey: .docs)
        try container.encode(tags, forKey: .tags)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(apps, forKey: .apps)
    }

    static func == (lhs: McpServer, rhs: McpServer) -> Bool {
        lhs.id == rhs.id
    }
}

