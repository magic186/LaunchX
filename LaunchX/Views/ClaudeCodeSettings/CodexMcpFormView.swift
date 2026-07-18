import SwiftUI

/// Codex MCP 服务器添加/编辑表单
struct CodexMcpFormView: View {
    @Binding var isPresented: Bool
    @StateObject private var service = ClaudeMcpService.shared
    var editingServer: McpServer?

    @State private var name: String = ""
    @State private var configJson: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text(editingServer != nil ? "编辑 Codex MCP" : "添加 Codex MCP")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("名称")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 36, alignment: .trailing)
                    TextField("例如：filesystem", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $configJson)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )

                    HStack {
                        Text("JSON 格式的服务器配置")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("格式化") { formatJson() }
                            .font(.system(size: 11))
                            .controlSize(.small)
                    }

                    if let error = errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(16)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(editingServer != nil ? "保存" : "添加") { saveServer() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || configJson.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 400)
        .onAppear {
            if let server = editingServer {
                name = server.name
                let dict = server.serverConfig.mapValues { $0.value }
                if let data = try? JSONSerialization.data(
                    withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8)
                {
                    configJson = str
                }
            } else {
                configJson = """
                    {
                      "args": [
                        "-y",
                        "@modelcontextprotocol/server-filesystem"
                      ],
                      "command": "npx"
                    }
                    """
            }
        }
    }

    private func formatJson() {
        guard let data = configJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: formatted, encoding: .utf8)
        else {
            errorMessage = "无效的 JSON 格式"
            return
        }
        errorMessage = nil
        configJson = str
    }

    private func saveServer() {
        guard let data = configJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            errorMessage = "无效的 JSON 格式"
            return
        }

        var config: [String: AnyCodable] = [:]
        for (key, value) in json {
            config[key] = AnyCodable(value)
        }

        if let error = service.validateConfig(config) {
            errorMessage = error
            return
        }

        errorMessage = nil

        if let existing = editingServer {
            var updated = existing
            updated.name = name
            updated.serverConfig = config
            do {
                try service.updateServer(updated)
            } catch {
                errorMessage = "保存失败：\(error.localizedDescription)"
                return
            }
        } else {
            let server = McpServer(name: name, serverConfig: config, apps: [.codex])
            do {
                guard try service.addServer(server) == nil else { return }
            } catch {
                errorMessage = "添加失败：\(error.localizedDescription)"
                return
            }
        }
        isPresented = false
    }
}
