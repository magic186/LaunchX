import SwiftUI

/// Skill 仓库管理视图
struct SkillRepoSettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var service = ClaudeSkillService.shared
    @State private var newOwner: String = ""
    @State private var newName: String = ""
    @State private var newApps: Set<AppTarget> = [.claude, .codex]

    var body: some View {
        VStack(spacing: 16) {
            Text("Skill 仓库管理")
                .font(.headline)

            // 添加仓库
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Owner", text: $newOwner)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("/")
                        .foregroundColor(.secondary)
                    TextField("Repo Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Button("添加") {
                        if !newOwner.isEmpty && !newName.isEmpty {
                            service.addRepo(owner: newOwner, name: newName, apps: newApps)
                            newOwner = ""
                            newName = ""
                        }
                    }
                    .disabled(newOwner.isEmpty || newName.isEmpty)
                }

                HStack(spacing: 12) {
                    Text("适用:")
                        .font(.system(size: 12))
                    Toggle("Claude Code", isOn: Binding(
                        get: { newApps.contains(.claude) },
                        set: { on in if on { newApps.insert(.claude) } else { newApps.remove(.claude) } }
                    ))
                    .controlSize(.small)
                    Toggle("Codex", isOn: Binding(
                        get: { newApps.contains(.codex) },
                        set: { on in if on { newApps.insert(.codex) } else { newApps.remove(.codex) } }
                    ))
                    .controlSize(.small)
                }
            }

            Divider()

            // 仓库列表
            if service.repos.isEmpty {
                Text("暂无仓库配置")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(service.repos) { repo in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.idString)
                                    .font(.system(size: 13))
                                HStack(spacing: 4) {
                                    Text("分支: \(repo.branch)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    ForEach(Array(repo.apps).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { app in
                                        Text(app.displayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(app == .claude ? Color.brown : Color.green)
                                            .cornerRadius(3)
                                    }
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { repo.isEnabled },
                                set: { _ in
                                    if let index = service.repos.firstIndex(where: { $0.id == repo.id }) {
                                        service.repos[index].isEnabled.toggle()
                                        try? ClaudeDataStore.shared.saveSkillRepos(service.repos)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()

                            Button(role: .destructive) {
                                service.removeRepo(repo)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            Spacer()

            HStack {
                Spacer()
                Button("完成") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480, height: 400)
    }
}
