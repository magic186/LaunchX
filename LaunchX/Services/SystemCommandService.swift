import AppKit
import Foundation

/// 系统命令服务
/// 负责执行各种系统命令（切换设置、系统操作等）
class SystemCommandService {
    static let shared = SystemCommandService()

    private init() {}

    // MARK: - 命令标识符

    enum Identifier: String, CaseIterable {
        case toggleDockAutohide = "toggle_dock_autohide"
        case toggleMenubarAutohide = "toggle_menubar_autohide"
        case toggleHiddenFiles = "toggle_hidden_files"
        case toggleDarkMode = "toggle_dark_mode"
        case toggleNightShift = "toggle_night_shift"
        case ejectAllDisks = "eject_all_disks"
        case emptyTrash = "empty_trash"
        case lockScreen = "lock_screen"
        case shutdown = "shutdown"
        case restart = "restart"

        // 系统设置面板
        case settingsGeneral = "settings_general"
        case settingsAppearance = "settings_appearance"
        case settingsAccessibility = "settings_accessibility"
        case settingsControlCenter = "settings_control_center"
        case settingsDesktop = "settings_desktop"
        case settingsDisplays = "settings_displays"
        case settingsWallpaper = "settings_wallpaper"
        case settingsSound = "settings_sound"
        case settingsNetwork = "settings_network"
        case settingsWiFi = "settings_wifi"
        case settingsBluetooth = "settings_bluetooth"
        case settingsBattery = "settings_battery"
        case settingsNotifications = "settings_notifications"
        case settingsKeyboard = "settings_keyboard"
        case settingsTrackpad = "settings_trackpad"
        case settingsMouse = "settings_mouse"
        case settingsPrintersAndScanners = "settings_printers"
        case settingsPrivacySecurity = "settings_privacy"
        case settingsSpotlight = "settings_spotlight"
        case settingsAppleID = "settings_appleid"
        case settingsUsersAndGroups = "settings_users"
        case settingsPasswords = "settings_passwords"
        case settingsInternetAccounts = "settings_internet_accounts"
        case settingsGameCenter = "settings_game_center"
        case settingsSoftwareUpdate = "settings_software_update"
        case settingsDateAndTime = "settings_date_time"
        case settingsLanguageAndRegion = "settings_language"
        case settingsShareAndAirdrop = "settings_sharing"
        case settingsTimeMachine = "settings_time_machine"
        case settingsStartupDisk = "settings_startup_disk"
        case settingsLockScreen = "settings_lock_screen"
        case settingsFocus = "settings_focus"
        case settingsScreenTime = "settings_screen_time"
        case settingsStorage = "settings_storage"

        /// 基础名称（静态）
        var baseName: String {
            switch self {
            case .toggleDockAutohide: return "自动隐藏程序坞"
            case .toggleMenubarAutohide: return "自动隐藏菜单栏"
            case .toggleHiddenFiles: return "切换隐藏文件显示"
            case .toggleDarkMode: return "切换深色模式"
            case .toggleNightShift: return "切换夜览"
            case .ejectAllDisks: return "推出所有磁盘"
            case .emptyTrash: return "清空废纸篓"
            case .lockScreen: return "锁屏"
            case .shutdown: return "关机"
            case .restart: return "重启电脑"
            case .settingsGeneral: return "系统设置 - 通用"
            case .settingsAppearance: return "系统设置 - 外观"
            case .settingsAccessibility: return "系统设置 - 辅助功能"
            case .settingsControlCenter: return "系统设置 - 控制中心"
            case .settingsDesktop: return "系统设置 - 桌面与程序坞"
            case .settingsDisplays: return "系统设置 - 显示器"
            case .settingsWallpaper: return "系统设置 - 墙纸"
            case .settingsSound: return "系统设置 - 声音"
            case .settingsNetwork: return "系统设置 - 网络"
            case .settingsWiFi: return "系统设置 - Wi-Fi"
            case .settingsBluetooth: return "系统设置 - 蓝牙"
            case .settingsBattery: return "系统设置 - 电池"
            case .settingsNotifications: return "系统设置 - 通知"
            case .settingsKeyboard: return "系统设置 - 键盘"
            case .settingsTrackpad: return "系统设置 - 触控板"
            case .settingsMouse: return "系统设置 - 鼠标"
            case .settingsPrintersAndScanners: return "系统设置 - 打印机与扫描仪"
            case .settingsPrivacySecurity: return "系统设置 - 隐私与安全性"
            case .settingsSpotlight: return "系统设置 - 聚焦"
            case .settingsAppleID: return "系统设置 - Apple ID"
            case .settingsUsersAndGroups: return "系统设置 - 用户与群组"
            case .settingsPasswords: return "系统设置 - 密码"
            case .settingsInternetAccounts: return "系统设置 - 互联网账户"
            case .settingsGameCenter: return "系统设置 - 游戏中心"
            case .settingsSoftwareUpdate: return "系统设置 - 软件更新"
            case .settingsDateAndTime: return "系统设置 - 日期与时间"
            case .settingsLanguageAndRegion: return "系统设置 - 语言与地区"
            case .settingsShareAndAirdrop: return "系统设置 - 通用 - 共享"
            case .settingsTimeMachine: return "系统设置 - 通用 - 时间机器"
            case .settingsStartupDisk: return "系统设置 - 通用 - 启动磁盘"
            case .settingsLockScreen: return "系统设置 - 锁定屏幕"
            case .settingsFocus: return "系统设置 - 专注模式"
            case .settingsScreenTime: return "系统设置 - 屏幕使用时间"
            case .settingsStorage: return "系统设置 - 通用 - 储存空间"
            }
        }

        /// 命令描述（用于确认弹窗）
        var description: String {
            switch self {
            case .toggleDockAutohide: return "切换程序坞的自动隐藏设置"
            case .toggleMenubarAutohide: return "切换菜单栏的自动隐藏设置"
            case .toggleHiddenFiles: return "切换 Finder 中隐藏文件的显示状态"
            case .toggleDarkMode: return "切换系统深色/浅色外观"
            case .toggleNightShift: return "切换夜览（护眼模式）"
            case .ejectAllDisks: return "安全推出所有外部磁盘"
            case .emptyTrash: return "永久删除废纸篓中的所有文件"
            case .lockScreen: return "锁定屏幕"
            case .shutdown: return "关闭电脑"
            case .restart: return "重新启动电脑"
            default: return "打开\(baseName)"
            }
        }

        /// 是否需要二次确认
        var requiresDoubleConfirmation: Bool {
            switch self {
            case .ejectAllDisks, .emptyTrash, .shutdown, .restart:
                return true
            default:
                return false
            }
        }

        /// 是否为系统设置面板
        var isSettingsPane: Bool {
            rawValue.hasPrefix("settings_")
        }

        /// 系统设置面板 URL
        var settingsURL: URL? {
            guard isSettingsPane else { return nil }
            let urlString: String
            switch self {
            case .settingsGeneral: urlString = "x-apple.systempreferences:com.apple.General-Settings.extension"
            case .settingsAppearance: urlString = "x-apple.systempreferences:com.apple.Appearance-Settings.extension"
            case .settingsAccessibility: urlString = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
            case .settingsControlCenter: urlString = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
            case .settingsDesktop: urlString = "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
            case .settingsDisplays: urlString = "x-apple.systempreferences:com.apple.Displays-Settings.extension"
            case .settingsWallpaper: urlString = "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
            case .settingsSound: urlString = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
            case .settingsNetwork: urlString = "x-apple.systempreferences:com.apple.Network-Settings.extension"
            case .settingsWiFi: urlString = "x-apple.systempreferences:com.apple.Wi-Fi-Settings.extension"
            case .settingsBluetooth: urlString = "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension"
            case .settingsBattery: urlString = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
            case .settingsNotifications: urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            case .settingsKeyboard: urlString = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
            case .settingsTrackpad: urlString = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
            case .settingsMouse: urlString = "x-apple.systempreferences:com.apple.Mouse-Settings.extension"
            case .settingsPrintersAndScanners: urlString = "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension"
            case .settingsPrivacySecurity: urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
            case .settingsSpotlight: urlString = "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"
            case .settingsAppleID: urlString = "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
            case .settingsUsersAndGroups: urlString = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
            case .settingsPasswords: urlString = "x-apple.systempreferences:com.apple.Passwords-Settings.extension"
            case .settingsInternetAccounts: urlString = "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
            case .settingsGameCenter: urlString = "x-apple.systempreferences:com.apple.Game-Center-Settings.extension"
            case .settingsSoftwareUpdate: urlString = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
            case .settingsDateAndTime: urlString = "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"
            case .settingsLanguageAndRegion: urlString = "x-apple.systempreferences:com.apple.Localization-Settings.extension"
            case .settingsShareAndAirdrop: urlString = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
            case .settingsTimeMachine: urlString = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
            case .settingsStartupDisk: urlString = "x-apple.systempreferences:com.apple.Startup-Disk-Settings.extension"
            case .settingsLockScreen: urlString = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
            case .settingsFocus: urlString = "x-apple.systempreferences:com.apple.Focus-Settings.extension"
            case .settingsScreenTime: urlString = "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"
            case .settingsStorage: urlString = "x-apple.systempreferences:com.apple.settings.Storage"
            default: return nil
            }
            return URL(string: urlString)
        }

        /// SF Symbol 图标名称
        var iconName: String {
            switch self {
            case .toggleDockAutohide: return "dock.rectangle"
            case .toggleMenubarAutohide: return "menubar.rectangle"
            case .toggleHiddenFiles: return "eye.slash"
            case .toggleDarkMode: return "moon.fill"
            case .toggleNightShift: return "sun.max.fill"
            case .ejectAllDisks: return "eject.fill"
            case .emptyTrash: return "trash.fill"
            case .lockScreen: return "lock.fill"
            case .shutdown: return "power"
            case .restart: return "arrow.clockwise"
            case .settingsGeneral: return "gear"
            case .settingsAppearance: return "paintbrush"
            case .settingsAccessibility: return "accessibility"
            case .settingsControlCenter: return "switch.2"
            case .settingsDesktop: return "menubar.dock.rectangle"
            case .settingsDisplays: return "display"
            case .settingsWallpaper: return "photo"
            case .settingsSound: return "speaker.wave.3.fill"
            case .settingsNetwork: return "network"
            case .settingsWiFi: return "wifi"
            case .settingsBluetooth: return "bluetooth"
            case .settingsBattery: return "battery.100percent"
            case .settingsNotifications: return "bell.badge.fill"
            case .settingsKeyboard: return "keyboard"
            case .settingsTrackpad: return "hand.point.up.braille"
            case .settingsMouse: return "computermouse"
            case .settingsPrintersAndScanners: return "printer"
            case .settingsPrivacySecurity: return "hand.raised.fill"
            case .settingsSpotlight: return "magnifyingglass"
            case .settingsAppleID: return "person.crop.circle"
            case .settingsUsersAndGroups: return "person.2"
            case .settingsPasswords: return "key.fill"
            case .settingsInternetAccounts: return "at"
            case .settingsGameCenter: return "gamecontroller"
            case .settingsSoftwareUpdate: return "arrow.triangle.2.circlepath"
            case .settingsDateAndTime: return "clock"
            case .settingsLanguageAndRegion: return "globe"
            case .settingsShareAndAirdrop: return "shareplay"
            case .settingsTimeMachine: return "clock.arrow.circlepath"
            case .settingsStartupDisk: return "internaldrive"
            case .settingsLockScreen: return "lock.display"
            case .settingsFocus: return "moon.circle"
            case .settingsScreenTime: return "hourglass"
            case .settingsStorage: return "externaldrive"
            }
        }
    }

    // MARK: - 动态名称

    /// 获取命令的动态显示名称
    func getDynamicName(for identifier: String) -> String {
        guard let id = Identifier(rawValue: identifier) else {
            return identifier
        }
        return id.baseName
    }

    // MARK: - 状态查询

    /// 检查 Dock 自动隐藏是否启用
    func isDockAutoHideEnabled() -> Bool {
        return readDefaultsBool(domain: "com.apple.dock", key: "autohide")
    }

    /// 检查菜单栏自动隐藏是否启用
    func isMenuBarAutoHideEnabled() -> Bool {
        // 优先检查新版 macOS 的设置键
        let newKey = readDefaultsString(
            domain: "com.apple.dock", key: "autohide-menubar-in-fullscreen")
        if newKey != nil {
            return readDefaultsBool(domain: "com.apple.dock", key: "autohide-menubar-in-fullscreen")
        }
        // 回退到旧版设置键
        return readDefaultsBool(domain: "NSGlobalDomain", key: "_HIHideMenuBar")
    }

    /// 检查隐藏文件是否显示
    func isHiddenFilesVisible() -> Bool {
        return readDefaultsBool(domain: "com.apple.finder", key: "AppleShowAllFiles")
    }

    /// 检查深色模式是否启用
    func isDarkModeEnabled() -> Bool {
        let result = readDefaultsString(domain: "-g", key: "AppleInterfaceStyle")
        return result?.lowercased() == "dark"
    }

    // MARK: - 命令执行

    /// 执行系统命令
    /// - Parameters:
    ///   - identifier: 命令标识符
    ///   - completion: 完成回调，参数为是否执行成功
    func execute(identifier: String, completion: @escaping (Bool) -> Void) {
        guard let id = Identifier(rawValue: identifier) else {
            print("[SystemCommandService] Unknown identifier: \(identifier)")
            completion(false)
            return
        }

        // 系统设置面板直接打开 URL
        if id.isSettingsPane {
            if let url = id.settingsURL {
                NSWorkspace.shared.open(url)
                completion(true)
            } else {
                completion(false)
            }
            return
        }

        // 检查是否需要二次确认
        if id.requiresDoubleConfirmation {
            showDoubleConfirmation(for: id) { confirmed in
                if confirmed {
                    self.performCommand(id, completion: completion)
                } else {
                    completion(false)
                }
            }
        } else {
            performCommand(id, completion: completion)
        }
    }

    /// 执行具体命令
    private func performCommand(_ id: Identifier, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success: Bool

            switch id {
            case .toggleDockAutohide:
                success = self.toggleDockAutohide()
            case .toggleMenubarAutohide:
                success = self.toggleMenuBarAutohide()
            case .toggleHiddenFiles:
                success = self.toggleHiddenFiles()
            case .toggleDarkMode:
                success = self.toggleDarkMode()
            case .toggleNightShift:
                success = self.toggleNightShift()
            case .ejectAllDisks:
                success = self.ejectAllDisks()
            case .emptyTrash:
                success = self.emptyTrash()
            case .lockScreen:
                success = self.lockScreen()
            case .shutdown:
                success = self.shutdown()
            case .restart:
                success = self.restart()
            default:
                success = false
            }

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    // MARK: - 具体命令实现

    /// 切换 Dock 自动隐藏
    private func toggleDockAutohide() -> Bool {
        // 使用 AppleScript 切换 Dock 自动隐藏，避免 killall Dock 导致的屏幕闪烁
        let script = """
            tell application "System Events"
                tell dock preferences
                    set autohide to not autohide
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// 切换菜单栏自动隐藏
    private func toggleMenuBarAutohide() -> Bool {
        // 使用 AppleScript 通过 System Events 切换菜单栏自动隐藏
        let script = """
            tell application "System Events"
                tell dock preferences
                    set autohide menu bar to not autohide menu bar
                end tell
            end tell
            """
        return runAppleScript(script)
    }

    /// 切换隐藏文件显示
    private func toggleHiddenFiles() -> Bool {
        let currentValue = isHiddenFilesVisible()
        let newValue = !currentValue

        let success = writeDefaultsBool(
            domain: "com.apple.finder", key: "AppleShowAllFiles", value: newValue)
        if success {
            // 重启 Finder 使设置生效
            runShellCommand("/usr/bin/killall", arguments: ["Finder"])
        }
        return success
    }

    /// 切换深色模式
    private func toggleDarkMode() -> Bool {
        let script =
            "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        return runAppleScript(script)
    }

    /// 切换夜览
    private func toggleNightShift() -> Bool {
        // 使用 AppleScript 调用 CoreBrightness 私有框架切换夜览
        let script = """
            use framework "CoreBrightness"

            set client to current application's CBBlueLightClient's alloc()'s init()
            set {theResult, theProps} to client's getBlueLightStatus:(reference)

            set isEnabled to item 2 of theProps

            if isEnabled then
                client's setEnabled:false
            else
                client's setEnabled:true
            end if
            """
        return runAppleScript(script)
    }

    /// 推出所有磁盘
    private func ejectAllDisks() -> Bool {
        let script = """
            tell application "Finder"
                eject (every disk whose ejectable is true)
            end tell
            """
        return runAppleScript(script)
    }

    /// 清空废纸篓
    private func emptyTrash() -> Bool {
        let script = """
            tell application "Finder"
                empty the trash
            end tell
            """
        return runAppleScript(script)
    }

    /// 锁屏
    private func lockScreen() -> Bool {
        // 使用 pmset 命令锁屏（更可靠的方式）
        let script = """
            tell application "System Events" to keystroke "q" using {control down, command down}
            """
        return runAppleScript(script)
    }

    /// 关机
    private func shutdown() -> Bool {
        let script = """
            tell application "System Events"
                shut down
            end tell
            """
        return runAppleScript(script)
    }

    /// 重启
    private func restart() -> Bool {
        let script = """
            tell application "System Events"
                restart
            end tell
            """
        return runAppleScript(script)
    }

    // MARK: - 确认弹窗

    /// 显示确认弹窗
    private func showDoubleConfirmation(for id: Identifier, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "确认\(id.baseName)？"
            alert.informativeText = id.description
            alert.alertStyle = .warning

            // 设置图标
            if let icon = NSImage(systemSymbolName: id.iconName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
                alert.icon = icon.withSymbolConfiguration(config)
            }

            alert.addButton(withTitle: "确认")
            alert.addButton(withTitle: "取消")

            // 激活应用以确保弹窗获得焦点并支持回车确认
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }

    // MARK: - 辅助方法

    /// 读取 defaults 布尔值
    private func readDefaultsBool(domain: String, key: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", domain, key]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output =
                String(data: data, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""

            // defaults 返回 "1" 或 "true" 表示 true
            return output == "1" || output.lowercased() == "true"
        } catch {
            print("[SystemCommandService] Failed to read defaults: \(error)")
            return false
        }
    }

    /// 读取 defaults 字符串值
    private func readDefaultsString(domain: String, key: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", domain, key]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
        } catch {
            print("[SystemCommandService] Failed to read defaults: \(error)")
            return nil
        }
    }

    /// 写入 defaults 布尔值
    private func writeDefaultsBool(domain: String, key: String, value: Bool) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", domain, key, "-bool", value ? "true" : "false"]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[SystemCommandService] Failed to write defaults: \(error)")
            return false
        }
    }

    /// 运行 Shell 命令
    @discardableResult
    private func runShellCommand(_ path: String, arguments: [String] = []) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[SystemCommandService] Failed to run shell command: \(error)")
            return false
        }
    }

    /// 运行 AppleScript
    private func runAppleScript(_ script: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[SystemCommandService] Failed to run AppleScript: \(error)")
            return false
        }
    }
}
