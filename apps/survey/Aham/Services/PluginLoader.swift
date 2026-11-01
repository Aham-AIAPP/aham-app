import Foundation

/// 加载内置问题库数据（部门模板 + 基础问题）
@Observable
final class PluginLoader {
    private(set) var departments: [DepartmentTemplate] = []
    private(set) var departmentQuestions: [String: DepartmentQuestions] = [:]
    private(set) var catalogVersion: Int = 0
    private(set) var loadError: String?

    init() {
        loadBuiltinData()
        #if DEBUG
        validateTriggerConditions()
        #endif
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
            catalogVersion = manifest.version
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

    // MARK: - 触发规则自检

    #if DEBUG
    /// 题库里的触发条件一旦写成 TriggerEngine 解析不了的形式，就会永远不触发且毫无提示。
    /// 这里在 DEBUG 构建下全量走一遍，把哑规则暴露在控制台。
    private func validateTriggerConditions() {
        var bad: [String] = []
        for (deptId, file) in departmentQuestions {
            for question in file.questions {
                for trigger in question.triggers ?? [] where !TriggerEngine.validate(trigger.condition) {
                    bad.append("[\(deptId)] \(question.id): \(trigger.condition)")
                }
            }
        }
        guard !bad.isEmpty else { return }
        for line in bad {
            print("[TriggerEngine] 无法解析的条件: \(line)")
        }
        assertionFailure("题库存在 \(bad.count) 条无法解析的触发条件，详见控制台")
    }
    #endif

    // MARK: - 查询

    /// 获取指定部门的基础问题列表
    func questions(for departmentId: String) -> [QuestionTemplate] {
        departmentQuestions[departmentId]?.questions ?? []
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

    /// 根据调研范围获取指定部门的问题（按 focusSections 排序）
    func questions(for departmentId: String, scopes: [SurveyScope]) -> [QuestionTemplate] {
        let all = questions(for: departmentId)
        let focusSections = scopes.reduce(into: Set<String>()) { $0.formUnion($1.focusSections) }
        return all.sorted { a, b in
            let aFocus = focusSections.contains(a.section.rawValue)
            let bFocus = focusSections.contains(b.section.rawValue)
            if aFocus != bFocus { return aFocus }
            let aSection = QuestionSection.allCases.firstIndex(of: a.section) ?? Int.max
            let bSection = QuestionSection.allCases.firstIndex(of: b.section) ?? Int.max
            if aSection != bSection { return aSection < bSection }
            return a.order < b.order
        }
    }

    /// 获取项目所有问题（scope 过滤）
    func questionsForProject(_ project: Project) -> [String: [QuestionTemplate]] {
        var result: [String: [QuestionTemplate]] = [:]
        let scopes = project.surveyScopes

        for deptId in project.selectedDepartmentIds {
            let questions = questions(for: deptId, scopes: scopes)

            result[deptId] = questions
        }

        return result
    }
}
