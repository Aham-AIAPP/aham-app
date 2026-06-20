import SwiftUI

/// 全局设置页面 — TabView 分页布局
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") {
                GeneralSettingsTab()
            }

            Tab("知识库", systemImage: "brain") {
                KnowledgeSettingsTab()
            }

            Tab("导出", systemImage: "square.and.arrow.up") {
                ExportSettingsTab()
            }

            Tab("备份", systemImage: "externaldrive") {
                BackupSettingsTab()
            }
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - 通用 Tab (AI 大模型)

private struct GeneralSettingsTab: View {
    @Environment(SettingsManager.self) private var settings
    @State private var testingConnection = false
    @State private var connectionResult: Bool?

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("AI 大模型服务") {
                TextField("API 端点", text: $s.llmConfig.endpoint)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $s.llmConfig.apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("模型名称", text: $s.llmConfig.model)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        testConnection()
                    } label: {
                        if testingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .disabled(testingConnection || !settings.isLLMConfigured)

                    if let result = connectionResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? Color.ahSuccess : Color.ahDanger)
                        Text(result ? "连接成功" : "连接失败")
                            .ahCaption()
                            .foregroundStyle(result ? Color.ahSuccess : Color.ahDanger)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { connectionResult = nil; testingConnection = false }
    }

    private func testConnection() {
        testingConnection = true; connectionResult = nil
        Task {
            let result = await settings.testLLMConnection()
            connectionResult = result; testingConnection = false
        }
    }
}

// MARK: - 知识库 Tab

private struct KnowledgeSettingsTab: View {
    var body: some View {
        Form {
            Section { KnowledgeTrainingView() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 导出 Tab

private struct ExportSettingsTab: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("Obsidian 集成") {
                Toggle("启用 Obsidian", isOn: $s.obsidianConfig.enabled)

                if settings.obsidianConfig.enabled {
                    HStack {
                        TextField("Vault 路径", text: $s.obsidianConfig.vaultPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择...") { selectVaultPath() }
                    }
                    TextField("导出目录", text: $s.obsidianConfig.exportFolder)
                        .textFieldStyle(.roundedBorder)
                    Toggle("添加 YAML Frontmatter", isOn: $s.obsidianConfig.addFrontmatter)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectVaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 Obsidian Vault 目录"
        panel.begin { [self] response in
            guard response == .OK, let url = panel.url else { return }
            settings.obsidianConfig.vaultPath = url.path
            settings.obsidianConfig.vaultBookmark = ObsidianConfig.createBookmark(from: url)
        }
    }
}

// MARK: - 备份 Tab

private struct BackupSettingsTab: View {
    @State private var manager = BackupManager()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    Text("将所有调研项目、回答、知识库和配置打包为 ZIP 文件，可在重装系统或换电脑后恢复。")
                        .ahCaption()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AHSpacing.m) {
                        Button {
                            manager.export()
                        } label: {
                            if manager.isExporting {
                                ProgressView().controlSize(.small)
                                Text("正在导出...")
                            } else {
                                Label("导出备份...", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(manager.isExporting)

                        if let msg = manager.exportMessage {
                            Text(msg)
                                .ahCaption()
                                .foregroundStyle(msg.hasPrefix("✅") ? Color.ahSuccess : Color.ahDanger)
                        }
                    }
                }
            } header: {
                Label("导出备份", systemImage: "square.and.arrow.down")
            }

            Section {
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    Text("选择之前导出的备份文件，导入后 App 将自动重启，重启后数据恢复完成。")
                        .ahCaption()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AHSpacing.m) {
                        Button {
                            manager.selectAndImport()
                        } label: {
                            if manager.isImporting {
                                ProgressView().controlSize(.small)
                                Text("正在导入...")
                            } else {
                                Label("选择备份文件...", systemImage: "arrow.up.circle")
                            }
                        }
                        .disabled(manager.isImporting)

                        if let msg = manager.importMessage {
                            Text(msg)
                                .ahCaption()
                                .foregroundStyle(msg.hasPrefix("✅") ? Color.ahSuccess : Color.ahDanger)
                        }
                    }
                }
            } header: {
                Label("导入备份", systemImage: "square.and.arrow.up")
            } footer: {
                Text("⚠️ 导入会覆盖当前全部数据，请确认备份文件来源正确。")
                    .ahCaption()
                    .foregroundStyle(Color.ahWarning)
            }
        }
        .formStyle(.grouped)
        .alert("确认导入备份？", isPresented: $manager.showImportConfirm) {
            Button("取消", role: .cancel) { manager.cancelImport() }
            Button("导入并重启", role: .destructive) { manager.confirmImport() }
        } message: {
            Text("导入后将覆盖当前所有数据（项目、回答、知识库、配置），App 会自动重启。此操作不可撤销。")
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsManager())
}
