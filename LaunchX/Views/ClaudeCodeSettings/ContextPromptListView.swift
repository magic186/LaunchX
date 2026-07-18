import SwiftUI

/// 上下文预设列表视图（按应用过滤；Claude / Codex 面板共用）
struct ContextPromptListView: View {
    let app: AppTarget

    @StateObject private var service = ContextPromptService.shared
    @State private var showingForm = false
    @State private var editingPrompt: ContextPrompt?
    @State private var showingPresets = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var title: String {
        app == .claude ? "上下文管理" : "上下文管理"
    }

    private var filteredPrompts: [ContextPrompt] {
        service.prompts
            .filter { $0.apps.contains(app) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private func isActive(_ prompt: ContextPrompt) -> Bool {
        service.currentClaudePrompt?.id == prompt.id || service.currentCodexPrompt?.id == prompt.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: { showingPresets = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("从预设")
                    }
                    .font(.system(size: 12))
                }
                Button(action: { showingForm = true }) {
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

            if filteredPrompts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无上下文预设")
                        .foregroundColor(.secondary)
                    Text("点击「从预设」快速添加，或「添加」手动创建")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredPrompts) { prompt in
                            ContextPromptRowView(
                                prompt: prompt,
                                isActive: isActive(prompt),
                                onActivate: { activate(prompt) },
                                onEdit: { editingPrompt = prompt },
                                onDuplicate: { duplicate(prompt) },
                                onDelete: { delete(prompt) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            ContextPromptFormView(isPresented: $showingForm, defaultApp: app)
        }
        .sheet(item: $editingPrompt) { prompt in
            ContextPromptFormView(
                isPresented: Binding(
                    get: { editingPrompt != nil },
                    set: { if !$0 { editingPrompt = nil } }
                ),
                editingPrompt: prompt
            )
        }
        .sheet(isPresented: $showingPresets) {
            ContextPromptPresetView(isPresented: $showingPresets, defaultApp: app)
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - 操作

    private func activate(_ prompt: ContextPrompt) {
        do {
            try service.switchPrompt(to: prompt)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func duplicate(_ prompt: ContextPrompt) {
        do {
            try service.duplicatePrompt(prompt)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func delete(_ prompt: ContextPrompt) {
        do {
            if try !service.deletePrompt(prompt) {
                errorMessage = "无法删除当前激活的上下文预设，请先切换到其他预设"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - 上下文预设行

struct ContextPromptRowView: View {
    let prompt: ContextPrompt
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: prompt.icon ?? prompt.category.iconName)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: prompt.iconColor ?? "#007AFF") ?? .accentColor)
                .frame(width: 24)

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .font(.system(size: 13, weight: .medium))
                    if isActive {
                        Text("激活")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                    // 适用应用标记
                    ForEach(Array(prompt.apps), id: \.self) { target in
                        Image(systemName: target.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(prompt.category.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if !prompt.content.isEmpty {
                    Text(prompt.content.split(separator: "\n").first.map(String.init) ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 操作按钮
            if !isActive {
                Button(action: onActivate) {
                    Text("启用")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("编辑")

            Button(action: onDuplicate) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("复制")

            if !isActive {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.7))
                .help("删除")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}
