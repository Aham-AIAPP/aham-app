import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = appStore

        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1: Module switcher
            ModuleSidebarView()
                .navigationSplitViewColumnWidth(min: 76, ideal: 76, max: 76)
        } detail: {
            // Column 2+: Module content
            switch appStore.activeModule {

            case .home:
                HomeView()

            case .survey:
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
                        }
                } else {
                    HSplitView {
                        ProjectListView()
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                        surveyDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

            case .sales:
                SalesDashboardView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appStore.isSurveying) { _, surveying in
            columnVisibility = surveying ? .detailOnly : .all
        }
        .onChange(of: appStore.selectedProjectId) { oldValue, newValue in
            if oldValue != newValue {
                appStore.isSurveying = false
                if newValue != nil { appStore.activeModule = .survey }
            }
        }
        .sheet(isPresented: $store.showNewProject) {
            NewProjectView()
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
            WelcomeView()
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            AHIconTile(symbol: "sparkles", size: AHIconBox.hero)
                .padding(.bottom, AHSpacing.xxxl)

            Text("企业智能调研平台")
                .ahTitle()

            Text("AI 重构业务")
                .ahTitle3()
                .foregroundStyle(.secondary)
                .padding(.top, AHSpacing.xs)

            AHDivider()
                .frame(maxWidth: 240)
                .padding(.vertical, AHSpacing.xl)

            VStack(alignment: .leading, spacing: AHSpacing.s) {
                featureRow("doc.text.magnifyingglass", "结构化调研，覆盖 14 大职能部门")
                featureRow("brain.head.profile",       "AI 智能分析，自动生成洞察报告")
                featureRow("mic.circle",               "语音转写，对话内容自动填入答案")
            }

            Button {
                appStore.showNewProject = true
            } label: {
                Label("新建调研项目", systemImage: "plus")
            }
            .buttonStyle(.ahPrimaryLarge)
            .padding(.top, AHSpacing.xxxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: AHSpacing.s) {
            Image(systemName: icon)
                .ahCallout()
                .foregroundStyle(Color.ahAccent)
                .frame(width: AHIconBox.xs)
            Text(text)
                .ahCallout()
                .foregroundStyle(Color.ahInk60)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .environment(SpeechRecognitionService())
        .modelContainer(for: [Project.self, Answer.self], inMemory: true)
}
