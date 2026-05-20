import Carbon.HIToolbox
import Cocoa

class PanelManager: NSObject, NSWindowDelegate {
    static let shared = PanelManager()

    private(set) var isPanelVisible: Bool = false

    // Callback to reset view state before hiding
    var onWillHide: (() -> Void)?
    // Callback when panel is about to show
    var onWillShow: (() -> Void)?

    private var panel: FloatingPanel!
    private var viewController: SearchPanelViewController?
    private var lastShowTime: Date = .distantPast
    private var isSetup = false

    // 用于快捷键触发 IDE 模式
    private var pendingIDEMode: (path: String, ideType: IDEType)?

    private override init() {
        super.init()
    }

    // 窗口尺寸常量
    private let panelWidth: CGFloat = 650
    private let panelExpandedHeight: CGFloat = 500

    // 计算窗口顶部应该在的Y坐标（基于展开后高度的中心位置）
    private func calculatePanelTopY() -> CGFloat {
        let screenRect = NSScreen.main?.frame ?? .zero
        // 以展开后的高度计算中心，返回窗口顶部的Y坐标
        return screenRect.midY + panelExpandedHeight / 2 + 50
    }

    /// Must be called once after app launches
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        let defaultWindowMode = UserDefaults.standard.string(forKey: "defaultWindowMode") ?? "full"
        let initialHeight: CGFloat = (defaultWindowMode == "simple") ? 80 : 500
        let topY = calculatePanelTopY()
        // origin.y = 顶部Y - 窗口高度（macOS坐标系从左下角开始）
        let originY = topY - initialHeight
        let originX = (NSScreen.main?.frame.midX ?? 0) - panelWidth / 2

        let rect = NSRect(
            origin: NSPoint(x: originX, y: originY),
            size: NSSize(width: panelWidth, height: initialHeight))

        self.panel = FloatingPanel(contentRect: rect)
        self.panel.delegate = self

        // Setup AppKit view controller
        viewController = SearchPanelViewController()
        panel.contentView = viewController?.view
    }

    func togglePanel() {
        guard isSetup else { return }

        if panel.isVisible && panel.isKeyWindow {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard isSetup else { return }

        lastShowTime = Date()

        // Notify before showing
        onWillShow?()

        // 获取鼠标所在的屏幕（全屏应用时更准确）
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen =
            NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let screenFrame = currentScreen?.frame ?? .zero

        // 保持窗口顶部位置一致（基于展开后高度计算）
        let topY = screenFrame.midY + panelExpandedHeight / 2 + 50
        let currentHeight = panel.frame.height
        let originY = topY - currentHeight
        let originX = screenFrame.midX - panelWidth / 2
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))

        // 确保面板移动到当前空间（不能同时使用 canJoinAllSpaces 和 moveToActiveSpace）
        panel.collectionBehavior = [
            .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle,
        ]

        // 切换到英文输入法
        if let englishSource = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() {
            TISSelectInputSource(englishSource)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Focus the search field
        viewController?.focus()

        isPanelVisible = true
    }

    func hidePanel() {
        guard isSetup else { return }

        print("PanelManager: hidePanel called, onWillHide is \(onWillHide == nil ? "nil" : "set")")

        // Reset state BEFORE hiding (通过回调通知 ViewController)
        onWillHide?()

        panel.orderOut(nil)

        isPanelVisible = false
    }

    // MARK: - IDE 模式入口

    /// 以 IDE 模式显示面板（用于快捷键触发）
    /// - Parameters:
    ///   - idePath: IDE 应用路径
    ///   - ideType: IDE 类型
    func showPanelInIDEMode(idePath: String, ideType: IDEType) {
        guard isSetup else { return }

        // 发送通知让 SearchPanelViewController 进入 IDE 模式
        NotificationCenter.default.post(
            name: .enterIDEModeDirectly,
            object: nil,
            userInfo: ["path": idePath, "ideType": ideType]
        )

        // 只有面板未显示时才调用 showPanel()，避免重复触发 onWillShow
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 显示面板并直接进入网页直达 Query 模式
    func showPanelInWebLinkQueryMode(tool: ToolItem) {
        guard isSetup else { return }

        // 发送通知让 SearchPanelViewController 进入网页直达 Query 模式
        NotificationCenter.default.post(
            name: .enterWebLinkQueryModeDirectly,
            object: nil,
            userInfo: ["tool": tool]
        )

        // 只有面板未显示时才调用 showPanel()，避免重复触发 onWillShow
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 显示面板并直接进入实用工具模式
    func showPanelInUtilityMode(tool: ToolItem) {
        guard isSetup else { return }

        // 发送通知让 SearchPanelViewController 进入实用工具模式
        NotificationCenter.default.post(
            name: .enterUtilityModeDirectly,
            object: nil,
            userInfo: ["tool": tool]
        )

        // 只有面板未显示时才调用 showPanel()，避免重复触发 onWillShow
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 显示面板并直接进入书签搜索模式
    func showPanelInBookmarkMode() {
        guard isSetup else { return }

        // 先发送通知进入书签模式（这样 focus() 调用时 isInBookmarkMode 已经是 true）
        NotificationCenter.default.post(
            name: .enterBookmarkModeDirectly,
            object: nil
        )

        // 再显示面板
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 显示面板并直接进入 2FA 短信模式
    func showPanelIn2FAMode() {
        guard isSetup else { return }

        // 先发送通知进入 2FA 模式（这样 focus() 调用时 isIn2FAMode 已经是 true）
        NotificationCenter.default.post(
            name: .enter2FAModeDirectly,
            object: nil
        )

        // 再显示面板
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 显示面板并直接进入表情包模式
    func showPanelInMemeMode() {
        guard isSetup else { return }

        // 先发送通知进入表情包模式
        NotificationCenter.default.post(
            name: .enterMemeModeDirectly,
            object: nil
        )

        // 再显示面板
        if !panel.isVisible {
            showPanel()
        }
    }

    /// 在收藏模式下显示面板（通过快捷键直接进入）
    func showPanelInFavoriteMode() {
        guard isSetup else { return }

        // 先发送通知进入收藏模式
        NotificationCenter.default.post(
            name: .enterFavoriteModeDirectly,
            object: nil
        )

        // 再显示面板
        if !panel.isVisible {
            showPanel()
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard isSetup else { return }

        if let window = notification.object as? NSWindow, window == self.panel {
            if Date().timeIntervalSince(lastShowTime) < 0.3 {
                return
            }
            hidePanel()
        }
    }
}
