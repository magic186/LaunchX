import SwiftUI

/// 上下文预设选择器（从内置模板一键创建）
struct ContextPromptPresetView: View {
    @Binding var isPresented: Bool
    @StateObject private var service = ContextPromptService.shared
    var defaultApp: AppTarget = .claude

    @State private var selectedPreset: ContextPromptPreset?
    @State private var showError = false
    @State private var errorMessage = ""

    /// 仅展示适用于当前面板应用的预设
    private var groupedPresets: [(category: ContextPromptCategory, presets: [ContextPromptPreset])] {
        let applicable = ContextPromptPresetLoader.builtInPresets.filter { $0.apps.contains(defaultApp) }
        let grouped = Dictionary(grouping: applicable) { $0.category }
        return ContextPromptCategory.allCases.compactMap { category in
            guard let presets = grouped[category], !presets.isEmpty else { return nil }
            return (category: category, presets: presets)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("从预设添加上下文")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HSplitView {
                // 预设列表
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(groupedPresets, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.category.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)

                                ForEach(group.presets) { preset in
                                    ContextPresetRowView(
                                        preset: preset,
                                        isSelected: selectedPreset?.id == preset.id
                                    ) {
                                        selectedPreset = preset
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 200, maxWidth: 240)

                // 右侧详情
                if let preset = selectedPreset {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text(preset.name)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        if let desc = preset.presetDescription {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        Text("内容预览")
                            .font(.system(size: 12, weight: .medium))
                        ScrollView {
                            Text(preset.content)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: .infinity)

                        HStack {
                            Spacer()
                            Button("取消") { isPresented = false }
                            Button("添加") {
                                add(from: preset)
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 280)
                } else {
                    VStack {
                        Spacer()
                        Text("选择一个预设")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(minWidth: 280)
                }
            }
        }
        .frame(width: 640, height: 460)
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func add(from preset: ContextPromptPreset) {
        do {
            try service.addPrompt(preset.createPrompt())
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 预设行

struct ContextPresetRowView: View {
    let preset: ContextPromptPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: preset.icon ?? preset.category.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: preset.iconColor ?? "#007AFF") ?? .accentColor)
                    .frame(width: 20)
                Text(preset.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
