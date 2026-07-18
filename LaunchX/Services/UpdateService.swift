import Combine
import Foundation
import Sparkle

/// 检查更新服务 - 集成 Sparkle 框架实现无感自动更新
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    private var updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false
    /// 标记是否正在准备更新重启，用于在 AppDelegate 中允许程序退出
    var isPreparingForUpdate = false

    private override init() {
        super.init()
        // 初始化 Sparkle 控制器
        // SPUStandardUpdaterController 会自动处理大部分 UI 逻辑
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

        // 绑定更新状态
        self.updaterController?.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 检查更新
    /// - Parameter manual: 是否由用户点击触发（手动触发会显示详细进度 UI）
    func checkForUpdates(manual: Bool = false) {
        print("UpdateService: Checking for updates (manual: \(manual))")
        if manual {
            updaterController?.checkForUpdates(nil)
        } else {
            // 启动时静默检查
            updaterController?.updater.checkForUpdatesInBackground()
        }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateService: SPUUpdaterDelegate {
    /// 这里的 feed URL 应该指向你服务器上的 Appcast.xml 文件
    /// GitHub Releases 环境下，通常需要一个工具生成的 XML
    func feedURLString(for updater: SPUUpdater) -> String? {
        // 替换为你的 GitHub Releases 对应的 Appcast URL
        // 注意：Sparkle 需要一个 appcast.xml 文件来识别版本更新
        return "https://raw.githubusercontent.com/magic186/LaunchX/main/appcast.xml"
    }

    /// 可以在这里自定义是否允许在特定情况下检查更新
    func updaterShouldPromptForPermissionToCheck(forUpdates updates: SPUUpdater) -> Bool {
        return false  // 我们已经在逻辑中控制了检查时机
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        print("UpdateService: Will relaunch application for update")
        isPreparingForUpdate = true

        // 标记应用即将因更新而重启
        UserDefaults.standard.set(true, forKey: "didJustUpdateAndRelaunch")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("UpdateService: Update aborted with error: \(error.localizedDescription)")
        isPreparingForUpdate = false
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("UpdateService: No update found")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        print("UpdateService: Will install update: \(item.displayVersionString)")
    }
}
