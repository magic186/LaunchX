import Foundation

/// Skill 仓库配置
struct SkillRepo: Identifiable, Codable, Equatable {
    let id: UUID
    var owner: String
    var name: String
    var branch: String
    var isEnabled: Bool
    var apps: Set<AppTarget>

    var idString: String { "\(owner)/\(name)" }

    init(
        id: UUID = UUID(),
        owner: String,
        name: String,
        branch: String = "main",
        isEnabled: Bool = true,
        apps: Set<AppTarget> = [.claude]
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.branch = branch
        self.isEnabled = isEnabled
        self.apps = apps
    }

    static func == (lhs: SkillRepo, rhs: SkillRepo) -> Bool {
        lhs.owner == rhs.owner && lhs.name == rhs.name
    }

    // 向后兼容：apps 字段缺失时默认为 [.claude]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        owner = try container.decode(String.self, forKey: .owner)
        name = try container.decode(String.self, forKey: .name)
        branch = try container.decode(String.self, forKey: .branch)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        apps = (try? container.decode(Set<AppTarget>.self, forKey: .apps)) ?? [.claude]
    }

    /// Claude Code 默认仓库
    static let claudeDefaults: [SkillRepo] = [
        SkillRepo(owner: "anthropics", name: "skills", apps: [.claude])
    ]

    /// Codex 默认仓库
    static let codexDefaults: [SkillRepo] = [
        SkillRepo(owner: "openai", name: "skills", apps: [.codex])
    ]

    /// 所有默认仓库（向后兼容）
    static let defaults: [SkillRepo] = claudeDefaults + codexDefaults
}
