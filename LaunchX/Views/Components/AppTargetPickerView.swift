import SwiftUI

/// 应用目标选择器组件
/// 显示 Claude Code / Codex 的可切换图标，用于控制配置项同步到哪些应用
struct AppTargetPickerView: View {
    @Binding var apps: Set<AppTarget>
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(AppTarget.allCases, id: \.self) { app in
                appButton(for: app)
            }
        }
    }

    @ViewBuilder
    private func appButton(for app: AppTarget) -> some View {
        let isActive = apps.contains(app)

        Button {
            if isActive {
                // 至少保留一个 app
                if apps.count > 1 {
                    apps.remove(app)
                }
            } else {
                apps.insert(app)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: app.iconName)
                    .font(compact ? .caption2 : .caption)
                if !compact {
                    Text(app.displayName)
                        .font(.caption2)
                }
            }
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("同步到 \(app.displayName)")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var apps: Set<AppTarget> = [.claude]
        var body: some View {
            VStack(spacing: 16) {
                AppTargetPickerView(apps: $apps)
                AppTargetPickerView(apps: $apps, compact: true)
                Text("Selected: \(apps.map(\.rawValue).sorted().joined(separator: ", "))")
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
