import SwiftUI

/// Provider 列表视图
struct ProviderListView: View {
    @StateObject private var service = ClaudeProviderService.shared
    @State private var showingAddSheet = false
    @State private var editingProvider: ClaudeProvider?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("Provider 管理")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
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

            let claudeProviders = service.providers.filter { $0.apps.contains(.claude) }

            if claudeProviders.isEmpty {
                // 空状态
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无 Provider")
                        .foregroundColor(.secondary)
                    Text("点击「添加」手动配置 Provider")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Provider 列表
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(claudeProviders) { provider in
                            ProviderRowView(
                                provider: provider,
                                isCurrent: provider.isCurrent,
                                onActivate: { activateProvider(provider) },
                                onEdit: { editingProvider = provider },
                                onDelete: { deleteProvider(provider) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ProviderFormView(isPresented: $showingAddSheet)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderFormView(
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

    private func activateProvider(_ provider: ClaudeProvider) {
        do {
            try service.switchProvider(to: provider)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteProvider(_ provider: ClaudeProvider) {
        do {
            if try !service.deleteProvider(provider) {
                errorMessage = "无法删除当前激活的 Provider，请先切换到其他 Provider"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Provider Row

struct ProviderRowView: View {
    let provider: ClaudeProvider
    let isCurrent: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: provider.category.iconName)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: provider.iconColor ?? "#007AFF") ?? .accentColor)
                .frame(width: 24)

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))
                    if isCurrent {
                        Text("激活")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                    Text(provider.category.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let baseUrl = provider.baseUrl {
                    Text(baseUrl)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 操作按钮 - 直接展示在右侧
            if !isCurrent {
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

            if !isCurrent {
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
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6 else { return nil }
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
