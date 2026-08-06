import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(PluginLoader.self) private var pluginLoader
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var projectToDelete: Project?
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    @State private var filterStatus = "all"

    var body: some View {
        @Bindable var store = appStore

        VStack(spacing: 0) {
            // 搜索 + 设置
            HStack(spacing: AHSpacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("搜索项目", text: $searchText)
                    .textFieldStyle(.plain)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .ahCallout()
                        .foregroundStyle(Color.ahInk60)
                }
                .buttonStyle(.plain)
                .help("设置 (⌘,)")
            }
            .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.s)
            .ahGlassBar()
            Divider()

            // 状态筛选 chip（与会议类型筛选逻辑一致）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AHSpacing.xs) {
                    statusChip("全部",  id: "all")
                    statusChip("进行中", id: "inProgress")
                    statusChip("草稿",  id: "draft")
                    statusChip("已完成", id: "completed")
                    statusChip("已归档", id: "archived")
                }
                .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.xs)
            }
            Divider()

            List(selection: $store.selectedProjectId) {
                ForEach(filteredByStatus) { project in
                    ProjectRowView(project: project)
                        .tag(project.id)
                        .contextMenu { projectContextMenu(project) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if allProjects.isEmpty {
                    ContentUnavailableView {
                        Label("暂无调研项目", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("项目由 Claude / Codex 通过 MCP 创建，右侧有接入说明")
                    }
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
            }
        } message: {
            Text("确定要删除「\(projectToDelete?.displayName ?? "")」吗？此操作不可撤销。")
        }
    }

    // MARK: - Filtered Projects

    private var filteredProjects: [Project] {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return allProjects }
        return allProjects.filter {
            $0.customerName.localizedCaseInsensitiveContains(search) ||
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.consultant.localizedCaseInsensitiveContains(search)
        }
    }

    private var filteredByStatus: [Project] {
        switch filterStatus {
        case "inProgress": return filteredProjects.filter { $0.status == .inProgress }
        case "draft":      return filteredProjects.filter { $0.status == .draft }
        case "completed":  return filteredProjects.filter { $0.status == .completed }
        case "archived":   return filteredProjects.filter { $0.status == .archived }
        default:           return filteredProjects
        }
    }

    // MARK: - Status Chip

    private func statusChip(_ name: String, id: String) -> some View {
        Button(name) { filterStatus = id }
            .buttonStyle(PillButtonStyle(selected: filterStatus == id))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        if project.status == .draft {
            Button {
                project.status = .inProgress
                project.updatedAt = .now
            } label: {
                Label("开始调研", systemImage: "play")
            }
        }

        if project.status == .inProgress {
            Button {
                project.status = .completed
                project.updatedAt = .now
            } label: {
                Label("标记完成", systemImage: "checkmark.circle")
            }
        }

        if project.status != .archived {
            Button {
                project.status = .archived
                project.updatedAt = .now
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }

        if project.status == .archived {
            Button {
                project.status = .completed
                project.updatedAt = .now
            } label: {
                Label("取消归档", systemImage: "arrow.uturn.backward")
            }
        }

        Divider()

        Button(role: .destructive) {
            projectToDelete = project
            showDeleteConfirm = true
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteProject(_ project: Project) {
        if appStore.selectedProjectId == project.id {
            appStore.selectedProjectId = nil
            appStore.isSurveying = false
        }
        try? ProjectService(context: modelContext, pluginLoader: pluginLoader).delete(project)
    }
}
