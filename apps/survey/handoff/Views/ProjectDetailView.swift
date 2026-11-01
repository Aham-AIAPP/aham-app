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
//   4. Customer Info 卡片分离成 3 个 AHCard：
//      - 基本信息（editable inline，去掉"编辑"开关）
//      - 产品与工艺
//      - 文档导入（独立卡片，不再嵌在客户信息内）
//
//   5. AI 增强全流程独立 tab：
//      - 状态、进度、结果一屏呈现
//      - 补充问题的 picker 从弹层改为 inline sheet
//
// ⚠️ 逻辑层（importDocument / exportToObsidian / AI enhancer 调用等）
//    保持不变 —— 只重写 UI，所有函数签名原样。

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(AppStore.self) private var appStore
    @Environment(SettingsManager.self) private var settings
    @Environment(PluginLoader.self) private var pluginLoader
    @Query private var allAnswers: [Answer]

    // 文档导入相关 state —— 与 V2 完全一致
    @State private var docAnalyzer = ProjectDocumentAnalyzer()
    @State private var analysisResult: ProjectDocumentAnalyzer.DocumentAnalysisResult?
    @State private var pendingDocQuestions: [AIGeneratedQuestion] = []
    @State private var pendingQuestionSelection: [Int: Bool] = [:]
    @State private var docImportPhase: DocImportPhase = .idle

    @State private var showExportPanel = false
    @State private var isExportingToObsidian = false
    @State private var obsidianExportMessage: String?
    @State private var aiEnhancer: AIProjectEnhancer?
    @State private var isSearchingProductInfo = false

    // V3 新增：tab 选择
    @State private var activeTab: DetailTab = .overview

    enum DetailTab: Hashable {
        case overview, customer, aiEnhancement, progress
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
                           tint: statusColor)

                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AHSpacing.s) {
                        Text(project.displayName).ahTitle()
                        AHPill(text: project.status.label,
                               icon: project.status.icon,
                               style: statusPillStyle)
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
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
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
                    (.aiEnhancement, "AI 增强", "wand.and.stars"),
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
        case .aiEnhancement:  aiEnhancementTab
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
                                        AHPill(text: s.label, style: .info)
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
                        quickAction("开始调研", "play.circle", .accent) { appStore.isSurveying = true }
                        quickAction("生成 AI 增强", "wand.and.stars", .accent) { runAIEnhancement() }
                        quickAction("导入文档", "doc.badge.plus", .neutral) { importDocument() }
                        quickAction("导出报告", "square.and.arrow.up", .neutral) { showExportPanel = true }
                    }
                }
            }
        }
    }

    private func quickAction(_ label: String, _ icon: String, _ style: AHPill.Style, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AHSpacing.xs) {
                AHIconTile(symbol: icon, size: AHIconBox.lg, tint: style.fg)
                Text(label).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AHSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(Color.ahPaperAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .strokeBorder(Color.ahBorder, lineWidth: 1)
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
                                .font(.callout)
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
                                .font(.callout)
                        }
                    }
                }
            }

            // 产品与工艺
            AHCard {
                AHSection("产品与工艺") {
                    HStack(alignment: .top, spacing: AHSpacing.s) {
                        Button {
                            searchProductInfo()
                        } label: {
                            if isSearchingProductInfo {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("搜索中")
                                }
                            } else {
                                Label("AI 搜索", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.ahSecondary)
                        .disabled(!settings.isLLMConfigured || project.customerName.isEmpty || isSearchingProductInfo)
                    }
                } trailing: {
                    EmptyView()
                }

                TextEditor(text: $project.productInfo)
                    .font(.callout)
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
                    Text("填写或 AI 搜索客户的主要产品和生产工艺")
                        .ahCaption()
                        .padding(.top, AHSpacing.xs)
                }
            }

            // 文档导入
            AHCard {
                documentImportInnerContent
            }
        }
    }

    @ViewBuilder
    private var documentImportInnerContent: some View {
        VStack(alignment: .leading, spacing: AHSpacing.m) {
            AHSection("文档导入") {
                EmptyView()
            } trailing: {
                if docImportPhase == .idle || docImportPhase == .applied {
                    Button {
                        importDocument()
                    } label: {
                        Label("选择文档", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.ahSecondary)
                }
            }

            if let docs = project.aiEnhancement?.importedDocsSummary, !docs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已导入").ahCaption()
                    ForEach(docs, id: \.self) { doc in
                        HStack(spacing: AHSpacing.xs) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(doc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let isBusy = docAnalyzer.isAnalyzing || docAnalyzer.isRebuildingQuestions
            if isBusy {
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    HStack(spacing: AHSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text(docAnalyzer.progressMessage.isEmpty
                             ? (docAnalyzer.isAnalyzing ? "正在分析..." : "生成补充问题...")
                             : docAnalyzer.progressMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: docAnalyzer.progress, total: 1.0)
                        .progressViewStyle(.linear)
                }
                .padding(AHSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: AHRadius.sm)
                        .fill(Color.ahAccentBG)
                )
            }

            if case .analyzed(let result) = docImportPhase {
                docAnalysisResultInline(result)
            }
            if case .pendingConfirm = docImportPhase {
                docQuestionPreviewInline()
            }

            if docImportPhase == .idle || docImportPhase == .applied {
                Text("支持 Word / PPT / Excel / PDF / Markdown 等，可多选 5 个")
                    .ahCaption()
            }

            if docImportPhase == .applied {
                AHPill(text: "已应用到本项目",
                       icon: "checkmark.circle.fill",
                       style: .success)
            }

            if let error = docAnalyzer.lastError {
                HStack(spacing: AHSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(Color.ahDanger)
                    Spacer()
                    Button {
                        docAnalyzer.lastError = nil
                        docImportPhase = .idle
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func docAnalysisResultInline(_ result: ProjectDocumentAnalyzer.DocumentAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: AHSpacing.s) {
            if !result.fileNames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(result.fileNames.joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            let hasContent = !result.keyFindings.isEmpty || !result.knownIssues.isEmpty || !result.knownNeeds.isEmpty
            if hasContent {
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    if !result.keyFindings.isEmpty {
                        analysisGroup("关键发现", icon: "lightbulb", items: Array(result.keyFindings.prefix(3)))
                    }
                    if !result.knownIssues.isEmpty {
                        analysisGroup("已知问题", icon: "exclamationmark.triangle", items: Array(result.knownIssues.prefix(2)))
                    }
                    if !result.knownNeeds.isEmpty {
                        analysisGroup("已知需求", icon: "star", items: Array(result.knownNeeds.prefix(2)))
                    }
                }
                .padding(AHSpacing.m)
                .background(RoundedRectangle(cornerRadius: AHRadius.sm).fill(Color.ahAccentBG))
            } else {
                Text("未提取到结构化信息，仍可直接生成补充问题")
                    .ahCaption()
            }

            HStack(spacing: AHSpacing.s) {
                Button("应用客户信息") {
                    docAnalyzer.applyToProject(result, project: project)
                }
                .buttonStyle(.ahSecondary)

                if settings.isLLMConfigured {
                    Button {
                        generateDocQuestions(docContent: result.rawDocContent)
                    } label: {
                        Label("生成补充问题", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.ahPrimary)
                }

                Button("取消") {
                    docImportPhase = .idle
                }
                .buttonStyle(.ahGhost)
            }
        }
    }

    private func analysisGroup(_ title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(title).ahSectionLabel()
            }
            ForEach(items, id: \.self) { item in
                Text("• \(item)").font(.caption).foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func docQuestionPreviewInline() -> some View {
        VStack(alignment: .leading, spacing: AHSpacing.s) {
            HStack(spacing: AHSpacing.xs) {
                Image(systemName: "wand.and.stars").foregroundStyle(Color.ahAccent)
                Text("AI 生成了 \(pendingDocQuestions.count) 道补充问题")
                    .font(.callout.weight(.medium))
                Spacer()
                Button(pendingQuestionSelection.values.allSatisfy({ $0 }) ? "全不选" : "全选") {
                    let allSelected = pendingQuestionSelection.values.allSatisfy({ $0 })
                    for i in pendingDocQuestions.indices {
                        pendingQuestionSelection[i] = !allSelected
                    }
                }
                .buttonStyle(.ahGhost)
            }

            let grouped = Dictionary(grouping: pendingDocQuestions.indices) {
                pendingDocQuestions[$0].departmentId
            }
            ForEach(grouped.keys.sorted(), id: \.self) { deptId in
                let dept = pluginLoader.departments.first { $0.id == deptId }
                let indices = grouped[deptId] ?? []

                VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                    HStack(spacing: 4) {
                        Image(systemName: dept?.sfSymbol ?? "folder")
                            .font(.caption2)
                            .foregroundStyle(Color.ahAccent)
                        Text(dept?.name ?? deptId)
                            .font(.caption.weight(.semibold))
                        Text("\(indices.count) 题").ahCaption()
                    }

                    ForEach(indices, id: \.self) { idx in
                        let q = pendingDocQuestions[idx]
                        let isSelected = pendingQuestionSelection[idx] ?? true
                        Button {
                            pendingQuestionSelection[idx] = !isSelected
                        } label: {
                            HStack(alignment: .top, spacing: AHSpacing.xs) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isSelected ? Color.ahAccent : .secondary)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.text).font(.caption).foregroundStyle(isSelected ? .primary : .secondary).lineLimit(2)
                                    if !q.reason.isEmpty {
                                        Text(q.reason).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                            }
                            .padding(AHSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: AHRadius.xs)
                                    .fill(isSelected ? Color.ahAccentBG : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: AHSpacing.s) {
                let selectedCount = pendingQuestionSelection.values.filter({ $0 }).count
                Button("应用选中的 \(selectedCount) 道题") {
                    applySelectedDocQuestions()
                }
                .buttonStyle(.ahPrimary)
                .disabled(selectedCount == 0)

                Button("放弃") {
                    pendingDocQuestions = []
                    pendingQuestionSelection = [:]
                    docImportPhase = .idle
                }
                .buttonStyle(.ahGhost)
            }
        }
        .padding(AHSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AHRadius.sm)
                .fill(Color.ahAccentBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AHRadius.sm)
                .strokeBorder(Color.ahAccentBorder, lineWidth: 1)
        )
    }

    // MARK: - Tab: AI 增强

    @ViewBuilder
    private var aiEnhancementTab: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xl) {
            if let enhancer = aiEnhancer, enhancer.isEnhancing {
                AHCard {
                    VStack(alignment: .leading, spacing: AHSpacing.m) {
                        HStack {
                            Text("正在生成 AI 增强...").ahTitle3()
                            Spacer()
                            Text("\(Int(enhancer.progressFraction * 100))%")
                                .ahMono(13, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                        Text(enhancer.progress).ahMeta()
                        ProgressView(value: enhancer.progressFraction)
                            .tint(Color.ahAccent)
                    }
                }
            } else if let enhancement = project.aiEnhancement {
                // 已生成
                AHCard {
                    VStack(alignment: .leading, spacing: AHSpacing.m) {
                        HStack {
                            AHPill(text: "AI 增强已完成", icon: "checkmark.circle.fill", style: .success)
                            Spacer()
                            Text(enhancement.generatedAt, format: .dateTime.month().day().hour().minute())
                                .ahCaption()
                        }

                        if !enhancement.industryContext.isEmpty {
                            Text(enhancement.industryContext)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }

                        // 四个统计
                        HStack(spacing: AHSpacing.m) {
                            enhancementStat("动态选项", enhancement.optionSets.count, "list.bullet")
                            enhancementStat("优先级调整", enhancement.priorityAdjustments.count, "arrow.up.arrow.down")
                            enhancementStat("跳过建议", enhancement.skipSuggestions.count, "forward.end")
                            enhancementStat("补充问题", enhancement.additionalQuestions.count, "plus.bubble")
                        }

                        HStack {
                            Button("重新生成") { runAIEnhancement() }
                                .buttonStyle(.ahSecondary)
                            Spacer()
                        }
                    }
                }
            } else {
                // 未生成
                AHCard {
                    VStack(alignment: .leading, spacing: AHSpacing.m) {
                        HStack(spacing: AHSpacing.m) {
                            AHIconTile(symbol: "wand.and.stars", size: AHIconBox.lg, tint: Color.ahAccent)
                            VStack(alignment: .leading, spacing: AHSpacing.xs) {
                                Text("AI 智能增强").ahTitle3()
                                Text("根据客户属性和行业特征，自动生成动态选项、调整优先级、筛除冗余问题。")
                                    .ahMeta()
                            }
                            Spacer()
                        }
                        HStack {
                            Spacer()
                            Button("开始生成") { runAIEnhancement() }
                                .buttonStyle(.ahPrimary)
                                .disabled(!settings.isLLMConfigured)
                        }

                        if let enhancer = aiEnhancer, let error = enhancer.lastError {
                            AHPill(text: error, icon: "exclamationmark.triangle", style: .danger)
                        }
                        if !settings.isLLMConfigured {
                            AHPill(text: "请先在设置中配置 LLM API Key", icon: "gearshape", style: .warning)
                        }
                    }
                }
            }
        }
    }

    private func enhancementStat(_ label: String, _ count: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: AHSpacing.xxs) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
                Text(label).ahCaption()
            }
            Text("\(count)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(count > 0 ? Color.ahAccent : Color.ahInk40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AHSpacing.m)
        .background(RoundedRectangle(cornerRadius: AHRadius.sm).fill(Color.ahPaper))
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
                                            AHIconTile(symbol: dept.sfSymbol, size: AHIconBox.sm, tint: Color.ahAccent)
                                            Text(dept.name)
                                                .font(.callout.weight(.medium))
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

        if !settings.obsidianConfig.vaultPath.isEmpty && project.answeredQuestions > 0 {
            ToolbarItem {
                Button {
                    exportToObsidian()
                } label: {
                    if isExportingToObsidian {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("写入中")
                        }
                    } else {
                        Label("Obsidian", systemImage: "note.text")
                    }
                }
                .disabled(isExportingToObsidian)
                .help(obsidianExportMessage ?? "导出到 Obsidian Vault")
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

    private func searchProductInfo() {
        guard let provider = settings.llmProvider, !project.customerName.isEmpty else { return }
        isSearchingProductInfo = true
        Task {
            let messages = [
                LLMMessage(role: .system, content: "根据公司名称，简要描述该公司的主要产品、生产工艺和业务范围。用中文，3-5句话。如果不确定，注明是推测。"),
                LLMMessage(role: .user, content: "公司名称：\(project.customerName)")
            ]
            do {
                let result = try await provider.chat(messages: messages, options: .default)
                project.productInfo = result
            } catch {
                project.productInfo = "搜索失败：\(error.localizedDescription)"
            }
            isSearchingProductInfo = false
        }
    }

    private func runAIEnhancement() {
        let enhancer = AIProjectEnhancer(settings: settings)
        self.aiEnhancer = enhancer
        let questionsByDept = pluginLoader.questionsForProject(project)
        Task {
            if let result = await enhancer.enhance(project: project, questionsByDept: questionsByDept) {
                project.aiEnhancement = result
                project.updatedAt = .now
            }
        }
    }

    private func importDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .plainText, .pdf,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "doc")  ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls")  ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "ppt")  ?? .data,
            UTType(filenameExtension: "md")   ?? .plainText,
            UTType(filenameExtension: "csv")  ?? .plainText,
            UTType(filenameExtension: "rtf")  ?? .data
        ]
        panel.message = "选择客户提供的文档（最多 5 个）"
        panel.begin { [self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = Array(panel.urls.prefix(5))
            docImportPhase = .idle
            pendingDocQuestions = []
            pendingQuestionSelection = [:]
            Task { @MainActor in
                if let result = await self.docAnalyzer.analyze(fileURLs: urls, settings: self.settings) {
                    self.analysisResult = result
                    self.docImportPhase = .analyzed(result)
                }
            }
        }
    }

    private func generateDocQuestions(docContent: String) {
        let departments = pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)
        Task { @MainActor in
            if let questions = await docAnalyzer.rebuildProjectQuestions(
                docContent: docContent,
                project: project,
                departments: departments,
                settings: settings
            ) {
                pendingDocQuestions = questions
                pendingQuestionSelection = Dictionary(
                    uniqueKeysWithValues: questions.indices.map { ($0, true) }
                )
                docImportPhase = .pendingConfirm
            }
        }
    }

    private func applySelectedDocQuestions() {
        let selected = pendingDocQuestions.enumerated().compactMap { idx, q in
            (pendingQuestionSelection[idx] ?? true) ? q : nil
        }
        guard !selected.isEmpty else { return }

        var enhancement = project.aiEnhancement ?? AIProjectEnhancement()
        let existingIds = Set(enhancement.additionalQuestions.map(\.id))
        let newOnes = selected.filter { !existingIds.contains($0.id) }
        enhancement.additionalQuestions.append(contentsOf: newOnes)

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let timeStr = formatter.string(from: Date())
        let fileLabel: String
        if let result = analysisResult, !result.fileNames.isEmpty {
            fileLabel = result.fileNames.count == 1
                ? result.fileNames[0]
                : "\(result.fileNames[0]) 等 \(result.fileNames.count) 个文档"
        } else {
            fileLabel = "文档"
        }
        enhancement.importedDocsSummary.append("\(fileLabel)（\(timeStr)，+\(newOnes.count)题）")

        project.aiEnhancement = enhancement
        project.updatedAt = .now

        pendingDocQuestions = []
        pendingQuestionSelection = [:]
        docImportPhase = .applied
    }

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
            deptAnsweredCounts: deptCounts,
            hasAIEnhancement: project.aiEnhancement != nil
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
            let rawSections = pluginLoader.questionsBySection(for: deptId)
            let sections: [ExportSnapshot.ExportSectionData] = rawSections.map { (section, questions) in
                let items: [ExportSnapshot.ExportItem] = questions.map { q in
                    let ans = deptAnswers.first { $0.questionId == q.id }
                    return ExportSnapshot.ExportItem(
                        topic: q.topic,
                        question: q.question,
                        selectedOptions: ans?.selectedOptions ?? [],
                        textValue: ans?.textValue ?? "",
                        noteText: ans?.noteText ?? "",
                        polishedText: ans?.polishedText ?? "",
                        voiceTranscript: ans?.voiceTranscript ?? "",
                        hasContent: ans?.hasContent ?? false
                    )
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
            aiEnhancement: project.aiEnhancement,
            selectedDepartmentIds: project.selectedDepartmentIds,
            departmentNames: deptNames, departmentSections: deptSections
        )
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

    private func exportToObsidian() {
        let vaultPath = settings.obsidianConfig.vaultPath
        guard !vaultPath.isEmpty else {
            obsidianExportMessage = "请先在设置中选择 Obsidian Vault"
            return
        }
        isExportingToObsidian = true
        obsidianExportMessage = nil
        let snapshot = buildExportSnapshot()
        let vaultURL = URL(fileURLWithPath: vaultPath)
        Task {
            let content = MarkdownExporter.exportProject(snapshot: snapshot, config: .default)
            let folderURL = vaultURL.appendingPathComponent("调研报告")
            let fileURL = folderURL.appendingPathComponent("\(snapshot.displayName) 调研报告.md")
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                isExportingToObsidian = false
                withAnimation { obsidianExportMessage = "✅ 已写入 Obsidian" }
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    if obsidianExportMessage?.hasPrefix("✅") == true {
                        obsidianExportMessage = nil
                    }
                }
            } catch {
                isExportingToObsidian = false
                withAnimation { obsidianExportMessage = "❌ 写入失败" }
            }
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
        case .draft:      .gray
        case .inProgress: Color.ahAccent
        case .completed:  Color.ahSuccess
        case .archived:   .secondary
        }
    }

    private var statusPillStyle: AHPill.Style {
        switch project.status {
        case .draft:      .neutral
        case .inProgress: .info
        case .completed:  .success
        case .archived:   .neutral
        }
    }
}

// MARK: - DocImportPhase

enum DocImportPhase: Equatable {
    case idle
    case analyzed(ProjectDocumentAnalyzer.DocumentAnalysisResult)
    case pendingConfirm
    case applied

    static func == (lhs: DocImportPhase, rhs: DocImportPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.pendingConfirm, .pendingConfirm), (.applied, .applied): return true
        case (.analyzed, .analyzed): return true
        default: return false
        }
    }
}
