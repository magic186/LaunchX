import AppKit
import Foundation

/// IDE 最近项目服务
/// 负责从各 IDE 获取最近打开的项目列表
final class IDERecentProjectsService {
    static let shared = IDERecentProjectsService()

    private init() {}

    // 缓存 getFolderOpeners 结果，避免频繁检测 IDE 安装状态
    private var cachedFolderOpeners: [FolderOpenerApp]?
    private var folderOpenersCacheTimestamp: Date = .distantPast
    private let folderOpenersCacheDuration: TimeInterval = 30  // 30 秒缓存

    enum CommandError: Error {
        case invalidUTF8
        case nonZeroExitStatus(Int32)
    }

    // MARK: - Installed IDE Detection

    /// 可用于打开文件夹的应用信息
    struct FolderOpenerApp {
        let name: String
        let path: String
        let icon: NSImage
        let ideType: IDEType?  // nil 表示 Finder 等非 IDE 应用
    }

    /// 获取可用于打开文件夹的应用列表
    /// - Returns: 应用列表，Finder 在最前，然后是已安装的 IDE
    /// - Note: 结果缓存 30 秒，避免频繁检测 IDE 安装状态
    func getAvailableFolderOpeners() -> [FolderOpenerApp] {
        // 使用缓存避免频繁遍历 IDE 类型
        if let cached = cachedFolderOpeners,
            Date().timeIntervalSince(folderOpenersCacheTimestamp) < folderOpenersCacheDuration
        {
            return cached
        }

        let openers = buildFolderOpenersList()
        cachedFolderOpeners = openers
        folderOpenersCacheTimestamp = Date()
        return openers
    }

    /// 清除缓存（在 IDE 安装/卸载后调用）
    func invalidateFolderOpenersCache() {
        cachedFolderOpeners = nil
    }

    /// 实际构建可用打开器列表（不缓存）
    private func buildFolderOpenersList() -> [FolderOpenerApp] {
        var openers: [FolderOpenerApp] = []

        // 1. Finder 始终在第一位
        let finderPath = "/System/Library/CoreServices/Finder.app"
        if FileManager.default.fileExists(atPath: finderPath) {
            let icon = NSWorkspace.shared.icon(forFile: finderPath)
            icon.size = NSSize(width: 32, height: 32)
            openers.append(
                FolderOpenerApp(name: "Finder", path: finderPath, icon: icon, ideType: nil))
        }

        // 2. 检测已安装的 IDE (通过 Bundle ID)
        for ideType in IDEType.allCases {
            for bundleId in ideType.bundleIdentifiers {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
                {
                    let path = appURL.path
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 32, height: 32)
                    let name = FileManager.default.displayName(atPath: path)
                        .replacingOccurrences(of: ".app", with: "")

                    openers.append(
                        FolderOpenerApp(name: name, path: path, icon: icon, ideType: ideType))
                    break  // 每种 IDE 类型只添加一个（如已安装多个版本，取检测到的第一个）
                }
            }
        }

        return openers
    }

    /// 使用指定应用打开文件夹
    /// - Parameters:
    ///   - folderPath: 文件夹路径
    ///   - appPath: 应用路径
    func openFolder(_ folderPath: String, withApp appPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appPath, folderPath]

        do {
            try process.run()
        } catch {
            print("Failed to open folder: \(error)")
        }
    }

    /// 获取指定 IDE 的最近项目
    /// - Parameters:
    ///   - ideType: IDE 类型
    ///   - limit: 最大数量
    /// - Returns: 项目列表
    func getRecentProjects(for ideType: IDEType, limit: Int = 20) -> [IDEProject] {
        switch ideType {
        case .vscode:
            return getVSCodeRecentProjects(limit: limit)
        case .cursor:
            return getCursorRecentProjects(limit: limit)
        case .zed:
            return getZedRecentProjects(limit: limit)
        case .antigravity:
            return getAntigravityRecentProjects(limit: limit)
        default:
            if ideType.isJetBrains {
                return getJetBrainsRecentProjects(for: ideType, limit: limit)
            }
            return []
        }
    }

    /// 使用指定 IDE 打开项目
    /// - Parameters:
    ///   - project: 项目
    ///   - idePath: IDE 应用路径
    func openProject(_ project: IDEProject, withIDEAt idePath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", idePath, project.path]

        do {
            try process.run()
        } catch {
            print("Failed to open project: \(error)")
        }
    }

    // MARK: - VSCode

    private func getVSCodeRecentProjects(limit: Int) -> [IDEProject] {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Code/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        do {
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath, "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';",
                ])
            guard !jsonString.isEmpty else { return [] }

            return parseVSCodeRecentProjects(jsonString, limit: limit)
        } catch {
            print("Failed to query VSCode database: \(error)")
            return []
        }
    }

    private func parseVSCodeRecentProjects(_ jsonString: String, limit: Int) -> [IDEProject] {
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            return []
        }

        var projects: [IDEProject] = []
        var seenPaths = Set<String>()  // 用于去重

        for entry in entries {
            guard projects.count < limit else { break }

            var path: String?

            // 优先获取 folderUri（项目文件夹）
            if let folderUri = entry["folderUri"] as? String {
                path = uriToPath(folderUri)
            }
            // 其次获取 workspace（工作区文件）
            else if let workspace = entry["workspace"] as? String {
                // 工作区文件，取其所在目录
                if let wsPath = uriToPath(workspace) {
                    path = (wsPath as NSString).deletingLastPathComponent
                }
            }

            guard let projectPath = path,
                !seenPaths.contains(projectPath),
                FileManager.default.fileExists(atPath: projectPath)
            else {
                continue
            }

            seenPaths.insert(projectPath)

            let name = (projectPath as NSString).lastPathComponent
            projects.append(
                IDEProject(
                    name: name,
                    path: projectPath,
                    ideType: .vscode
                ))
        }

        return projects
    }

    // MARK: - Cursor

    private func getCursorRecentProjects(limit: Int) -> [IDEProject] {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        do {
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath, "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';",
                ])
            guard !jsonString.isEmpty else { return [] }

            return parseCursorRecentProjects(jsonString, limit: limit)
        } catch {
            print("Failed to query Cursor database: \(error)")
            return []
        }
    }

    private func parseCursorRecentProjects(_ jsonString: String, limit: Int) -> [IDEProject] {
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            return []
        }

        var projects: [IDEProject] = []
        var seenPaths = Set<String>()  // 用于去重

        for entry in entries {
            guard projects.count < limit else { break }

            var path: String?

            // 优先获取 folderUri（项目文件夹）
            if let folderUri = entry["folderUri"] as? String {
                path = uriToPath(folderUri)
            }
            // 其次获取 workspace（工作区文件）
            else if let workspace = entry["workspace"] as? String {
                // 工作区文件，取其所在目录
                if let wsPath = uriToPath(workspace) {
                    path = (wsPath as NSString).deletingLastPathComponent
                }
            }

            guard let projectPath = path,
                !seenPaths.contains(projectPath),
                FileManager.default.fileExists(atPath: projectPath)
            else {
                continue
            }

            seenPaths.insert(projectPath)

            let name = (projectPath as NSString).lastPathComponent
            projects.append(
                IDEProject(
                    name: name,
                    path: projectPath,
                    ideType: .cursor
                ))
        }

        return projects
    }

    // MARK: - Zed

    private func getZedRecentProjects(limit: Int) -> [IDEProject] {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zed/db/0-stable/db.sqlite")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        do {
            let output = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath,
                    "SELECT paths, timestamp FROM workspaces WHERE paths IS NOT NULL AND paths != '' ORDER BY timestamp DESC LIMIT \(limit);",
                ])
            guard !output.isEmpty else { return [] }

            return parseZedRecentProjects(output, limit: limit)
        } catch {
            print("Failed to query Zed database: \(error)")
            return []
        }
    }

    private func parseZedRecentProjects(_ output: String, limit: Int) -> [IDEProject] {
        var projects: [IDEProject] = []
        var seenPaths = Set<String>()  // 用于去重
        let lines = output.components(separatedBy: "\n")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for line in lines {
            guard projects.count < limit, !line.isEmpty else { continue }

            // 格式: path|timestamp
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 1 else { continue }

            let path = parts[0]

            // 去重：跳过已经添加过的路径
            guard !seenPaths.contains(path) else { continue }

            guard FileManager.default.fileExists(atPath: path) else { continue }

            seenPaths.insert(path)

            var lastOpened: Date? = nil
            if parts.count >= 2 {
                lastOpened = dateFormatter.date(from: parts[1])
            }

            let name = (path as NSString).lastPathComponent
            projects.append(
                IDEProject(
                    name: name,
                    path: path,
                    lastOpened: lastOpened,
                    ideType: .zed
                ))
        }

        return projects
    }

    // MARK: - JetBrains

    private func getJetBrainsRecentProjects(for ideType: IDEType, limit: Int) -> [IDEProject] {
        // 查找 JetBrains 配置目录
        let appSupportPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains")
            .path

        guard FileManager.default.fileExists(atPath: appSupportPath) else {
            return []
        }

        // 根据 IDE 类型确定目录前缀
        let dirPrefix: String
        switch ideType {
        case .jetbrainsIntelliJ: dirPrefix = "IntelliJIdea"
        case .jetbrainsPyCharm: dirPrefix = "PyCharm"
        case .jetbrainsWebStorm: dirPrefix = "WebStorm"
        case .jetbrainsGoLand: dirPrefix = "GoLand"
        case .jetbrainsRider: dirPrefix = "Rider"
        case .jetbrainsClion: dirPrefix = "CLion"
        default: return []
        }

        // 查找最新版本的配置目录
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: appSupportPath)
        else {
            return []
        }

        let matchingDirs = contents.filter { $0.hasPrefix(dirPrefix) }.sorted().reversed()

        for dir in matchingDirs {
            let recentProjectsPath = (appSupportPath as NSString)
                .appendingPathComponent(dir)
                .appending("/options/recentProjects.xml")

            if FileManager.default.fileExists(atPath: recentProjectsPath) {
                return parseJetBrainsRecentProjects(
                    at: recentProjectsPath, ideType: ideType, limit: limit)
            }
        }

        return []
    }

    private func parseJetBrainsRecentProjects(at path: String, ideType: IDEType, limit: Int)
        -> [IDEProject]
    {
        guard let data = FileManager.default.contents(atPath: path),
            let xml = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var projects: [IDEProject] = []
        var seenPaths = Set<String>()  // 用于去重

        // 简单的 XML 解析，查找 recentPaths 中的路径
        // JetBrains 使用 $USER_HOME$ 作为 home 目录占位符
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // 匹配 <option name="recentPaths"> 或 <entry key="..."> 中的路径
        let pattern = #"<(?:option value|entry key)="([^"]+)"(?:/)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for match in matches {
            guard projects.count < limit,
                let range = Range(match.range(at: 1), in: xml)
            else {
                continue
            }

            var path = String(xml[range])

            // 替换 $USER_HOME$
            path = path.replacingOccurrences(of: "$USER_HOME$", with: homeDir)

            // 去重：跳过已经添加过的路径
            guard !seenPaths.contains(path) else { continue }

            // 跳过非目录路径
            guard FileManager.default.fileExists(atPath: path) else { continue }

            seenPaths.insert(path)

            let name = (path as NSString).lastPathComponent
            projects.append(
                IDEProject(
                    name: name,
                    path: path,
                    ideType: ideType
                ))
        }

        return projects
    }

    // MARK: - Antigravity

    private func getAntigravityRecentProjects(limit: Int) -> [IDEProject] {
        // Antigravity 使用类似 VSCode 的数据库结构
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        do {
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath, "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';",
                ])
            guard !jsonString.isEmpty else { return [] }

            return parseAntigravityRecentProjects(jsonString, limit: limit)
        } catch {
            print("Failed to query Antigravity database: \(error)")
            return []
        }
    }

    private func parseAntigravityRecentProjects(_ jsonString: String, limit: Int) -> [IDEProject]
    {
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            return []
        }

        var projects: [IDEProject] = []
        var seenPaths = Set<String>()  // 用于去重

        for entry in entries {
            guard projects.count < limit else { break }

            var path: String?

            // 优先获取 folderUri（项目文件夹）
            if let folderUri = entry["folderUri"] as? String {
                path = uriToPath(folderUri)
            }
            // 其次获取 workspace（工作区文件）
            else if let workspace = entry["workspace"] as? String {
                // 工作区文件，取其所在目录
                if let wsPath = uriToPath(workspace) {
                    path = (wsPath as NSString).deletingLastPathComponent
                }
            }

            guard let projectPath = path,
                !seenPaths.contains(projectPath),
                FileManager.default.fileExists(atPath: projectPath)
            else {
                continue
            }

            seenPaths.insert(projectPath)

            let name = (projectPath as NSString).lastPathComponent
            projects.append(
                IDEProject(
                    name: name,
                    path: projectPath,
                    ideType: .antigravity
                ))
        }

        return projects
    }

    // MARK: - Remove Recent Projects

    /// 从最近项目列表中移除指定项目
    /// - Parameters:
    ///   - ideType: IDE类型
    ///   - projectPath: 项目路径
    func removeRecentProject(for ideType: IDEType, projectPath: String) {
        switch ideType {
        case .vscode:
            removeVSCodeRecentProject(projectPath: projectPath)
        case .cursor:
            removeCursorRecentProject(projectPath: projectPath)
        case .zed:
            removeZedRecentProject(projectPath: projectPath)
        case .antigravity:
            removeAntigravityRecentProject(projectPath: projectPath)
        default:
            if ideType.isJetBrains {
                removeJetBrainsRecentProject(for: ideType, projectPath: projectPath)
            }
        }
    }

    /// 从VSCode最近项目列表中移除项目
    private func removeVSCodeRecentProject(projectPath: String) {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Code/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        do {
            // 1. 读取当前数据
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath,
                    "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';"
                ]
            )
            guard !jsonString.isEmpty else { return }

            // 2. 解析JSON并过滤
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var entries = json["entries"] as? [[String: Any]]
            else { return }

            // 3. 过滤掉要移除的项目
            let filteredEntries = entries.filter { entry in
                let path = extractPathFromEntry(entry)
                return path != projectPath
            }

            // 4. 写回数据库
            var modifiedJson: [String: Any] = ["entries": filteredEntries]
            let modifiedData = try JSONSerialization.data(withJSONObject: modifiedJson)
            let modifiedString = String(data: modifiedData, encoding: .utf8) ?? ""

            // 使用UPDATE语句更新
            let escapedValue = modifiedString.replacingOccurrences(of: "'", with: "''")
            let updateSQL = "UPDATE ItemTable SET value = '\(escapedValue)' WHERE key='history.recentlyOpenedPathsList';"

            try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [dbPath, updateSQL]
            )
        } catch {
            print("Failed to remove VSCode recent project: \(error)")
        }
    }

    /// 从Cursor最近项目列表中移除项目
    private func removeCursorRecentProject(projectPath: String) {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        do {
            // 1. 读取当前数据
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath,
                    "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';"
                ]
            )
            guard !jsonString.isEmpty else { return }

            // 2. 解析JSON并过滤
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var entries = json["entries"] as? [[String: Any]]
            else { return }

            // 3. 过滤掉要移除的项目
            let filteredEntries = entries.filter { entry in
                let path = extractPathFromEntry(entry)
                return path != projectPath
            }

            // 4. 写回数据库
            var modifiedJson: [String: Any] = ["entries": filteredEntries]
            let modifiedData = try JSONSerialization.data(withJSONObject: modifiedJson)
            let modifiedString = String(data: modifiedData, encoding: .utf8) ?? ""

            let escapedValue = modifiedString.replacingOccurrences(of: "'", with: "''")
            let updateSQL = "UPDATE ItemTable SET value = '\(escapedValue)' WHERE key='history.recentlyOpenedPathsList';"

            try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [dbPath, updateSQL]
            )
        } catch {
            print("Failed to remove Cursor recent project: \(error)")
        }
    }

    /// 从Zed最近项目列表中移除项目
    private func removeZedRecentProject(projectPath: String) {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zed/db/0-stable/db.sqlite")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        do {
            // Zed使用workspaces表,直接DELETE即可
            let deleteSQL = "DELETE FROM workspaces WHERE paths = '\(projectPath)';"

            try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [dbPath, deleteSQL]
            )
        } catch {
            print("Failed to remove Zed recent project: \(error)")
        }
    }

    /// 从Antigravity最近项目列表中移除项目
    private func removeAntigravityRecentProject(projectPath: String) {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
            )
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        do {
            // 1. 读取当前数据
            let jsonString = try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [
                    dbPath,
                    "SELECT value FROM ItemTable WHERE key='history.recentlyOpenedPathsList';"
                ]
            )
            guard !jsonString.isEmpty else { return }

            // 2. 解析JSON并过滤
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var entries = json["entries"] as? [[String: Any]]
            else { return }

            // 3. 过滤掉要移除的项目
            let filteredEntries = entries.filter { entry in
                let path = extractPathFromEntry(entry)
                return path != projectPath
            }

            // 4. 写回数据库
            var modifiedJson: [String: Any] = ["entries": filteredEntries]
            let modifiedData = try JSONSerialization.data(withJSONObject: modifiedJson)
            let modifiedString = String(data: modifiedData, encoding: .utf8) ?? ""

            let escapedValue = modifiedString.replacingOccurrences(of: "'", with: "''")
            let updateSQL = "UPDATE ItemTable SET value = '\(escapedValue)' WHERE key='history.recentlyOpenedPathsList';"

            try Self.runCommand(
                executablePath: "/usr/bin/sqlite3",
                arguments: [dbPath, updateSQL]
            )
        } catch {
            print("Failed to remove Antigravity recent project: \(error)")
        }
    }

    /// 从JetBrains IDE最近项目列表中移除项目
    private func removeJetBrainsRecentProject(for ideType: IDEType, projectPath: String) {
        // 查找JetBrains配置目录
        let appSupportPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains")
            .path

        guard FileManager.default.fileExists(atPath: appSupportPath) else { return }

        // 根据IDE类型确定目录前缀
        let dirPrefix: String
        switch ideType {
        case .jetbrainsIntelliJ: dirPrefix = "IntelliJIdea"
        case .jetbrainsPyCharm: dirPrefix = "PyCharm"
        case .jetbrainsWebStorm: dirPrefix = "WebStorm"
        case .jetbrainsGoLand: dirPrefix = "GoLand"
        case .jetbrainsRider: dirPrefix = "Rider"
        case .jetbrainsClion: dirPrefix = "CLion"
        default: return
        }

        // 查找最新版本的配置目录
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: appSupportPath)
        else { return }

        let matchingDirs = contents.filter { $0.hasPrefix(dirPrefix) }.sorted().reversed()

        for dir in matchingDirs {
            let recentProjectsPath = (appSupportPath as NSString)
                .appendingPathComponent(dir)
                .appending("/options/recentProjects.xml")

            if FileManager.default.fileExists(atPath: recentProjectsPath) {
                removeProjectFromJetBrainsXML(at: recentProjectsPath, projectPath: projectPath)
                break
            }
        }
    }

    /// 从JetBrains XML文件中移除项目
    private func removeProjectFromJetBrainsXML(at path: String, projectPath: String) {
        guard let data = FileManager.default.contents(atPath: path),
              var xml = String(data: data, encoding: .utf8)
        else { return }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let xmlPath = projectPath.replacingOccurrences(of: homeDir, with: "$USER_HOME$")

        // 简单的XML处理:移除包含该路径的entry或option行
        let lines = xml.components(separatedBy: "\n")
        let filteredLines = lines.filter { line in
            !line.contains(xmlPath)
        }

        let modifiedXML = filteredLines.joined(separator: "\n")

        do {
            try modifiedXML.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to remove JetBrains recent project: \(error)")
        }
    }

    /// 从entry字典中提取路径
    private func extractPathFromEntry(_ entry: [String: Any]) -> String? {
        // 优先获取folderUri(项目文件夹)
        if let folderUri = entry["folderUri"] as? String {
            return uriToPath(folderUri)
        }
        // 其次获取workspace(工作区文件)
        else if let workspace = entry["workspace"] as? String {
            // 工作区文件,取其所在目录
            if let wsPath = uriToPath(workspace) {
                return (wsPath as NSString).deletingLastPathComponent
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// 将 file:// URI 转换为路径
    private func uriToPath(_ uri: String) -> String? {
        guard uri.hasPrefix("file://") else { return nil }

        // 移除 file:// 前缀并解码 URL 编码
        let encoded = String(uri.dropFirst(7))
        return encoded.removingPercentEncoding
    }

    static func runCommand(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // 先持续读取 stdout，避免子进程在管道缓冲区写满后阻塞，导致 waitUntilExit 互锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError.nonZeroExitStatus(process.terminationStatus)
        }

        guard let output = String(data: data, encoding: .utf8) else {
            throw CommandError.invalidUTF8
        }

        return output
    }
}
