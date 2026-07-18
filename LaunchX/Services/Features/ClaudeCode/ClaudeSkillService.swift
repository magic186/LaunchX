import Foundation
import Combine

/// Claude Code Skills 管理服务
@MainActor
final class ClaudeSkillService: ObservableObject {
    static let shared = ClaudeSkillService()

    @Published var skills: [ClaudeSkill] = []
    @Published var repos: [SkillRepo] = []
    @Published var discoveredSkills: [DiscoveredSkill] = []
    @Published var isLoading = false

    private let store = ClaudeDataStore.shared
    private let fileManager = FileManager.default

    private init() {
        loadData()
    }

    // MARK: - 路径

    /// ~/.claude/skills/ 目标目录
    private var claudeSkillsDir: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
    }

    /// ~/.codex/skills/ 目标目录
    private var codexSkillsDir: URL {
        store.codexSkillsDir
    }

    /// LaunchX 本地主副本目录
    private var localSkillsDir: URL {
        store.skillsDir
    }

    // MARK: - 数据加载

    private func loadData() {
        skills = store.loadSkills()
        repos = store.loadSkillRepos()
    }

    private func persistSkills() throws {
        try store.saveSkills(skills)
    }

    private func persistRepos() {
        try? store.saveSkillRepos(repos)
    }

    // MARK: - 仓库管理

    /// 初始化默认仓库（补充缺失的）
    func initDefaultRepos() {
        for defaultRepo in SkillRepo.defaults {
            if !repos.contains(where: { $0.owner == defaultRepo.owner && $0.name == defaultRepo.name }) {
                repos.append(defaultRepo)
            }
        }
        persistRepos()
    }

    /// 添加自定义仓库
    func addRepo(owner: String, name: String, branch: String = "main", apps: Set<AppTarget> = [.claude]) {
        let repo = SkillRepo(owner: owner, name: name, branch: branch, apps: apps)
        if !repos.contains(where: { $0.owner == owner && $0.name == name }) {
            repos.append(repo)
            persistRepos()
        }
    }

    /// 移除仓库
    func removeRepo(_ repo: SkillRepo) {
        repos.removeAll { $0.id == repo.id }
        persistRepos()
    }

    // MARK: - Skills 发现

    /// 已发现的 Skill（还未安装）
    struct DiscoveredSkill: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let directory: String
        let repoOwner: String
        let repoName: String
        let repoBranch: String
        let rawUrl: String

        var isInstalled: Bool = false
    }

    /// 从仓库发现可用 Skills（并行请求 + 增量更新）
    /// - Parameter appTarget: 只从指定 app 的仓库发现，nil 表示全部
    func discoverSkills(for appTarget: AppTarget? = nil) async {
        isLoading = true
        defer { isLoading = false }

        discoveredSkills = []

        var enabledRepos = repos.filter { $0.isEnabled }
        if let appTarget = appTarget {
            enabledRepos = enabledRepos.filter { $0.apps.contains(appTarget) }
        }
        guard !enabledRepos.isEmpty else { return }

        await withTaskGroup(of: [DiscoveredSkill].self) { group in
            for repo in enabledRepos {
                group.addTask { [weak self] in
                    guard let self = self else { return [] }
                    return await self.discoverSkillsFromRepo(repo)
                }
            }

            // 每完成一个仓库就增量更新 UI
            for await repoSkills in group {
                discoveredSkills.append(contentsOf: repoSkills)
                discoveredSkills.sort { $0.name.lowercased() < $1.name.lowercased() }
            }
        }
    }

    /// 从单个仓库发现 Skills
    private func discoverSkillsFromRepo(_ repo: SkillRepo) async -> [DiscoveredSkill] {
        let apiUrl = "https://api.github.com/repos/\(repo.owner)/\(repo.name)/git/trees/\(repo.branch)?recursive=1"

        guard let url = URL(string: apiUrl) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("ClaudeSkillService: Failed to fetch tree for \(repo.owner)/\(repo.name): \(error.localizedDescription)")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse else { return [] }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 403 {
                print("ClaudeSkillService: GitHub API rate limit exceeded for \(repo.owner)/\(repo.name) (HTTP 403)")
            } else {
                print("ClaudeSkillService: GitHub API returned \(httpResponse.statusCode) for \(repo.owner)/\(repo.name)")
            }
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            print("ClaudeSkillService: Failed to parse tree JSON for \(repo.owner)/\(repo.name)")
            return []
        }

        let skillFiles = tree.filter { item in
            (item["path"] as? String)?.hasSuffix("SKILL.md") == true
        }

        // 捕获当前已安装 skills 快照，避免在子 Task 中跨 actor 访问
        let currentSkills = self.skills

        // 并行下载所有 SKILL.md 内容
        var repoSkills: [DiscoveredSkill] = await withTaskGroup(of: DiscoveredSkill?.self) { group in
            for file in skillFiles {
                guard let path = file["path"] as? String else { continue }
                let directory = path.replacingOccurrences(of: "/SKILL.md", with: "")
                let rawUrl = "https://raw.githubusercontent.com/\(repo.owner)/\(repo.name)/\(repo.branch)/\(path)"

                group.addTask { [weak self] in
                    guard let self = self else { return nil }

                    var skillName = directory.components(separatedBy: "/").last ?? directory
                    var skillDesc = ""

                    if let contentUrl = URL(string: rawUrl) {
                        if let contentData = try? await URLSession.shared.data(from: contentUrl).0,
                           let content = String(data: contentData, encoding: .utf8) {
                            if let metadata = self.parseYAMLFrontmatter(content) {
                                skillName = metadata.name ?? skillName
                                skillDesc = metadata.description ?? ""
                            }
                        }
                    }

                    let sanitizedDir = self.sanitizeDirectory(directory)
                    let isInstalled = currentSkills.contains(where: {
                        $0.repoOwner == repo.owner && $0.repoName == repo.name && $0.directory == sanitizedDir
                    })

                    return DiscoveredSkill(
                        name: skillName,
                        description: skillDesc,
                        directory: directory,
                        repoOwner: repo.owner,
                        repoName: repo.name,
                        repoBranch: repo.branch,
                        rawUrl: rawUrl,
                        isInstalled: isInstalled
                    )
                }
            }

            var results: [DiscoveredSkill] = []
            for await skill in group {
                if let skill = skill {
                    results.append(skill)
                }
            }
            return results
        }

        print("ClaudeSkillService: Discovered \(repoSkills.count) skills from \(repo.owner)/\(repo.name)")
        return repoSkills
    }

    // MARK: - YAML Frontmatter 解析

    private struct SkillMetadata {
        let name: String?
        let description: String?
    }

    nonisolated private func parseYAMLFrontmatter(_ content: String) -> SkillMetadata? {
        guard content.hasPrefix("---") else { return nil }

        let lines = content.components(separatedBy: "\n")
        var endIdx: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIdx = i
                break
            }
        }
        guard let end = endIdx else { return nil }

        var name: String?
        var description: String?

        for i in 1..<end {
            let line = lines[i]
            if line.hasPrefix("name:") {
                name = line.replacingOccurrences(of: "name:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("description:") {
                description = line.replacingOccurrences(of: "description:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return SkillMetadata(name: name, description: description)
    }

    // MARK: - 安装

    /// 安装 Skill 到指定 app 目标
    func installSkill(_ discovered: DiscoveredSkill, for appTarget: AppTarget = .claude) async throws {
        // 去重检查：如果已安装则跳过
        let sanitizedDir = sanitizeDirectory(discovered.directory)
        if skills.contains(where: {
            $0.repoOwner == discovered.repoOwner &&
            $0.repoName == discovered.repoName &&
            $0.directory == sanitizedDir
        }) {
            return
        }

        guard let url = URL(string: discovered.rawUrl) else { return }

        // 1. 异步下载 SKILL.md
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else { return }

        // 2. 保存到本地主副本
        let localDir = localSkillsDir.appendingPathComponent(sanitizedDir)
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        let skillFile = localDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillFile, atomically: true, encoding: .utf8)

        // 3. symlink 到对应应用的 skills 目录
        let newSkill = ClaudeSkill(
            name: discovered.name,
            skillDescription: discovered.description,
            directory: sanitizedDir,
            repoOwner: discovered.repoOwner,
            repoName: discovered.repoName,
            repoBranch: discovered.repoBranch,
            isEnabled: true,
            apps: [appTarget]
        )

        for app in newSkill.apps {
            let targetBase = app == .claude ? claudeSkillsDir : codexSkillsDir
            try createSkillLink(sanitizedDir, to: targetBase)
        }

        // 4. 记录安装信息
        skills.append(newSkill)
        try persistSkills()
    }

    /// 创建 symlink 或复制到指定目标目录
    private func createSkillLink(_ directory: String, to targetBase: URL) throws {
        let sanitizedDir: String
        if directory.hasPrefix("skills/") {
            sanitizedDir = String(directory.dropFirst("skills/".count))
        } else {
            sanitizedDir = directory
        }

        let targetDir = targetBase.appendingPathComponent(sanitizedDir)
        let sourceDir = localSkillsDir.appendingPathComponent(sanitizedDir)

        // 确保目标目录存在
        try? fileManager.createDirectory(at: targetBase, withIntermediateDirectories: true)

        // 如果已存在，先删除
        if fileManager.fileExists(atPath: targetDir.path) {
            try? fileManager.removeItem(at: targetDir)
        }

        // 尝试 symlink
        do {
            try fileManager.createSymbolicLink(atPath: targetDir.path, withDestinationPath: sourceDir.path)
        } catch {
            // Fallback: 文件复制
            try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let sourceFile = sourceDir.appendingPathComponent("SKILL.md")
            let targetFile = targetDir.appendingPathComponent("SKILL.md")
            try? fileManager.copyItem(at: sourceFile, to: targetFile)
        }
    }

    // MARK: - 卸载

    /// 卸载 Skill
    func uninstallSkill(_ skill: ClaudeSkill) throws {
        // 1. 删除所有同步目录中的链接/副本
        for app in skill.apps {
            let targetBase = app == .claude ? claudeSkillsDir : codexSkillsDir
            let targetDir = targetBase.appendingPathComponent(skill.directory)
            try? fileManager.removeItem(at: targetDir)
        }

        // 2. 删除本地主副本
        let localDir = localSkillsDir.appendingPathComponent(skill.directory)
        try? fileManager.removeItem(at: localDir)

        // 3. 移除记录
        skills.removeAll { $0.id == skill.id }
        try persistSkills()
    }

    // MARK: - 启用/禁用

    /// 切换 Skill 启用状态
    func toggleEnabled(_ skill: ClaudeSkill) throws {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index].isEnabled.toggle()

        if skills[index].isEnabled {
            for app in skill.apps {
                let targetBase = app == .claude ? claudeSkillsDir : codexSkillsDir
                try createSkillLink(skill.directory, to: targetBase)
            }
        } else {
            for app in skill.apps {
                let targetBase = app == .claude ? claudeSkillsDir : codexSkillsDir
                let targetDir = targetBase.appendingPathComponent(skill.directory)
                try? fileManager.removeItem(at: targetDir)
            }
        }

        try persistSkills()
    }

    // MARK: - 扫描与导入

    /// 扫描 ~/.claude/skills/ 中未管理的 Skills
    func scanUnmanagedSkills() -> [UnmanagedSkill] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: claudeSkillsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var unmanaged: [UnmanagedSkill] = []
        for url in contents {
            let dirName = url.lastPathComponent
            // 排除已管理的
            if skills.contains(where: { $0.directory == dirName }) { continue }

            // 检查是否有 SKILL.md
            let skillFile = url.appendingPathComponent("SKILL.md")
            if fileManager.fileExists(atPath: skillFile.path) {
                var name = dirName
                var desc: String? = nil
                if let content = try? String(contentsOf: skillFile, encoding: .utf8),
                   let metadata = parseYAMLFrontmatter(content) {
                    name = metadata.name ?? name
                    desc = metadata.description
                }
                unmanaged.append(UnmanagedSkill(name: name, description: desc, directory: dirName, url: url))
            }
        }
        return unmanaged
    }

    struct UnmanagedSkill: Identifiable {
        let id = UUID()
        let name: String
        let description: String?
        let directory: String
        let url: URL
    }

    /// 导入未管理的 Skill
    func importSkill(_ unmanaged: UnmanagedSkill) throws {
        // 复制到本地主副本
        let localDir = localSkillsDir.appendingPathComponent(unmanaged.directory)
        try? fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        let sourceFile = unmanaged.url.appendingPathComponent("SKILL.md")
        let targetFile = localDir.appendingPathComponent("SKILL.md")
        try? fileManager.copyItem(at: sourceFile, to: targetFile)

        // 记录
        let skill = ClaudeSkill(
            name: unmanaged.name,
            skillDescription: unmanaged.description,
            directory: unmanaged.directory,
            isEnabled: true
        )
        skills.append(skill)
        try? persistSkills()
    }

    /// 扫描 ~/.codex/skills/ 中未管理的 Skills
    func scanUnmanagedCodexSkills() -> [UnmanagedSkill] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: codexSkillsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var unmanaged: [UnmanagedSkill] = []
        for url in contents {
            let dirName = url.lastPathComponent
            if skills.contains(where: { $0.directory == dirName }) { continue }

            let skillFile = url.appendingPathComponent("SKILL.md")
            if fileManager.fileExists(atPath: skillFile.path) {
                var name = dirName
                var desc: String? = nil
                if let content = try? String(contentsOf: skillFile, encoding: .utf8),
                   let metadata = parseYAMLFrontmatter(content) {
                    name = metadata.name ?? name
                    desc = metadata.description
                }
                unmanaged.append(UnmanagedSkill(name: name, description: desc, directory: dirName, url: url))
            }
        }
        return unmanaged
    }

    /// 从 ~/.codex/skills/ 导入 Skill，标记 apps 为 [.codex]
    func importCodexSkill(_ unmanaged: UnmanagedSkill) throws {
        let localDir = localSkillsDir.appendingPathComponent(unmanaged.directory)
        try? fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        let sourceFile = unmanaged.url.appendingPathComponent("SKILL.md")
        let targetFile = localDir.appendingPathComponent("SKILL.md")
        try? fileManager.copyItem(at: sourceFile, to: targetFile)

        let skill = ClaudeSkill(
            name: unmanaged.name,
            skillDescription: unmanaged.description,
            directory: unmanaged.directory,
            isEnabled: true,
            apps: [.codex]
        )
        skills.append(skill)
        try? persistSkills()
    }

    // MARK: - 同步

    /// 同步所有已启用的 Skills 到对应应用目录
    func syncAllEnabled() {
        for skill in skills where skill.isEnabled {
            for app in skill.apps {
                let targetBase = app == .claude ? claudeSkillsDir : codexSkillsDir
                try? createSkillLink(skill.directory, to: targetBase)
            }
        }
    }

    // MARK: - 目录清理

    /// 清理错误的嵌套目录 ~/.claude/skills/skills/
    func cleanupNestedSkillsDir() {
        let nestedDir = claudeSkillsDir.appendingPathComponent("skills")
        if fileManager.fileExists(atPath: nestedDir.path) {
            try? fileManager.removeItem(at: nestedDir)
        }
    }

    /// 去掉开头的 skills/ 前缀
    nonisolated private func sanitizeDirectory(_ directory: String) -> String {
        if directory.hasPrefix("skills/") {
            return String(directory.dropFirst("skills/".count))
        }
        return directory
    }
}
