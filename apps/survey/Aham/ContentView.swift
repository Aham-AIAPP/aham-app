import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(PluginLoader.self) private var pluginLoader
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: 项目列表（宽度对齐 aham-ui sidebar-width 264）
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 264, max: 320)
        } detail: {
            // Detail: 调研中 → SurveyView；否则项目详情 / 欢迎页
            if appStore.isSurveying, let project = currentProject {
                SurveyView(project: project)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                appStore.isSurveying = false
                            } label: {
                                Label("返回项目", systemImage: "chevron.left")
                            }
                            .help("返回项目详情 (⌘⎋)")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            SettingsLink {
                                Label("设置", systemImage: "gearshape")
                            }
                            .help("设置 (⌘,)")
                        }
                    }
            } else {
                surveyDetail
            }
        }
        .alert("无法保存修改", isPresented: Binding(
            get: { appStore.writeError != nil },
            set: { if !$0 { appStore.writeError = nil } }
        )) {
            Button("知道了", role: .cancel) { appStore.writeError = nil }
        } message: { Text(appStore.writeError ?? "") }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: appStore.isSurveying) { _, surveying in
            if surveying, currentProject?.status == .archived {
                appStore.isSurveying = false
                columnVisibility = .all
            } else {
                if surveying, let project = currentProject, project.status == .draft {
                    guard appStore.performWrite({
                        try ProjectService(context: modelContext, pluginLoader: pluginLoader)
                            .update(project, fields: ["status": ProjectStatus.inProgress.rawValue])
                    }) else { appStore.isSurveying = false; return }
                }
                columnVisibility = surveying ? .detailOnly : .all
            }
        }
        .onChange(of: appStore.selectedProjectId) { oldValue, newValue in
            if oldValue != newValue {
                appStore.isSurveying = false
            }
        }
    }

    // MARK: - Computed

    private var currentProject: Project? {
        guard let id = appStore.selectedProjectId else { return nil }
        return allProjects.first(where: { $0.id == id })
    }

    // MARK: - Survey Detail

    @ViewBuilder
    private var surveyDetail: some View {
        if let project = currentProject {
            ProjectDetailView(project: project)
        } else {
            MCPConsoleView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .environment(MCPSettings())
        .modelContainer(for: [Project.self, Answer.self, MemoItem.self, AdoptedFollowup.self, MCPChangeSet.self], inMemory: true)
}
