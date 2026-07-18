import SwiftUI

/// Codex CLI 独立配置主视图
/// 与 Claude Code 并列在高级扩展侧边栏
struct CodexMainSettingsView: View {
    @StateObject private var providerService = ClaudeProviderService.shared
    @StateObject private var mcpService = ClaudeMcpService.shared
    @StateObject private var skillService = ClaudeSkillService.shared

    @State private var selectedTab: CodexMainTab = .providers
    @State private var settings = CodexSwitcherSettings.load()
    @State private var showHotKeyPopover: Bool = false

    private let labelWidth: CGFloat = 140

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 标题头
                HStack(spacing: SettingsHeaderStyle.iconTitleSpacing) {
                    if let name = AdvancedExtensionType.codex.iconImageName,
                        let logo = NSImage(named: name)
                    {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: SettingsHeaderStyle.iconFrameSize, height: SettingsHeaderStyle.iconFrameSize)
                    } else {
                        Image(systemName: AdvancedExtensionType.codex.sfSymbolName)
                            .font(.system(size: SettingsHeaderStyle.iconSize))
                            .foregroundColor(AdvancedExtensionType.codex.iconColor)
                            .frame(width: SettingsHeaderStyle.iconFrameSize, height: SettingsHeaderStyle.iconFrameSize)
                    }
                    Text("Codex")
                        .font(SettingsHeaderStyle.titleFont)
                        .fontWeight(SettingsHeaderStyle.titleFontWeight)
                    Spacer()

                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: settings.isEnabled) { _, _ in
                            settings.save()
                        }
                }
                .padding(.horizontal, SettingsHeaderStyle.horizontalPadding)
                .padding(.top, SettingsHeaderStyle.topPadding)
                .padding(.bottom, SettingsHeaderStyle.bottomPadding)

                Divider()

                // 快捷键行
                HStack {
                    Text("直接打开扩展快捷键:")
                        .frame(width: labelWidth, alignment: .trailing)
                    ExtensionHotKeyButton(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers,
                        showPopover: $showHotKeyPopover
                    )
                    .popover(isPresented: $showHotKeyPopover) {
                        ExtensionHotKeyRecorderPopover(
                            keyCode: $settings.hotKeyCode,
                            modifiers: $settings.hotKeyModifiers,
                            isPresented: $showHotKeyPopover,
                            exampleKey: "X",
                            onSave: { settings.save() },
                            onUnregister: { HotKeyService.shared.unregisterCodexHotKey() },
                            onRegister: { keyCode, modifiers in
                                HotKeyService.shared.registerCodexHotKey(keyCode: keyCode, modifiers: modifiers)
                            },
                            checkConflict: { keyCode, modifiers in
                                HotKeyService.shared.checkConflict(
                                    keyCode: keyCode,
                                    modifiers: modifiers,
                                    excludingMainHotKey: false
                                )
                            }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // 别名行
                HStack {
                    Text("别名:")
                        .frame(width: labelWidth, alignment: .trailing)
                    TextField("cx", text: $settings.alias)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: settings.alias) { _, _ in
                            settings.save()
                        }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Divider()
                    .padding(.top, 16)

                // Tab 切换
                HStack(spacing: 0) {
                    ForEach(CodexMainTab.allCases) { tab in
                        Button(action: { selectedTab = tab }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 12))
                                Text(tab.title)
                                    .font(.system(size: 13))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider()
                    .padding(.top, 8)

                // 内容区
                Group {
                    switch selectedTab {
                    case .providers:
                        CodexProviderListView()
                    case .context:
                        ContextPromptListView(app: .codex)
                    case .mcp:
                        CodexMcpListView()
                    case .skills:
                        CodexSkillsListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if providerService.providers.filter({ $0.apps.contains(.codex) }).isEmpty {
                _ = providerService.importDefaultCodexConfig()
            }
            if mcpService.servers.filter({ $0.apps.contains(.codex) }).isEmpty {
                _ = mcpService.importFromCodex()
            }
        }
    }
}

// MARK: - Codex Tab Enum

private enum CodexMainTab: String, CaseIterable, Identifiable {
    case providers
    case context
    case mcp
    case skills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: return "Provider"
        case .context: return "上下文"
        case .mcp: return "MCP"
        case .skills: return "Skills"
        }
    }

    var iconName: String {
        switch self {
        case .providers: return "server.rack"
        case .context: return "text.bubble"
        case .mcp: return "puzzlepiece.extension"
        case .skills: return "wand.and.stars"
        }
    }
}

// MARK: - Provider 列表

private struct CodexProviderListView: View {
    @StateObject private var providerService = ClaudeProviderService.shared
    @State private var showForm = false
    @State private var editingProvider: ClaudeProvider?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Provider 管理")
                    .font(.headline)
                Spacer()
                Button(action: { showForm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            let codexProviders = providerService.providers.filter { $0.apps.contains(.codex) }

            if codexProviders.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无 Codex Provider")
                        .foregroundColor(.secondary)
                    Text("点击「添加」配置 Codex CLI 的 API 连接")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(codexProviders) { provider in
                            codexProviderRow(provider)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showForm) {
            CodexProviderFormView(isPresented: $showForm)
        }
        .sheet(item: $editingProvider) { provider in
            CodexProviderFormView(
                isPresented: Binding(
                    get: { editingProvider != nil },
                    set: { if !$0 { editingProvider = nil } }
                ),
                editingProvider: provider
            )
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func codexProviderRow(_ provider: ClaudeProvider) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))
                    if provider.isCurrent {
                        Text("激活")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
                if let url = provider.settingsConfig["CODEX_BASE_URL"] {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let model = provider.settingsConfig["CODEX_MODEL"] {
                    Text("Model: \(model)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !provider.isCurrent {
                Button("启用") {
                    do {
                        try providerService.switchProvider(to: provider)
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.system(size: 12))
            }

            Button {
                editingProvider = provider
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            if !provider.isCurrent {
                Button {
                    do {
                        if try !providerService.deleteProvider(provider) {
                            errorMessage = "无法删除当前激活的 Provider"
                            showError = true
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(provider.isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - MCP 列表

private struct CodexMcpListView: View {
    @StateObject private var mcpService = ClaudeMcpService.shared
    @State private var showForm = false
    @State private var editingServer: McpServer?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MCP 服务器")
                    .font(.headline)
                Spacer()
                Button(action: {
                    let count = mcpService.importFromCodex()
                    if count == 0 {
                        errorMessage = "未找到可导入的 Codex MCP 配置"
                        showError = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("从 Codex 导入")
                    }
                    .font(.system(size: 12))
                }
                Button(action: { showForm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            let codexServers = mcpService.servers.filter { $0.apps.contains(.codex) }

            if codexServers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无 Codex MCP 服务器")
                        .foregroundColor(.secondary)
                    Text("点击「添加」创建新的 MCP，或「从 Codex 导入」已有配置")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(codexServers) { server in
                            codexMcpRow(server)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showForm) {
            CodexMcpFormView(isPresented: $showForm)
        }
        .sheet(item: $editingServer) { server in
            CodexMcpFormView(
                isPresented: Binding(
                    get: { editingServer != nil },
                    set: { if !$0 { editingServer = nil } }
                ),
                editingServer: server
            )
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func codexMcpRow(_ server: McpServer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: server.serverType == .stdio ? "terminal" : "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(server.serverType.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(3)
                }
                Text(server.configSummary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                do {
                    try mcpService.toggleEnabled(server)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } label: {
                Image(systemName: server.isEnabled ? "pause.circle" : "play.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(server.isEnabled ? .orange : .green)

            Button {
                editingServer = server
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button {
                do {
                    try mcpService.deleteServer(server)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(server.isEnabled ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - Skills 列表（含发现和安装）

private enum CodexSkillTab: String, CaseIterable, Identifiable {
    case installed
    case discover

    var id: String { rawValue }
    var title: String {
        switch self {
        case .installed: return "已安装"
        case .discover: return "发现"
        }
    }
}

private struct CodexSkillsListView: View {
    @StateObject private var skillService = ClaudeSkillService.shared
    @State private var selectedTab: CodexSkillTab = .installed
    @State private var showingRepoSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(CodexSkillTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                if selectedTab == .discover {
                    Button(action: { Task { await skillService.discoverSkills(for: .codex) } }) {
                        HStack(spacing: 4) {
                            if skillService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("刷新")
                        }
                        .font(.system(size: 12))
                    }
                    .disabled(skillService.isLoading)
                }

                if selectedTab == .installed {
                    Button(action: {
                        let unmanaged = skillService.scanUnmanagedCodexSkills()
                        for skill in unmanaged {
                            try? skillService.importCodexSkill(skill)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("从 Codex 导入")
                        }
                        .font(.system(size: 12))
                    }
                }

                Button(action: { showingRepoSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // 内容
            Group {
                switch selectedTab {
                case .installed:
                    codexInstalledList
                case .discover:
                    codexDiscoverList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingRepoSettings) {
            SkillRepoSettingsView(isPresented: $showingRepoSettings)
        }
        .onAppear {
            skillService.initDefaultRepos()
        }
    }

    // MARK: - 已安装列表

    private var codexInstalledList: some View {
        let codexSkills = skillService.skills.filter { $0.apps.contains(.codex) }

        return Group {
            if codexSkills.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无已安装的 Codex Skill")
                        .foregroundColor(.secondary)
                    Text("切换到「发现」标签浏览和安装 Skills")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(codexSkills) { skill in
                            SkillRowView(
                                skill: skill,
                                onToggle: { try? skillService.toggleEnabled(skill) },
                                onUninstall: { try? skillService.uninstallSkill(skill) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - 发现列表

    private var codexDiscoverList: some View {
        Group {
            if skillService.discoveredSkills.isEmpty && !skillService.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(skillService.repos.isEmpty ? "请先添加 Skill 仓库" : "点击「刷新」发现可用 Skills")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(skillService.discoveredSkills) { discovered in
                            let isInstalledForCodex = skillService.skills.contains {
                                $0.apps.contains(.codex) &&
                                $0.repoOwner == discovered.repoOwner &&
                                $0.repoName == discovered.repoName &&
                                $0.directory == discovered.directory
                            }

                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(discovered.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(discovered.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Text(discovered.repoOwner + "/" + discovered.repoName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)

                                if isInstalledForCodex {
                                    Text("已安装")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                } else {
                                    Button("安装") {
                                        Task {
                                            try? await skillService.installSkill(discovered, for: .codex)
                                            await skillService.discoverSkills(for: .codex)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

#Preview {
    CodexMainSettingsView()
        .frame(width: 480, height: 500)
}
