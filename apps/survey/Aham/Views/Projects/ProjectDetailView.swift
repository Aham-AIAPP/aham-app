import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// ProjectDetailView V3
// ────────────────────────────────────────────────────────────────────────
// V3 核心改动（对比 V2）：
//
//   1. Header 重做：
//      - 去掉 64pt 彩色 squircle → 改为 28pt 小图标 + 状态胶囊
//      - 标题行变单列，meta 信息走 Pill 组件
//      - 操作按钮右对齐到 header 同行（不单占一行 actionSection）
//
//   2. 引入 Segmented Tab 结构：
//      - 一页塞 AI 增强 + 客户信息 + 调研配置 + 进度 → 太满
//      - V3 分成 4 个 tab：「概览」「客户」「AI 增强」「进度」
//      - 每 tab 一个专注任务，认知负担下降
//
//   3. 所有视觉走 AHCard / AHSection / AHPill / AHPrimaryButtonStyle
//      - 彻底消除 GroupBox / .borderedProminent / .font(.title) 这类原始 API
//      - 所有 padding、radius 都走 AHSpacing / AHRadius token
//
//   4. Customer Info 卡片分离成 2 个 AHCard：
//      - 基本信息（editable inline，去掉"编辑"开关）
//      - 产品与工艺

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(AppStore.self) private var appStore
    @Environment(SettingsManager.self) private var settings
    @Environment(PluginLoader.self) private var pluginLoader
    @Query private var allAnswers: [Answer]
    @Query private var allMemoItems: [MemoItem]
    @Query private var allAdoptedFollowups: [AdoptedFollowup]


    @State private var showExportPanel = false

    // V3 新增：tab 选择
    @State private var activeTab: DetailTab = .overview

    enum DetailTab: Hashable {
        case overview, customer, progress
    }

    private var projectAnswers: [Answer] {
        allAnswers.filter { $0.projectId == project.id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().overlay(Color.ahDivider)
            ScrollView {
                tabContent
                    .padding(.horizontal, AHSpacing.xxl)
                    .padding(.vertical, AHSpacing.xl)
                    .frame(maxWidth: 960, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color.ahPaper)
        }
        .navigationTitle(project.displayName)
        .onAppear { syncProgress() }
        .toolbar { toolbarContent }
    }

    // MARK: - Header（V3 紧凑式）

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AHSpacing.m) {
                AHIconTile(symbol: project.status.icon,
                           size: AHIconBox.md,
                           tint: .ahInk60)

                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AHSpacing.s) {
                        Text(project.displayName).ahTitle()
                        AHStatus(text: project.status.label, color: statusColor)
                    }

                    HStack(spacing: AHSpacing.m) {
                        metaItem("person.fill", project.consultant.isEmpty ? "—" : project.consultant)
                        metaItem("calendar",
                                 project.surveyDate.formatted(.dateTime.year().month().day()))
                        metaItem(project.industryEnum.icon, project.industryEnum.label)
                        if !project.surveyScopes.isEmpty {
                            metaItem("scope",
                                     project.surveyScopes.map(\.label).joined(separator: "+"))
                        }
                        if !project.selectedDepartmentIds.isEmpty {
                            metaItem("building.2",
                                     "\(project.selectedDepartmentIds.count) 个部门")
                        }
                    }
                }

                Spacer()

                headerActions
            }
            .padding(.horizontal, AHSpacing.xxl)
            .padding(.vertical, AHSpacing.l)
        }
    }

    private func metaItem(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: AHSpacing.xxs) {
            Image(systemName: symbol).fontWeight(.medium)
            Text(text)
        }
        .foregroundStyle(.secondary)
        .ahCaption()
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: AHSpacing.s) {
            if project.status == .draft {
                Button {
                    project.status = .inProgress
                    project.updatedAt = .now
                    appStore.isSurveying = true
                } label: {
                    Label("开始调研", systemImage: "play.fill")
                }
                .buttonStyle(.ahPrimary)
            }

            if project.status == .inProgress {
                Button {
                    appStore.isSurveying = true
                } label: {
                    let pct = Int(project.progress * 100)
                    Label("继续调研 \(pct)%", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.ahPrimary)
            }

            if project.answeredQuestions > 0 {
                Button {
                    showExportPanel = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.ahSecondary)
            }
        }
        .sheet(isPresented: $showExportPanel) { exportSheet }
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack {
            AHSegmentedTab(
                selection: $activeTab,
                items: [
                    (.overview,      "概览",    "square.grid.2x2"),
                    (.customer,      "客户信息", "person.text.rectangle"),
                    (.progress,      "进度",    "chart.bar")
                ]
            )
            Spacer()
        }
        .padding(.horizontal, AHSpacing.xxl)
        .padding(.bottom, AHSpacing.m)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .overview:       overviewTab
        case .customer:       customerTab
        case .progress:       progressTab
        }
    }

    // MARK: - Tab: 概览

    @ViewBuilder
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xl) {
            // 三个 stat cards
            HStack(spacing: AHSpacing.m) {
                AHStatCard(label: "完成度",
                           value: "\(Int(project.progress * 100))%",
                           icon: "chart.bar.fill")
                AHStatCard(label: "已答 / 总题",
                           value: "\(project.answeredQuestions)/\(project.totalQuestions)",
                           icon: "checkmark.seal")
                AHStatCard(label: "调研部门",
                           value: "\(project.selectedDepartmentIds.count)",
                           icon: "building.2")
            }

            // 调研配置
            AHCard {
                AHSection("调研配置") {
                    VStack(alignment: .leading, spacing: AHSpacing.m) {
                        AHLabeledRow(label: "调研范围") {
                            if project.surveyScopes.isEmpty {
                                Text("—").foregroundStyle(.tertiary)
                            } else {
                                HStack(spacing: AHSpacing.xs) {
                                    ForEach(project.surveyScopes, id: \.self) { s in
                                        AHPill(text: s.label, style: .neutral)
                                    }
                                }
                            }
                        }
                        AHLabeledRow(label: "调研部门") {
                            let depts = pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)
                            if depts.isEmpty {
                                Text("—").foregroundStyle(.tertiary)
                            } else {
                                FlowLayout(spacing: AHSpacing.xs) {
                                    ForEach(depts) { d in
                                        AHPill(text: d.name, icon: d.sfSymbol, style: .neutral)
                                    }
                                }
                            }
                        }
                        AHLabeledRow(label: "调研目标") {
                            Text(project.surveyGoal.isEmpty ? "—" : project.surveyGoal)
                                .foregroundStyle(project.surveyGoal.isEmpty ? .tertiary : .primary)
                        }
                    }
                }
            }

            // 快速操作
            AHCard {
                AHSection("快速操作") {
                    HStack(spacing: AHSpacing.m) {
                        quickAction("开始调研", "play.circle") { appStore.isSurveying = true }
                        quickAction("导出报告", "square.and.arrow.up") { showExportPanel = true }
                    }
                }
            }
        }
    }

    private func quickAction(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AHSpacing.xs) {
                AHIconTile(symbol: icon, size: AHIconBox.lg, tint: .ahInk60)
                Text(label).ahCallout().fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AHSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(Color.ahPaper)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab: 客户信息

    @ViewBuilder
    private var customerTab: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xl) {
            // 基本信息
            AHCard {
                AHSection("基本信息") {
                    VStack(spacing: AHSpacing.m) {
                        AHLabeledRow(label: "客户名称") {
                            TextField("客户名称", text: $project.customerName)
                                .textFieldStyle(.roundedBorder)
                                .ahCallout()
                        }
                        AHLabeledRow(label: "组织形态") {
                            Picker("", selection: Binding(
                                get: { OrgScale(rawValue: project.companyScale) ?? .unset },
                                set: { project.companyScale = $0.rawValue }
                            )) {
                                ForEach(OrgScale.allCases, id: \.self) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                        }
                        AHLabeledRow(label: "员工规模") {
                            Picker("", selection: Binding(
                                get: { StaffScale(rawValue: project.headcount) ?? .unset },
                                set: { project.headcount = $0.rawValue }
                            )) {
                                ForEach(StaffScale.allCases, id: \.self) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                        }
                        AHLabeledRow(label: "年营收") {
                            Picker("", selection: Binding(
                                get: { RevenueScale(rawValue: project.revenue) ?? .unset },
                                set: { project.revenue = $0.rawValue }
                            )) {
                                ForEach(RevenueScale.allCases, id: \.self) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                        }
                        AHLabeledRow(label: "现有系统") {
                            TextField("如：用友 U8、SAP B1 等", text: $project.existingSystems)
                                .textFieldStyle(.roundedBorder)
                                .ahCallout()
                        }
                    }
                }
            }

            // 产品与工艺
            AHCard {
                AHSection("产品与工艺") {
                    EmptyView()
                }

                TextEditor(text: $project.productInfo)
                    .ahCallout()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(AHSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: AHRadius.sm)
                            .fill(Color.ahPaper)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.sm)
                            .strokeBorder(Color.ahBorder, lineWidth: 1)
                    )
                    .padding(.top, AHSpacing.s)

                if project.productInfo.isEmpty {
                    Text("填写客户的主要产品和生产工艺")
                        .ahCaption()
                        .padding(.top, AHSpacing.xs)
                }
            }
        }
    }

    // MARK: - Tab: 进度

    @ViewBuilder
    private var progressTab: some View {
        if project.selectedDepartmentIds.isEmpty {
            AHEmptyState(
                symbol: "building.2",
                title: "还未选择部门",
                message: "请先在创建项目时选择调研部门",
                actionLabel: nil,
                action: nil
            )
        } else {
            VStack(alignment: .leading, spacing: AHSpacing.xl) {
                AHCard {
                    VStack(alignment: .leading, spacing: AHSpacing.m) {
                        HStack {
                            Text("总进度").ahTitle3()
                            Spacer()
                            Text("\(Int(project.progress * 100))%")
                                .ahMono(28, weight: .semibold)
                                .foregroundStyle(project.progress >= 1 ? Color.ahSuccess : Color.ahAccent)
                        }
                        ProgressView(value: project.progress)
                            .tint(project.progress >= 1.0 ? Color.ahSuccess : Color.ahAccent)
                        Text("已完成 \(project.answeredQuestions) / \(project.totalQuestions) 题").ahMeta()
                    }
                }

                if project.selectedDepartmentIds.count > 1 {
                    AHCard {
                        AHSection("各部门详情") {
                            VStack(spacing: AHSpacing.s) {
                                let filteredByDept = pluginLoader.questionsForProject(project)
                                ForEach(pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)) { dept in
                                    let total = filteredByDept[dept.id]?.count ?? 0
                                    let done = projectAnswers.filter { $0.departmentId == dept.id && $0.hasContent }.count
                                    let pct = total > 0 ? Double(done) / Double(total) : 0

                                    Button {
                                        appStore.isSurveying = true
                                    } label: {
                                        HStack(spacing: AHSpacing.s) {
                                            AHIconTile(symbol: dept.sfSymbol, size: AHIconBox.sm, tint: .ahInk60)
                                            Text(dept.name)
                                                .ahCallout().fontWeight(.medium)
                                                .frame(width: 100, alignment: .leading)
                                            ProgressView(value: pct)
                                                .tint(pct >= 1 ? Color.ahSuccess : Color.ahAccent)
                                            Text("\(done)/\(total)")
                                                .ahMono(12)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 48, alignment: .trailing)
                                        }
                                        .padding(.vertical, AHSpacing.xs)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Button {
                        project.status = status
                        project.updatedAt = .now
                    } label: {
                        Label(status.label, systemImage: status.icon)
                    }
                    .disabled(project.status == status)
                }
            } label: {
                Label(project.status.label, systemImage: project.status.icon)
            }
        }
    }

    // MARK: - Export Sheet

    @ViewBuilder
    private var exportSheet: some View {
        ExportPanelView(
            panelData: buildExportPanelData(),
            isPresented: $showExportPanel,
            onGenerate: { config in
                let snapshot = self.buildExportSnapshot()
                let baseName = "\(snapshot.displayName) 调研报告"
                switch config.format {
                case .markdown:
                    guard let data = MarkdownExporter.exportProject(snapshot: snapshot, config: config).data(using: .utf8) else { return nil }
                    return (data, "\(baseName).md")
                case .word:
                    guard let data = await MarkdownExporter.exportProjectAsDOCX(snapshot: snapshot, config: config) else { return nil }
                    return (data, "\(baseName).docx")
                }
            },
            onExport: { data, name in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.saveExportFile(data: data, fileName: name)
                }
            }
        )
    }

    // MARK: - Business Logic (保留 V2 原样)

    private func buildExportPanelData() -> ExportPanelData {
        var deptNames: [String: String] = [:]
        var deptCounts: [String: Int] = [:]
        for deptId in project.selectedDepartmentIds {
            let dept = pluginLoader.departments.first { $0.id == deptId }
            deptNames[deptId] = dept?.name ?? deptId
            deptCounts[deptId] = projectAnswers.filter { $0.departmentId == deptId && $0.hasContent }.count
        }
        return ExportPanelData(
            projectName: project.displayName,
            selectedDeptIds: project.selectedDepartmentIds,
            deptNames: deptNames,
            deptAnsweredCounts: deptCounts
        )
    }

    private func buildExportSnapshot() -> ExportSnapshot {
        let answers = projectAnswers
        var deptNames: [String: String] = [:]
        var deptSections: [String: [ExportSnapshot.ExportSectionData]] = [:]
        for deptId in project.selectedDepartmentIds {
            let dept = pluginLoader.departments.first { $0.id == deptId }
            deptNames[deptId] = dept?.name ?? deptId
            let deptAnswers = answers.filter { $0.departmentId == deptId }
            let deptFollowups = allAdoptedFollowups
                .filter { $0.projectId == project.id && $0.departmentId == deptId }
                .sorted { $0.createdAt < $1.createdAt }
            let rawSections = pluginLoader.questionsBySection(for: deptId)

            func item(for q: QuestionTemplate, isFollowup: Bool) -> ExportSnapshot.ExportItem {
                let ans = deptAnswers.first { $0.questionId == q.id }
                return ExportSnapshot.ExportItem(
                    topic: q.topic,
                    question: q.question,
                    isFollowup: isFollowup,
                    selectedOptions: ans?.selectedOptions ?? [],
                    textValue: ans?.textValue ?? "",
                    noteText: ans?.noteText ?? "",
                    polishedText: ans?.polishedText ?? "",
                    voiceTranscript: ans?.voiceTranscript ?? "",
                    hasContent: ans?.hasContent ?? false
                )
            }

            let sections: [ExportSnapshot.ExportSectionData] = rawSections.map { (section, questions) in
                var items: [ExportSnapshot.ExportItem] = []
                for q in questions {
                    items.append(item(for: q, isFollowup: false))
                    // 现场采纳的 AI 追问紧跟其父题目输出
                    for fu in deptFollowups where fu.parentQuestionId == q.id {
                        items.append(item(for: fu.asTemplate(section: section), isFollowup: true))
                    }
                }
                return ExportSnapshot.ExportSectionData(label: section.label, items: items)
            }
            deptSections[deptId] = sections
        }
        return ExportSnapshot(
            displayName: project.displayName, customerName: project.customerName,
            consultant: project.consultant, surveyDate: project.surveyDate,
            statusLabel: project.status.label, industryLabel: project.industryEnum.label,
            companyScale: project.companyScale, headcount: project.headcount,
            revenue: project.revenue, existingSystems: project.existingSystems,
            surveyGoal: project.surveyGoal, totalQuestions: project.totalQuestions,
            answeredQuestions: project.answeredQuestions, progress: project.progress,
            selectedDepartmentIds: project.selectedDepartmentIds,
            departmentNames: deptNames, departmentSections: deptSections,
            memoItems: memoGroupsForExport()
        )
    }

    /// 现场备忘按四类固定顺序导出
    private func memoGroupsForExport() -> [(category: String, texts: [String])] {
        MemoCategory.allCases.map { category in
            let texts = allMemoItems
                .filter { $0.projectId == project.id && $0.category == category.rawValue }
                .sorted { $0.createdAt < $1.createdAt }
                .map(\.text)
            return (category: category.label, texts: texts)
        }
    }

    private func saveExportFile(data: Data, fileName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        if fileName.hasSuffix(".md") {
            panel.allowedContentTypes = [.plainText]
            panel.message = "选择 Markdown 导出位置"
        } else {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
            panel.message = "选择 Word 文档导出位置"
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func syncProgress() {
        let selectedDepts = Set(project.selectedDepartmentIds)
        let total = pluginLoader.questionsForProject(project).values.reduce(0) { $0 + $1.count }
        let answered = projectAnswers.filter { selectedDepts.contains($0.departmentId) && $0.hasContent }.count
        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        switch project.status {
        case .draft:      .ahInk40
        case .inProgress: Color.ahAccent
        case .completed:  Color.ahSuccess
        case .archived:   .ahInk20
        }
    }
}
