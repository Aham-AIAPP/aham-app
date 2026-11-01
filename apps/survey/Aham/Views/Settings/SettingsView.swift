import SwiftUI

/// 全局设置页面 — TabView 分页布局
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") {
                GeneralSettingsTab()
            }
        }
        .frame(width: 560, height: 320)
    }
}

// MARK: - 通用 Tab (AI 大模型)

private struct GeneralSettingsTab: View {
    @Environment(SettingsManager.self) private var settings
    @State private var testingConnection = false
    @State private var connectionResult: Bool?
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("AI 大模型服务") {
                TextField("API 端点", text: $s.llmConfig.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .disabled(testingConnection)

                SecureField("API Key", text: $s.llmConfig.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(testingConnection)

                TextField("模型名称", text: $s.llmConfig.model)
                    .textFieldStyle(.roundedBorder)
                    .disabled(testingConnection)

                HStack {
                    Button {
                        testConnection()
                    } label: {
                        Text(testingConnection ? "正在测试…" : "测试连接")
                            .frame(width: AHLayout.editorHeight)
                    }
                    .buttonStyle(.ahSecondary)
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
        .onDisappear { connectionTask?.cancel(); testingConnection = false }
        .onChange(of: settings.llmConfig) { _, _ in connectionResult = nil }
    }

    private func testConnection() {
        guard !testingConnection else { return }
        testingConnection = true; connectionResult = nil
        let submitted = settings.llmConfig
        connectionTask = Task {
            let result = await settings.testLLMConnection()
            guard !Task.isCancelled, settings.llmConfig == submitted else { return }
            connectionResult = result; testingConnection = false
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsManager())
}
