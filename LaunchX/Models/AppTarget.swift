import Foundation

/// 配置同步的目标应用
enum AppTarget: String, Codable, CaseIterable, Hashable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "bubble.left.and.bubble.right"
        case .codex: return "terminal"
        }
    }
}
