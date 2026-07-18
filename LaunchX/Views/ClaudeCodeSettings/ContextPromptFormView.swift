import SwiftUI

/// 上下文预设 添加/编辑表单
struct ContextPromptFormView: View {
    @Binding var isPresented: Bool
    @StateObject private var service = ContextPromptService.shared
    var editingPrompt: ContextPrompt?
    var defaultApp: AppTarget = .claude

    // MARK: - 表单状态

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var category: ContextPromptCategory = .general
    @State private var appsClaude: Bool = true
    @State private var appsCodex: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var selectedApps: Set<AppTarget> {
        var apps: Set<AppTarget> = []
        if appsClaude { apps.insert(.claude) }
        if appsCodex { apps.insert(.codex) }
        return apps
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedApps.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basicSection
                    Divider()
                    appsSection
                    Divider()
                    contentSection
                }
                .padding(20)
            }

            Divider()

            actionBar
        }
        .frame(width: 560, height: 600)
        .onAppear { populate() }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        HStack {
            Image(systemName: editingPrompt?.category.iconName ?? category.iconName)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
            Text(editingPrompt != nil ? "编辑上下文" : "添加上下文")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("基本信息", icon: "info.circle")

            HStack(spacing: 12) {
                Text("名称")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 90, alignment: .trailing)
                    .padding(.top, 4)
                TextField("例如：严格代码审查", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(alignment: .top, spacing: 12) {
                Text("分类")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 90, alignment: .trailing)
                    .padding(.top, 4)
                Picker("", selection: $category) {
                    ForEach(ContextPromptCategory.allCases, id: \.self) { cat in
                        HStack(spacing: 6) {
                            Image(systemName: cat.iconName).font(.system(size: 11))
                            Text(cat.displayName)
                        }
                        .tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 应用选择

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("适用应用", icon: "apps.iphone")

            HStack(spacing: 24) {
                appToggle("Claude Code", icon: "bubble.left.and.bubble.right", isOn: $appsClaude)
                appToggle("Codex", icon: "terminal", isOn: $appsCodex)
                Spacer()
            }
            .padding(.leading, 102)

            Text("选择该上下文预设作用于哪些 CLI；启用时会写入对应的全局指令文件。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 102)
        }
    }

    private func appToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12))
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - 正文

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text("上下文内容（Markdown）")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(content.count) 字")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 220)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .cornerRadius(6)

            Text("此内容会在启用预设时写入 CLAUDE.md / AGENTS.md 末尾会自动追加管理标记。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 底部操作栏

    private var actionBar: some View {
        HStack {
            Spacer()
            Button("取消") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button(editingPrompt != nil ? "保存" : "添加") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 辅助

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    // MARK: - 数据填充 / 保存

    private func populate() {
        if let prompt = editingPrompt {
            name = prompt.name
            content = prompt.content
            category = prompt.category
            appsClaude = prompt.apps.contains(.claude)
            appsCodex = prompt.apps.contains(.codex)
        } else {
            appsClaude = (defaultApp == .claude)
            appsCodex = (defaultApp == .codex)
        }
    }

    private func save() {
        let apps = selectedApps
        guard !apps.isEmpty else {
            errorMessage = "请至少选择一个适用应用"
            showError = true
            return
        }

        if let existing = editingPrompt {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.content = content
            updated.category = category
            updated.apps = apps
            do {
                try service.updatePrompt(updated)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                return
            }
        } else {
            let prompt = ContextPrompt(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                apps: apps,
                category: category
            )
            do {
                try service.addPrompt(prompt)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                return
            }
        }
        isPresented = false
    }
}
