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

#Preview {
    SettingsView()
        .environment(SettingsManager())
}
