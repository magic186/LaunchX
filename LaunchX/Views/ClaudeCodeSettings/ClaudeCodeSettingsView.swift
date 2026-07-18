import SwiftUI

/// Claude Code 管理主视图
struct ClaudeCodeSettingsView: View {
    @StateObject private var providerService = ClaudeProviderService.shared
    @State private var selectedTab: ClaudeCodeTab = .providers
    @State private var settings = ClaudeCodeSwitcherSettings.load()
    @State private var showHotKeyPopover: Bool = false

    private let labelWidth: CGFloat = 140

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 标准头部: 图标 + 标题 + 启用开关
                HStack(spacing: SettingsHeaderStyle.iconTitleSpacing) {
                    if let name = AdvancedExtensionType.claudeCode.iconImageName,
                        let logo = NSImage(named: name)
                    {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: SettingsHeaderStyle.iconFrameSize, height: SettingsHeaderStyle.iconFrameSize)
                    } else {
                        Image(systemName: AdvancedExtensionType.claudeCode.sfSymbolName)
                            .font(.system(size: SettingsHeaderStyle.iconSize))
                            .foregroundColor(AdvancedExtensionType.claudeCode.iconColor)
                            .frame(width: SettingsHeaderStyle.iconFrameSize, height: SettingsHeaderStyle.iconFrameSize)
                    }
                    Text("Claude Code")
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
                            exampleKey: "C",
                            onSave: { settings.save() },
                            onUnregister: { HotKeyService.shared.unregisterClaudeCodeHotKey() },
                            onRegister: { keyCode, modifiers in
                                HotKeyService.shared.registerClaudeCodeHotKey(keyCode: keyCode, modifiers: modifiers)
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
                    TextField("cc", text: $settings.alias)
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
                    ForEach(ClaudeCodeTab.allCases) { tab in
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
                        ProviderListView()
                    case .context:
                        ContextPromptListView(app: .claude)
                    case .mcp:
                        McpServerListView()
                    case .skills:
                        SkillListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // 首次导入
            if providerService.providers.isEmpty {
                providerService.importDefaultConfig()
            }
        }
    }
}

enum ClaudeCodeTab: String, CaseIterable, Identifiable {
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

#Preview {
    ClaudeCodeSettingsView()
        .frame(width: 480, height: 500)
}
