import Foundation

/// Claude Code Skill 数据模型
struct ClaudeSkill: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var skillDescription: String?
    var directory: String
    var repoOwner: String
    var repoName: String
    var repoBranch: String
    var readmeUrl: String?
    var isEnabled: Bool
    var installedAt: Date
    var apps: Set<AppTarget>

    init(
        id: UUID = UUID(),
        name: String,
        skillDescription: String? = nil,
        directory: String,
        repoOwner: String = "",
        repoName: String = "",
        repoBranch: String = "main",
        readmeUrl: String? = nil,
        isEnabled: Bool = true,
        installedAt: Date = Date(),
        apps: Set<AppTarget> = [.claude]
    ) {
        self.id = id
        self.name = name
        self.skillDescription = skillDescription
        self.directory = directory
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.repoBranch = repoBranch
        self.readmeUrl = readmeUrl
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, skillDescription, directory, repoOwner, repoName
        case repoBranch, readmeUrl, isEnabled, installedAt, apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        skillDescription = try container.decodeIfPresent(String.self, forKey: .skillDescription)
        directory = try container.decode(String.self, forKey: .directory)
        repoOwner = try container.decode(String.self, forKey: .repoOwner)
        repoName = try container.decode(String.self, forKey: .repoName)
        repoBranch = try container.decode(String.self, forKey: .repoBranch)
        readmeUrl = try container.decodeIfPresent(String.self, forKey: .readmeUrl)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        apps = (try? container.decode(Set<AppTarget>.self, forKey: .apps)) ?? [.claude]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(skillDescription, forKey: .skillDescription)
        try container.encode(directory, forKey: .directory)
        try container.encode(repoOwner, forKey: .repoOwner)
        try container.encode(repoName, forKey: .repoName)
        try container.encode(repoBranch, forKey: .repoBranch)
        try container.encodeIfPresent(readmeUrl, forKey: .readmeUrl)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(installedAt, forKey: .installedAt)
        try container.encode(apps, forKey: .apps)
    }

    /// 来源仓库全名
    var repoFullName: String {
        "\(repoOwner)/\(repoName)"
    }

    /// SKILL.md 内容的 GitHub Raw URL
    var skillRawUrl: String {
        "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/\(repoBranch)/\(directory)/SKILL.md"
    }

    static func == (lhs: ClaudeSkill, rhs: ClaudeSkill) -> Bool {
        lhs.id == rhs.id
    }
}
