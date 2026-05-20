import AppKit
import Foundation

/// 工具配置管理
struct ToolsConfig: Codable {
    /// 工具列表
    var tools: [ToolItem] = []

    // MARK: - 便捷访问

    /// 应用工具
    var appTools: [ToolItem] {
        tools.filter { $0.type == .app }
    }

    /// 网页直达工具
    var webLinkTools: [ToolItem] {
        tools.filter { $0.type == .webLink }
    }

    /// 实用工具
    var utilityTools: [ToolItem] {
        tools.filter { $0.type == .utility }
    }

    /// 系统命令工具
    var systemCommandTools: [ToolItem] {
        tools.filter { $0.type == .systemCommand }
    }

    /// 已启用的工具
    var enabledTools: [ToolItem] {
        tools.filter { $0.isEnabled }
    }

    // MARK: - 持久化

    private static let configKey = "ToolsConfig"
    private static let migrationKey = "ToolsConfigMigrated"
    private static let defaultWebLinksAddedKey = "DefaultWebLinksAdded"
    private static let defaultUtilitiesAddedKey = "DefaultUtilitiesAdded"
    private static let defaultSystemCommandsAddedKey = "DefaultSystemCommandsAdded"
    private static let coreAppsAddedKey = "CoreAppsAdded"
    private static let defaultSettingsPanesAddedKey = "DefaultSettingsPanesAdded"

    /// 从 UserDefaults 加载配置（含自动迁移）
    static func load() -> ToolsConfig {
        // 1. 尝试加载新格式
        if let data = UserDefaults.standard.data(forKey: configKey),
            var config = try? JSONDecoder().decode(ToolsConfig.self, from: data)
        {
            var needsSave = false

            // 检查是否需要添加默认网页直达
            if !UserDefaults.standard.bool(forKey: defaultWebLinksAddedKey) {
                config.addDefaultWebLinksIfNeeded()
                UserDefaults.standard.set(true, forKey: defaultWebLinksAddedKey)
                needsSave = true
            }

            // 检查是否需要添加默认实用工具
            if !UserDefaults.standard.bool(forKey: defaultUtilitiesAddedKey) {
                config.addDefaultUtilitiesIfNeeded()
                UserDefaults.standard.set(true, forKey: defaultUtilitiesAddedKey)
                needsSave = true
            }

            // 检查是否需要添加默认系统命令
            if !UserDefaults.standard.bool(forKey: defaultSystemCommandsAddedKey) {
                config.addDefaultSystemCommandsIfNeeded()
                UserDefaults.standard.set(true, forKey: defaultSystemCommandsAddedKey)
                needsSave = true
            }

            // 检查是否需要添加默认系统设置面板
            if !UserDefaults.standard.bool(forKey: defaultSettingsPanesAddedKey) {
                config.addDefaultSettingsPanesIfNeeded()
                UserDefaults.standard.set(true, forKey: defaultSettingsPanesAddedKey)
                needsSave = true
            }

            // 检查是否需要添加核心应用别名
            if !UserDefaults.standard.bool(forKey: ToolsConfig.coreAppsAddedKey) {
                config.addCoreAppsIfNeeded()
                UserDefaults.standard.set(true, forKey: ToolsConfig.coreAppsAddedKey)
                needsSave = true
            }

            if needsSave {
                config.save()
            }
            return config
        }

        // 2. 尝试迁移旧格式
        if !UserDefaults.standard.bool(forKey: migrationKey),
            let migrated = migrateFromCustomItemsConfig()
        {
            var config = migrated
            // 迁移后也添加默认内容
            config.addDefaultWebLinksIfNeeded()
            config.addDefaultUtilitiesIfNeeded()
            config.addDefaultSystemCommandsIfNeeded()
            config.addDefaultSettingsPanesIfNeeded()
            config.addCoreAppsIfNeeded()
            // 先设置标记，避免循环
            UserDefaults.standard.set(true, forKey: ToolsConfig.migrationKey)
            UserDefaults.standard.set(true, forKey: ToolsConfig.coreAppsAddedKey)
            UserDefaults.standard.set(true, forKey: ToolsConfig.defaultWebLinksAddedKey)
            UserDefaults.standard.set(true, forKey: defaultUtilitiesAddedKey)
            UserDefaults.standard.set(true, forKey: defaultSystemCommandsAddedKey)
            UserDefaults.standard.set(true, forKey: defaultSettingsPanesAddedKey)
            config.save()
            return config
        }

        // 3. 返回带有默认内容的配置
        var config = ToolsConfig()
        config.tools = defaultWebLinks() + defaultUtilities() + defaultSystemCommands() + defaultSettingsPanes()
        config.addCoreAppsIfNeeded()
        // 先设置标记，避免循环
        UserDefaults.standard.set(true, forKey: ToolsConfig.defaultWebLinksAddedKey)
        UserDefaults.standard.set(true, forKey: ToolsConfig.defaultUtilitiesAddedKey)
        UserDefaults.standard.set(true, forKey: ToolsConfig.defaultSystemCommandsAddedKey)
        UserDefaults.standard.set(true, forKey: ToolsConfig.defaultSettingsPanesAddedKey)
        UserDefaults.standard.set(true, forKey: ToolsConfig.coreAppsAddedKey)
        config.save()
        return config
    }

    /// 添加默认网页直达（如果尚未添加）
    private mutating func addDefaultWebLinksIfNeeded() {
        let defaults = ToolsConfig.defaultWebLinks()
        let existingUrls = Set(tools.compactMap { $0.url })

        for webLink in defaults {
            // 只添加 URL 不存在的
            if let url = webLink.url, !existingUrls.contains(url) {
                tools.append(webLink)
            }
        }
    }

    /// 添加默认实用工具（如果尚未添加）
    private mutating func addDefaultUtilitiesIfNeeded() {
        let defaults = ToolsConfig.defaultUtilities()
        let existingIdentifiers = Set(tools.compactMap { $0.extensionIdentifier })

        for utility in defaults {
            // 只添加 identifier 不存在的
            if let identifier = utility.extensionIdentifier,
                !existingIdentifiers.contains(identifier)
            {
                tools.append(utility)
            }
        }
    }

    /// 添加核心应用别名
    private mutating func addCoreAppsIfNeeded() {
        for (path, alias) in SearchConfig.coreApps {
            if FileManager.default.fileExists(atPath: path) {
                // 如果已经存在该路径的工具，则不重复添加，但可以确保别名存在
                if let existingIndex = tools.firstIndex(where: { $0.path == path }) {
                    if tools[existingIndex].alias == nil || tools[existingIndex].alias!.isEmpty {
                        tools[existingIndex].alias = alias
                    }
                } else {
                    var tool = ToolItem.app(path: path, alias: alias)
                    tool.isBuiltIn = true
                    tools.append(tool)
                }
            }
        }
    }

    /// 添加默认系统命令（如果尚未添加）
    private mutating func addDefaultSystemCommandsIfNeeded() {
        let defaults = ToolsConfig.defaultSystemCommands()
        let existingCommands = Set(tools.compactMap { $0.command })

        for systemCommand in defaults {
            // 只添加 command 不存在的
            if let command = systemCommand.command,
                !existingCommands.contains(command)
            {
                tools.append(systemCommand)
            }
        }
    }

    /// 添加默认系统设置面板（如果尚未添加）
    private mutating func addDefaultSettingsPanesIfNeeded() {
        let defaults = ToolsConfig.defaultSettingsPanes()
        let existingCommands = Set(tools.compactMap { $0.command })

        for pane in defaults {
            if let command = pane.command, !existingCommands.contains(command) {
                tools.append(pane)
            }
        }
    }

    /// 默认实用工具列表
    private static func defaultUtilities() -> [ToolItem] {
        return [
            ToolItem.utility(
                name: "退出应用与进程",
                identifier: "kill",
                alias: "kill",
                iconData: loadIconData(named: "Utility_kill")
            ),
            ToolItem.utility(
                name: "IP 查询",
                identifier: "ip",
                alias: "ip",
                iconData: loadIconData(named: "Utility_ip")
            ),
            ToolItem.utility(
                name: "UUID 生成器",
                identifier: "uuid",
                alias: "uuid",
                iconData: loadIconData(named: "Utility_uuid")
            ),
            ToolItem.utility(
                name: "URL 编码 & 解码",
                identifier: "url",
                alias: "url",
                iconData: loadIconData(named: "Utility_url")
            ),
            ToolItem.utility(
                name: "Base64 编码 & 解码",
                identifier: "base64",
                alias: "b64",
                iconData: loadIconData(named: "Utility_base64")
            ),
        ]
    }

    /// 默认系统命令列表
    private static func defaultSystemCommands() -> [ToolItem] {
        return [
            ToolItem.systemCommand(
                name: "自动隐藏程序坞",
                command: "toggle_dock_autohide",
                alias: "dock"
            ),
            ToolItem.systemCommand(
                name: "自动隐藏菜单栏",
                command: "toggle_menubar_autohide",
                alias: "menubar"
            ),
            ToolItem.systemCommand(
                name: "切换隐藏文件显示",
                command: "toggle_hidden_files",
                alias: "hidden"
            ),
            ToolItem.systemCommand(
                name: "切换深色模式",
                command: "toggle_dark_mode",
                alias: "dark"
            ),
            ToolItem.systemCommand(
                name: "切换夜览",
                command: "toggle_night_shift",
                alias: "night"
            ),
            ToolItem.systemCommand(
                name: "推出所有磁盘",
                command: "eject_all_disks",
                alias: "eject"
            ),
            ToolItem.systemCommand(
                name: "清空废纸篓",
                command: "empty_trash",
                alias: "trash"
            ),
            ToolItem.systemCommand(
                name: "锁屏",
                command: "lock_screen",
                alias: "lock"
            ),
            ToolItem.systemCommand(
                name: "关机",
                command: "shutdown",
                alias: "shut"
            ),
            ToolItem.systemCommand(
                name: "重启电脑",
                command: "restart",
                alias: "restart"
            ),
        ]
    }

    /// 默认系统设置面板列表
    private static func defaultSettingsPanes() -> [ToolItem] {
        return [
            ToolItem.systemCommand(name: "系统设置 - 通用", command: "settings_general", alias: "general"),
            ToolItem.systemCommand(name: "系统设置 - 外观", command: "settings_appearance", alias: "appearance"),
            ToolItem.systemCommand(name: "系统设置 - 辅助功能", command: "settings_accessibility", alias: "accessibility"),
            ToolItem.systemCommand(name: "系统设置 - 控制中心", command: "settings_control_center"),
            ToolItem.systemCommand(name: "系统设置 - 桌面与程序坞", command: "settings_desktop"),
            ToolItem.systemCommand(name: "系统设置 - 显示器", command: "settings_displays", alias: "display"),
            ToolItem.systemCommand(name: "系统设置 - 墙纸", command: "settings_wallpaper", alias: "wallpaper"),
            ToolItem.systemCommand(name: "系统设置 - 声音", command: "settings_sound", alias: "sound"),
            ToolItem.systemCommand(name: "系统设置 - 网络", command: "settings_network", alias: "network"),
            ToolItem.systemCommand(name: "系统设置 - Wi-Fi", command: "settings_wifi", alias: "wifi"),
            ToolItem.systemCommand(name: "系统设置 - 蓝牙", command: "settings_bluetooth", alias: "bluetooth"),
            ToolItem.systemCommand(name: "系统设置 - 电池", command: "settings_battery", alias: "battery"),
            ToolItem.systemCommand(name: "系统设置 - 通知", command: "settings_notifications", alias: "notification"),
            ToolItem.systemCommand(name: "系统设置 - 键盘", command: "settings_keyboard"),
            ToolItem.systemCommand(name: "系统设置 - 触控板", command: "settings_trackpad", alias: "trackpad"),
            ToolItem.systemCommand(name: "系统设置 - 鼠标", command: "settings_mouse", alias: "mouse"),
            ToolItem.systemCommand(name: "系统设置 - 打印机与扫描仪", command: "settings_printers", alias: "printer"),
            ToolItem.systemCommand(name: "系统设置 - 隐私与安全性", command: "settings_privacy", alias: "privacy"),
            ToolItem.systemCommand(name: "系统设置 - 聚焦", command: "settings_spotlight", alias: "spotlight"),
            ToolItem.systemCommand(name: "系统设置 - Apple ID", command: "settings_appleid", alias: "appleid"),
            ToolItem.systemCommand(name: "系统设置 - 用户与群组", command: "settings_users", alias: "users"),
            ToolItem.systemCommand(name: "系统设置 - 密码", command: "settings_passwords", alias: "passwords"),
            ToolItem.systemCommand(name: "系统设置 - 互联网账户", command: "settings_internet_accounts"),
            ToolItem.systemCommand(name: "系统设置 - 游戏中心", command: "settings_game_center"),
            ToolItem.systemCommand(name: "系统设置 - 软件更新", command: "settings_software_update", alias: "update"),
            ToolItem.systemCommand(name: "系统设置 - 日期与时间", command: "settings_date_time"),
            ToolItem.systemCommand(name: "系统设置 - 语言与地区", command: "settings_language", alias: "language"),
            ToolItem.systemCommand(name: "系统设置 - 共享", command: "settings_sharing", alias: "sharing"),
            ToolItem.systemCommand(name: "系统设置 - 时间机器", command: "settings_time_machine", alias: "timemachine"),
            ToolItem.systemCommand(name: "系统设置 - 启动磁盘", command: "settings_startup_disk"),
            ToolItem.systemCommand(name: "系统设置 - 锁定屏幕", command: "settings_lock_screen"),
            ToolItem.systemCommand(name: "系统设置 - 专注模式", command: "settings_focus", alias: "focus"),
            ToolItem.systemCommand(name: "系统设置 - 屏幕使用时间", command: "settings_screen_time", alias: "screentime"),
            ToolItem.systemCommand(name: "系统设置 - 储存空间", command: "settings_storage", alias: "storage"),
        ]
    }

    /// 从 Asset Catalog 加载图标数据
    private static func loadIconData(named name: String) -> Data? {
        guard let image = NSImage(named: name) else { return nil }
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return pngData
    }

    /// 默认网页直达列表
    private static func defaultWebLinks() -> [ToolItem] {
        return [
            ToolItem.webLink(
                name: "Google",
                url: "https://www.google.com/search?q={query}",
                alias: "go",
                iconData: loadIconData(named: "WebLink_google"),
                showInSearchPanel: true
            ),
            ToolItem.webLink(
                name: "GitHub",
                url: "https://www.github.com/search?q={query}",
                alias: "gh",
                iconData: loadIconData(named: "WebLink_github"),
                showInSearchPanel: true
            ),
            ToolItem.webLink(
                name: "DeepSeek",
                url: "https://chat.deepseek.com/",
                alias: "deep",
                iconData: loadIconData(named: "WebLink_deepseek"),
                showInSearchPanel: false
            ),
            ToolItem.webLink(
                name: "哔哩哔哩",
                url: "https://search.bilibili.com/all?keyword={query}",
                alias: "bl",
                iconData: loadIconData(named: "WebLink_bilibili"),
                showInSearchPanel: true
            ),
            ToolItem.webLink(
                name: "YouTube",
                url: "https://www.youtube.com/results?search_query={query}",
                alias: "yt",
                iconData: loadIconData(named: "WebLink_youtube"),
                showInSearchPanel: true
            ),
            ToolItem.webLink(
                name: "Twitter",
                url: "https://twitter.com/search?q={query}",
                alias: "tt",
                iconData: loadIconData(named: "WebLink_twitter"),
                showInSearchPanel: false
            ),
            ToolItem.webLink(
                name: "微博",
                url: "https://s.weibo.com/weibo/{query}",
                alias: "wb",
                iconData: loadIconData(named: "WebLink_weibo"),
                showInSearchPanel: false
            ),
            ToolItem.webLink(
                name: "V2EX",
                url: "https://www.v2ex.com/?q={query}",
                alias: "v2",
                iconData: loadIconData(named: "WebLink_v2ex"),
                showInSearchPanel: false
            ),
            ToolItem.webLink(
                name: "天眼查",
                url: "https://www.tianyancha.com/search?key={query}",
                alias: "tyc",
                iconData: loadIconData(named: "WebLink_tianyancha"),
                showInSearchPanel: false
            ),
        ]
    }

    /// 保存配置到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ToolsConfig.configKey)
            // 发送配置变化通知
            NotificationCenter.default.post(name: .toolsConfigDidChange, object: nil)
            // 过渡期：同时发送旧通知以保持兼容
            NotificationCenter.default.post(name: .customItemsConfigDidChange, object: nil)
        }
    }

    /// 重置配置
    static func reset() {
        UserDefaults.standard.removeObject(forKey: configKey)
        UserDefaults.standard.removeObject(forKey: migrationKey)
        NotificationCenter.default.post(name: .toolsConfigDidChange, object: nil)
    }

    // MARK: - 迁移逻辑

    /// 从 CustomItemsConfig 迁移
    private static func migrateFromCustomItemsConfig() -> ToolsConfig? {
        let oldConfig = CustomItemsConfig.load()
        guard !oldConfig.customItems.isEmpty else { return nil }

        var newConfig = ToolsConfig()
        for item in oldConfig.customItems {
            newConfig.tools.append(ToolItem.fromCustomItem(item))
        }
        return newConfig
    }

    // MARK: - 别名映射

    /// 获取别名映射表（alias -> path/url）
    /// 用于 MemoryIndex 的别名搜索
    func aliasMap() -> [String: String] {
        var map: [String: String] = [:]
        for tool in enabledTools {
            guard let alias = tool.alias, !alias.isEmpty else { continue }

            switch tool.type {
            case .app:
                if let path = tool.path {
                    map[alias.lowercased()] = path
                }
            case .webLink:
                if let url = tool.url {
                    map[alias.lowercased()] = url
                }
            case .utility:
                if let identifier = tool.extensionIdentifier {
                    map[alias.lowercased()] = identifier
                }
            case .systemCommand:
                if let command = tool.command {
                    map[alias.lowercased()] = command
                }
            }
        }
        return map
    }

    // MARK: - 快捷键管理

    /// 获取所有已配置的快捷键
    /// - Returns: 元组数组 (快捷键配置, 工具ID, 是否为进入扩展快捷键)
    func allHotKeys() -> [(config: HotKeyConfig, toolId: UUID, isExtension: Bool)] {
        var hotKeys: [(HotKeyConfig, UUID, Bool)] = []
        for tool in enabledTools {
            if let hotKey = tool.hotKey {
                hotKeys.append((hotKey, tool.id, false))
            }
            if tool.isIDE, let extKey = tool.extensionHotKey {
                hotKeys.append((extKey, tool.id, true))
            }
        }
        return hotKeys
    }

    /// 检查快捷键是否已被使用
    /// - Parameters:
    ///   - keyCode: 按键代码
    ///   - modifiers: 修饰键
    ///   - excludingToolId: 排除的工具 ID（用于编辑时排除自身）
    ///   - excludingIsExtension: 排除的快捷键类型
    /// - Returns: 冲突的工具名称，nil 表示无冲突
    func checkHotKeyConflict(
        keyCode: UInt32,
        modifiers: UInt32,
        excludingToolId: UUID? = nil,
        excludingIsExtension: Bool? = nil
    ) -> String? {
        for tool in tools {
            // 检查主快捷键
            if let hotKey = tool.hotKey,
                hotKey.keyCode == keyCode && hotKey.modifiers == modifiers
            {
                // 如果是同一工具的同类型快捷键，跳过
                if let excludeId = excludingToolId,
                    let excludeIsExt = excludingIsExtension,
                    tool.id == excludeId && !excludeIsExt
                {
                    continue
                }
                return "\(tool.name) (打开)"
            }

            // 检查扩展快捷键
            if let extKey = tool.extensionHotKey,
                extKey.keyCode == keyCode && extKey.modifiers == modifiers
            {
                // 如果是同一工具的同类型快捷键，跳过
                if let excludeId = excludingToolId,
                    let excludeIsExt = excludingIsExtension,
                    tool.id == excludeId && excludeIsExt
                {
                    continue
                }
                return "\(tool.name) (进入扩展)"
            }
        }
        return nil
    }

    // MARK: - 查找方法

    /// 根据 ID 查找工具
    func tool(byId id: UUID) -> ToolItem? {
        tools.first { $0.id == id }
    }

    /// 根据路径查找工具（仅 App 类型）
    func tool(byPath path: String) -> ToolItem? {
        tools.first { $0.type == .app && $0.path == path }
    }

    /// 根据 URL 查找工具（仅 WebLink 类型）
    func tool(byURL url: String) -> ToolItem? {
        tools.first { $0.type == .webLink && $0.url == url }
    }

    /// 根据别名查找工具
    func tool(byAlias alias: String) -> ToolItem? {
        let lowercased = alias.lowercased()
        return tools.first { $0.alias?.lowercased() == lowercased }
    }

    // MARK: - 增删改

    /// 添加工具
    mutating func addTool(_ tool: ToolItem) {
        // 检查是否已存在相同的工具
        switch tool.type {
        case .app:
            guard !tools.contains(where: { $0.type == .app && $0.path == tool.path }) else {
                return
            }
        case .webLink:
            guard !tools.contains(where: { $0.type == .webLink && $0.url == tool.url }) else {
                return
            }
        case .utility:
            guard
                !tools.contains(where: {
                    $0.type == .utility && $0.extensionIdentifier == tool.extensionIdentifier
                })
            else { return }
        case .systemCommand:
            guard
                !tools.contains(where: { $0.type == .systemCommand && $0.command == tool.command })
            else { return }
        }
        tools.append(tool)
    }

    /// 更新工具
    mutating func updateTool(_ tool: ToolItem) {
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[index] = tool
        }
    }

    /// 删除工具
    mutating func removeTool(byId id: UUID) {
        tools.removeAll { $0.id == id }
    }

    /// 删除多个工具
    mutating func removeTools(at offsets: IndexSet) {
        let indicesToRemove = offsets.sorted(by: >)
        for index in indicesToRemove {
            tools.remove(at: index)
        }
    }

    /// 切换工具启用状态
    mutating func toggleEnabled(toolId: UUID) {
        if let index = tools.firstIndex(where: { $0.id == toolId }) {
            tools[index].isEnabled.toggle()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 工具配置变化通知
    static let toolsConfigDidChange = Notification.Name("toolsConfigDidChange")
}
