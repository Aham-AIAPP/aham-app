import SwiftUI
import SwiftData

@main
struct AhamApp: App {
    @State private var appStore        = AppStore()
    @State private var settingsManager = SettingsManager()
    @State private var pluginLoader: PluginLoader
    @State private var mcpSettings: MCPSettings
    @State private var mcpServer: MCPServer
    private let container: ModelContainer

    init() {
        // 显式建容器：MCP 服务要在视图之外访问 SwiftData
        let container = try! ModelContainer(
            for: Project.self, Answer.self, MemoItem.self, AdoptedFollowup.self
        )
        let loader = PluginLoader()
        let settings = MCPSettings()

        self.container = container
        _pluginLoader = State(initialValue: loader)
        _mcpSettings = State(initialValue: settings)
        _mcpServer = State(initialValue: MCPServer(
            settings: settings, container: container, pluginLoader: loader
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appStore)
                .environment(pluginLoader)
                .environment(settingsManager)
                .environment(mcpSettings)
                .environment(mcpServer)
                .onAppear { mcpServer.start() }
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            // 项目由 MCP 创建，App 内不再提供新建入口
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .newItem) {
                Button("开始/继续调研") {
                    appStore.isSurveying = true
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appStore.selectedProjectId == nil)

                Button("返回项目") {
                    appStore.isSurveying = false
                }
                .keyboardShortcut(.escape, modifiers: .command)
                .disabled(!appStore.isSurveying)
            }
        }

        Settings {
            SettingsView()
                .environment(settingsManager)
                .environment(pluginLoader)
        }
        .defaultPosition(.center)
    }
}
