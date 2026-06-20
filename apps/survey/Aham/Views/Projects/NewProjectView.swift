import SwiftUI
import SwiftData

struct NewProjectView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(PluginLoader.self) private var pluginLoader
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 基本信息
    @State private var customerName = ""
    @State private var consultant = ""
    @State private var surveyDate = Date.now

    // 行业与范围
    @State private var selectedIndustry: Industry = .general
    @State private var selectedScopes: Set<SurveyScope> = [.fullDiag]

    // 客户属性
    @State private var orgScale: OrgScale = .unset
    @State private var staffScale: StaffScale = .unset
    @State private var revenueScale: RevenueScale = .unset
    @State private var selectedSystems: Set<ERPSystem> = []

    // 部门
    @State private var selectedDeptIds: Set<String> = SurveyScope.fullDiag.defaultDepartmentIds
    @State private var showDeptCustomize = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("新建调研项目")
                    .ahTitle2()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .ahTitle2()
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // 表单（macOS Form 自带滚动，不需要额外 ScrollView）
            Form {
                Section("基本信息") {
                    TextField("客户名称", text: $customerName)
                    TextField("顾问姓名", text: $consultant)
                    DatePicker("调研日期", selection: $surveyDate, displayedComponents: .date)
                }

                Section("行业") {
                    Picker("客户行业", selection: $selectedIndustry) {
                        ForEach(Industry.allCases) { ind in
                            Label(ind.label, systemImage: ind.icon).tag(ind)
                        }
                    }

                    if selectedIndustry != .general {
                        Text(selectedIndustry.focusAreas.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .ahCaption()
                    }
                }

                Section("调研范围") {
                    scopeGrid

                    HStack(spacing: AHSpacing.xxs) {
                        Image(systemName: "info.circle")
                        Text("已自动匹配 \(selectedDeptIds.count) 个部门")
                        Button(showDeptCustomize ? "收起" : "自定义") {
                            showDeptCustomize.toggle()
                        }
                        .buttonStyle(.ahGhost)
                    }
                    .foregroundStyle(.secondary)
                    .ahCaption()

                    if showDeptCustomize {
                        departmentToggles
                    }
                }

                Section("客户概况（可选）") {
                    Picker("组织形态", selection: $orgScale) {
                        ForEach(OrgScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("员工规模", selection: $staffScale) {
                        ForEach(StaffScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("年营收", selection: $revenueScale) {
                        ForEach(RevenueScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }

                    VStack(alignment: .leading, spacing: AHSpacing.xs) {
                        Text("现有系统")
                            .ahCallout()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AHSpacing.xs) {
                            ForEach(ERPSystem.allCases) { sys in
                                let isOn = selectedSystems.contains(sys)
                                Button {
                                    if isOn { selectedSystems.remove(sys) }
                                    else { selectedSystems.insert(sys) }
                                } label: {
                                    Text(sys.rawValue)
                                        .foregroundStyle(isOn ? Color.ahInk : Color.ahInk60)
                                        .ahCaption()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AHSpacing.xxs)
                                        .background(isOn ? Color.ahSelected : Color.clear, in: .rect(cornerRadius: AHRadius.xs))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AHRadius.xs)
                                                .stroke(Color.ahBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // 底部按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("创建项目") {
                    createProject()
                }
                .buttonStyle(.ahPrimary)
                .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 680)
        .onChange(of: selectedScopes) {
            syncDepartments()
        }
    }

    // MARK: - Scope Grid

    @ViewBuilder
    private var scopeGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: AHSpacing.s) {
            ForEach(SurveyScope.allCases) { scope in
                let isSelected = selectedScopes.contains(scope)
                Button {
                    toggleScope(scope)
                } label: {
                    VStack(spacing: AHSpacing.xxs) {
                        Image(systemName: scope.icon)
                            .ahTitle3()
                        Text(scope.label)
                            .foregroundStyle(isSelected ? Color.ahInk : Color.ahInk60)
                            .ahCaption()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.s)
                    .background(isSelected ? Color.ahSelected : Color.clear,
                                in: .rect(cornerRadius: AHRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.lg)
                            .stroke(Color.ahBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.ahInk : Color.ahInk60)
            }
        }
    }

    // MARK: - Department Toggles

    @ViewBuilder
    private var departmentToggles: some View {
        let depts = pluginLoader.departments
        ForEach(depts) { dept in
            Toggle(isOn: Binding(
                get: { selectedDeptIds.contains(dept.id) },
                set: { isOn in
                    if isOn { selectedDeptIds.insert(dept.id) }
                    else { selectedDeptIds.remove(dept.id) }
                }
            )) {
                Label(dept.name, systemImage: dept.sfSymbol)
            }
        }
    }

    // MARK: - Helpers

    private func toggleScope(_ scope: SurveyScope) {
        if scope == .fullDiag {
            selectedScopes = [.fullDiag]
        } else {
            selectedScopes.remove(.fullDiag)
            if selectedScopes.contains(scope) {
                selectedScopes.remove(scope)
                if selectedScopes.isEmpty {
                    selectedScopes = [.fullDiag]
                }
            } else {
                selectedScopes.insert(scope)
            }
        }
    }

    private func syncDepartments() {
        selectedDeptIds = SurveyScope.mergedDepartmentIds(Array(selectedScopes))
    }

    // MARK: - Create

    private func createProject() {
        let trimmedName = customerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let project = Project(
            name: trimmedName,
            customerName: trimmedName,
            consultant: consultant.trimmingCharacters(in: .whitespaces),
            surveyDate: surveyDate
        )
        project.industryEnum = selectedIndustry
        project.surveyScopes = Array(selectedScopes)
        project.companyScale = orgScale.rawValue
        project.headcount = staffScale.rawValue
        project.revenue = revenueScale.rawValue
        project.existingSystems = selectedSystems.map(\.rawValue).sorted().joined(separator: "、")
        project.selectedDepartmentIds = Array(selectedDeptIds)
        let kqVersion = KnowledgeQuestionStore().currentVersion()
        project.knowledgeQuestionVersion = kqVersion
        let exclusions = QuestionExclusionStore().load()
        project.usesQuestionExclusions = !exclusions.isEmpty
        project.totalQuestions = pluginLoader.questionsForProject(project).values.reduce(0) { $0 + $1.count }

        modelContext.insert(project)
        try? modelContext.save()
        appStore.selectedProjectId = project.id
        dismiss()
    }
}

#Preview {
    NewProjectView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .modelContainer(for: [Project.self, Answer.self], inMemory: true)
}
