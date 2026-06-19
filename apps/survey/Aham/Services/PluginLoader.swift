import Foundation

/// 加载内置问题库数据（部门模板 + 基础问题 + 行业补充问题 + 知识库补充问题）
@Observable
final class PluginLoader {
    private(set) var departments: [DepartmentTemplate] = []
    private(set) var departmentQuestions: [String: DepartmentQuestions] = [:]
    private(set) var industrySupplements: [String: IndustrySupplementFile] = [:]
    private(set) var loadError: String?

    private let knowledgeQuestionStore = KnowledgeQuestionStore()

    init() {
        loadBuiltinData()
        loadIndustrySupplements()
    }

    // MARK: - 加载内置数据

    private func loadBuiltinData() {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json") else {
            loadError = "未找到内置 manifest.json"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(QuestionManifest.self, from: data)
            departments = manifest.departments
            for file in manifest.departmentFiles {
                guard let fileURL = Bundle.main.url(forResource: file, withExtension: "json") else {
                    continue
                }
                loadQuestionFile(fileURL)
            }
        } catch {
            loadError = "内置数据解析失败: \(error.localizedDescription)"
        }
    }

    private func loadQuestionFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let deptQuestions = try JSONDecoder().decode(DepartmentQuestions.self, from: data)
            departmentQuestions[deptQuestions.department] = deptQuestions
        } catch {
            print("[PluginLoader] 加载 \(url.lastPathComponent) 失败: \(error)")
        }
    }

    // MARK: - 行业补充问题

    private func loadIndustrySupplements() {
        for industry in Industry.allCases where industry != .general {
            guard let url = Bundle.main.url(forResource: "industry-\(industry.rawValue)", withExtension: "json") else {
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let supplement = try JSONDecoder().decode(IndustrySupplementFile.self, from: data)
                industrySupplements[industry.rawValue] = supplement
            } catch {
                print("[PluginLoader] 行业补充问题 \(industry.rawValue) 加载失败: \(error)")
            }
        }
    }

    // MARK: - 查询

    /// 获取指定部门的基础问题列表
    func questions(for departmentId: String) -> [QuestionTemplate] {
        departmentQuestions[departmentId]?.questions ?? []
    }

    /// 获取指定部门的问题列表（含行业补充）
    func questions(for departmentId: String, industry: Industry) -> [QuestionTemplate] {
        var result = questions(for: departmentId)
        if industry != .general, let supplement = industrySupplements[industry.rawValue] {
            if let extra = supplement.supplements[departmentId] {
                result.append(contentsOf: extra)
            }
        }
        return result
    }

    /// 获取指定部门按分区分组的问题
    func questionsBySection(for departmentId: String) -> [(section: QuestionSection, questions: [QuestionTemplate])] {
        let questions = questions(for: departmentId)
        var result: [(QuestionSection, [QuestionTemplate])] = []
        for section in QuestionSection.allCases {
            let sectionQuestions = questions.filter { $0.section == section }
            if !sectionQuestions.isEmpty {
                result.append((section, sectionQuestions))
            }
        }
        return result
    }

    /// 获取指定项目选中部门的模板列表
    func selectedDepartments(ids: [String]) -> [DepartmentTemplate] {
        departments.filter { ids.contains($0.id) }
    }

    // MARK: - Scope 过滤

    /// 根据调研范围获取指定部门的问题（按 focusSections 排序，含行业补充）
    func questions(for departmentId: String, scopes: [SurveyScope], industry: Industry = .general) -> [QuestionTemplate] {
        let all = questions(for: departmentId, industry: industry)
        let focusSections = scopes.reduce(into: Set<String>()) { $0.formUnion($1.focusSections) }
        return all.sorted { a, b in
            let aFocus = focusSections.contains(a.section.rawValue)
            let bFocus = focusSections.contains(b.section.rawValue)
            if aFocus != bFocus { return aFocus }
            return a.order < b.order
        }
    }

    /// 获取项目所有问题（合并 scope 过滤 + 行业补充 + 知识库补充 + AI 增强）
    func questionsForProject(_ project: Project) -> [String: [QuestionTemplate]] {
        var result: [String: [QuestionTemplate]] = [:]
        let scopes = project.surveyScopes
        let industry = project.industryEnum
        let enhancement = project.aiEnhancement
        // 始终尝试加载知识库补充问题（有则加载，无则跳过）
        let kqSupplement = knowledgeQuestionStore.load()

        for deptId in project.selectedDepartmentIds {
            var questions = questions(for: deptId, scopes: scopes, industry: industry)

            // 追加知识库补充问题（置于列表末尾）
            if let extra = kqSupplement?.supplements[deptId] {
                questions.append(contentsOf: extra)
            }

            // 应用问题排除规则（仅新建项目时启用排除）
            if project.usesQuestionExclusions {
                let exclusions = QuestionExclusionStore().load()
                if !exclusions.isEmpty {
                    questions = questions.filter { !exclusions.contains($0.id) }
                }
            }

            // 应用 AI 跳过建议
            if let skips = enhancement?.skipSuggestions {
                questions = questions.filter { !skips.contains($0.id) }
            }

            // 应用 AI 优先级排序
            if let priorities = enhancement?.priorityAdjustments {
                questions.sort { a, b in
                    let pa = priorities[a.id] ?? 3
                    let pb = priorities[b.id] ?? 3
                    return pa < pb
                }
            }

            result[deptId] = questions
        }

        return result
    }
}
