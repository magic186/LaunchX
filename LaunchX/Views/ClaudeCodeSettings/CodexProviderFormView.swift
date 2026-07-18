import SwiftUI

/// Codex Provider 添加/编辑表单
struct CodexProviderFormView: View {
    @Binding var isPresented: Bool
    @StateObject private var service = ClaudeProviderService.shared
    var editingProvider: ClaudeProvider?

    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var baseUrl: String = ""
    @State private var model: String = ""
    @State private var envKey: String = "OPENAI_API_KEY"
    @State private var providerId: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text(editingProvider != nil ? "编辑 Codex Provider" : "添加 Codex Provider")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 名称
                    fieldRow(label: "名称", placeholder: "例如：OpenAI Official", text: $name)

                    // Base URL
                    fieldRow(label: "Base URL", placeholder: "https://api.openai.com/v1", text: $baseUrl)

                    // Model
                    fieldRow(label: "Model", placeholder: "例如：o3, gpt-4.1", text: $model)

                    // Env Key
                    HStack(spacing: 12) {
                        Text("环境变量名")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                            .padding(.top, 4)
                        TextField("OPENAI_API_KEY", text: $envKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                                .padding(.top, 4)
                            HStack {
                                if showApiKey {
                                    TextField("sk-...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                } else {
                                    SecureField("sk-...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                Button(action: { showApiKey.toggle() }) {
                                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 24)
                            }
                        }
                        Text("API Key 将自动写入 shell 配置文件并设置为环境变量")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 92)
                    }

                    // Provider ID
                    fieldRow(label: "Provider ID", placeholder: "自动从名称生成", text: $providerId)

                    // 配置预览
                    VStack(alignment: .leading, spacing: 4) {
                        Text("配置预览 (~/.codex/config.toml)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(configPreview)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(editingProvider != nil ? "保存" : "添加") {
                    saveProvider()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 520)
        .onAppear {
            if let provider = editingProvider {
                name = provider.name
                apiKey = provider.settingsConfig["CODEX_API_KEY"]
                    ?? provider.settingsConfig["ANTHROPIC_API_KEY"]
                    ?? ""
                baseUrl = provider.settingsConfig["CODEX_BASE_URL"]
                    ?? provider.settingsConfig["ANTHROPIC_BASE_URL"]
                    ?? ""
                model = provider.settingsConfig["CODEX_MODEL"]
                    ?? provider.settingsConfig["ANTHROPIC_MODEL"]
                    ?? ""
                envKey = provider.settingsConfig["CODEX_ENV_KEY"] ?? "OPENAI_API_KEY"
                providerId = provider.settingsConfig["CODEX_PROVIDER_ID"]
                    ?? generateProviderId(from: provider.name)
            }
        }
        .onChange(of: name) { _, newValue in
            if editingProvider == nil && providerId.isEmpty {
                providerId = generateProviderId(from: newValue)
            }
        }
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 80, alignment: .trailing)
                .padding(.top, 4)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private var configPreview: String {
        let resolvedId = providerId.isEmpty ? generateProviderId(from: name) : providerId
        let resolvedEnvKey = envKey.isEmpty ? "OPENAI_API_KEY" : envKey
        var lines: [String] = []
        if !model.isEmpty { lines.append("model = \"\(model)\"") }
        lines.append("model_provider = \"\(resolvedId)\"")
        lines.append("")
        lines.append("[model_providers.\(resolvedId)]")
        lines.append("name = \"\(name.isEmpty ? "..." : name)\"")
        if !baseUrl.isEmpty { lines.append("base_url = \"\(baseUrl)\"") }
        lines.append("wire_api = \"responses\"")
        lines.append("env_key = \"\(resolvedEnvKey)\"")
        return lines.joined(separator: "\n")
    }

    private func generateProviderId(from name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private func saveProvider() {
        let resolvedProviderId = providerId.isEmpty ? generateProviderId(from: name) : providerId
        let resolvedEnvKey = envKey.isEmpty ? "OPENAI_API_KEY" : envKey

        var settingsConfig: [String: String] = [:]
        if !apiKey.isEmpty { settingsConfig["CODEX_API_KEY"] = apiKey }
        if !baseUrl.isEmpty { settingsConfig["CODEX_BASE_URL"] = baseUrl }
        if !model.isEmpty { settingsConfig["CODEX_MODEL"] = model }
        settingsConfig["CODEX_ENV_KEY"] = resolvedEnvKey
        settingsConfig["CODEX_PROVIDER_ID"] = resolvedProviderId

        if let existing = editingProvider {
            var updated = existing
            updated.name = name
            updated.settingsConfig = settingsConfig
            try? service.updateProvider(updated)
        } else {
            let provider = ClaudeProvider(
                name: name,
                settingsConfig: settingsConfig,
                category: .thirdParty,
                apps: [.codex]
            )
            try? service.addProvider(provider)
        }
        isPresented = false
    }
}
