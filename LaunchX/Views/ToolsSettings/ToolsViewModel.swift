import Combine
import SwiftUI
import UniformTypeIdentifiers

class ToolsViewModel: ObservableObject {
    @Published var tools: [ToolItem] = []
    @Published var appExpanded: Bool = true
    @Published var webLinkExpanded: Bool = true
    @Published var utilityExpanded: Bool = true
    @Published var systemCommandExpanded: Bool = true

    init() {
        loadConfig()
    }

    // MARK: - 便捷访问

    var appTools: [ToolItem] {
        tools.filter { $0.type == .app }
    }

    var webLinkTools: [ToolItem] {
        tools.filter { $0.type == .webLink }
    }

    var utilityTools: [ToolItem] {
        tools.filter { $0.type == .utility }
    }

    var systemCommandTools: [ToolItem] {
        tools.filter { $0.type == .systemCommand }
    }

    // MARK: - 配置加载和保存

    private func loadConfig() {
        let config = ToolsConfig.load()
        tools = config.tools
    }

    private func saveConfig() {
        var config = ToolsConfig()
        config.tools = tools
        config.save()

        // 重新加载快捷键
        HotKeyService.shared.reloadToolHotKeys(from: config)
    }

    // MARK: - 工具操作

    func updateTool(_ tool: ToolItem) {
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[index] = tool
            saveConfig()
        }
    }

    func deleteTool(_ tool: ToolItem) {
        tools.removeAll { $0.id == tool.id }
        IconCacheManager.shared.removeIcon(for: tool.id)
        saveConfig()
    }

    func addTool(_ tool: ToolItem) {
        // 检查是否已存在
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
        saveConfig()
    }

    func addApp(path: String) {
        guard !tools.contains(where: { $0.type == .app && $0.path == path }) else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        guard path.hasSuffix(".app") || isDir.boolValue else { return }

        let tool = ToolItem.app(path: path)
        tools.append(tool)
        saveConfig()
    }

    // MARK: - 拖拽处理

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    data, _ in
                    guard let data = data as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }

                    DispatchQueue.main.async {
                        self.addApp(path: url.path)
                    }
                }
                handled = true
            }
        }

        return handled
    }

    // MARK: - 文件选择器

    func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application, .folder]
        panel.message = "选择要添加的应用或文件夹"
        panel.prompt = "添加"

        if panel.runModal() == .OK {
            for url in panel.urls {
                addApp(path: url.path)
            }
        }
    }
}
