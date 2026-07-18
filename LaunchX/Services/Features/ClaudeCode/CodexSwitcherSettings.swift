import Foundation

/// Codex Switcher 搜索面板配置
struct CodexSwitcherSettings: Codable {
    var isEnabled: Bool
    var alias: String
    var hotKeyCode: UInt32
    var hotKeyModifiers: UInt32

    static let `default` = CodexSwitcherSettings(
        isEnabled: true,
        alias: "cx",
        hotKeyCode: 0,
        hotKeyModifiers: 0
    )

    private static let storageKey = "codexSwitcherSettings"

    static func load() -> CodexSwitcherSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(CodexSwitcherSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CodexSwitcherSettings.storageKey)
        }
    }
}
