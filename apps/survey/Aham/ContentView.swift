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
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: appStore.isSurveying) { _, surveying in
            columnVisibility = surveying ? .detailOnly : .all
        }
        .onChange(of: appStore.selectedProjectId) { oldValue, newValue in
            if oldValue != newValue {
                appStore.isSurveying = false
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

            AHIconTile(symbol: "doc.text.magnifyingglass", size: AHIconBox.hero)
                .padding(.bottom, AHSpacing.xxxl)

            Text("Aham Survey")
                .ahTitle()

            Text("把现场调研变成结构化洞察")
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
                .foregroundStyle(Color.ahInk60)
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
