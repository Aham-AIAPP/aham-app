import Foundation
import SwiftData

/// MCP 工具的定义与分发。
///
/// 工具清单同时供首页展示与 stdio 适配器的 `tools/list` 使用 —— 单一事实源，
/// 避免 App 里能做的事和 Claude 看到的能力对不上。
@MainActor
struct MCPTools {

    struct ToolSpec: Identifiable {
        let name: String
        let summary: String
        let arguments: String
        var isWrite: Bool = false
        var id: String { name }
    }

    static let catalog: [ToolSpec] = [
        ToolSpec(name: "list_projects",
                 summary: "列出全部调研项目与完成进度",
                 arguments: "无"),
        ToolSpec(name: "get_project",
                 summary: "读取单个项目的客户信息、部门与调研范围",
                 arguments: "project"),
        ToolSpec(name: "list_questions",
                 summary: "读取某部门的题目、当前答案与触发规则",
                 arguments: "project, department"),
        ToolSpec(name: "export_report",
                 summary: "生成调研报告 Markdown 文本",
                 arguments: "project, departments?"),
        ToolSpec(name: "create_project",
                 summary: "新建调研项目（App 内已无新建入口，只能由此创建）",
                 arguments: "customer, consultant?, industry?, scopes?, departments?, …",
                 isWrite: true),
        ToolSpec(name: "upsert_answers",
                 summary: "批量写回答案、选项与笔记",
                 arguments: "project, answers[]",
                 isWrite: true),
        ToolSpec(name: "import_transcript",
                 summary: "把外部转写文本追加到指定题目",
                 arguments: "project, department, question, text",
                 isWrite: true),
        ToolSpec(name: "update_project",
                 summary: "修改客户信息、调研目标或项目状态",
                 arguments: "project, fields",
                 isWrite: true)
    ]

    let context: ModelContext
    let pluginLoader: PluginLoader

    private var projects: ProjectService { ProjectService(context: context, pluginLoader: pluginLoader) }
    private var survey: SurveyService { SurveyService(context: context, pluginLoader: pluginLoader) }
    private var exporter: ExportService { ExportService(context: context, pluginLoader: pluginLoader) }

    // MARK: - 分发

    func call(_ tool: String, args: [String: Any]) throws -> Any {
        switch tool {
        case "list_projects":     return try listProjects()
        case "get_project":       return try getProject(args)
        case "list_questions":    return try listQuestions(args)
        case "export_report":     return try exportReport(args)
        case "create_project":    return try createProject(args)
        case "upsert_answers":    return try upsertAnswers(args)
        case "import_transcript": return try importTranscript(args)
        case "update_project":    return try updateProject(args)
        default:
            throw ServiceError.invalidInput("未知工具：\(tool)")
        }
    }

    // MARK: - 读

    private func listProjects() throws -> Any {
        try projects.allProjects().map { project in
            [
                "id": project.id.uuidString,
                "customer": project.customerName,
                "consultant": project.consultant,
                "status": project.status.label,
                "industry": project.industryEnum.label,
                "scopes": project.surveyScopes.map(\.label),
                "departments": project.selectedDepartmentIds,
                "answered": project.answeredQuestions,
                "total": project.totalQuestions,
                "surveyDate": ISO8601DateFormatter().string(from: project.surveyDate)
            ]
        }
    }

    private func getProject(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        projects.syncProgress(project)
        return [
            "id": project.id.uuidString,
            "customer": project.customerName,
            "consultant": project.consultant,
            "status": project.status.label,
            "industry": project.industryEnum.label,
            "scopes": project.surveyScopes.map(\.rawValue),
            "departments": project.selectedDepartmentIds.map { deptId in
                [
                    "id": deptId,
                    "name": pluginLoader.departments.first { $0.id == deptId }?.name ?? deptId,
                    "questions": survey.questions(for: project, departmentId: deptId).count
                ]
            },
            "companyScale": project.companyScale,
            "headcount": project.headcount,
            "revenue": project.revenue,
            "existingSystems": project.existingSystems,
            "productInfo": project.productInfo,
            "surveyGoal": project.surveyGoal,
            "answered": project.answeredQuestions,
            "total": project.totalQuestions,
            "memo": survey.memoItems(for: project).map { ["category": $0.category, "text": $0.text] }
        ]
    }

    private func listQuestions(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        guard let deptId = args["department"] as? String else {
            throw ServiceError.invalidInput("缺少 department")
        }
        let answers = survey.answers(for: project)
        return survey.questions(for: project, departmentId: deptId).map { question -> [String: Any] in
            let answer = answers.first { $0.departmentId == deptId && $0.questionId == question.id }
            var payload: [String: Any] = [
                "id": question.id,
                "section": question.section.label,
                "topic": question.topic,
                "question": question.question,
                "type": question.type.rawValue,
                "answered": answer?.hasContent ?? false
            ]
            if let options = question.options, !options.isEmpty { payload["options"] = options }
            if let answer {
                payload["text"] = answer.textValue
                payload["options_selected"] = answer.selectedOptions
                payload["note"] = answer.noteText
            }
            if let triggers = question.triggers, !triggers.isEmpty {
                payload["triggers"] = triggers.map { ["type": $0.type, "content": $0.content] }
            }
            return payload
        }
    }

    private func exportReport(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        var config = ExportConfig.default
        if let departments = args["departments"] as? [String], !departments.isEmpty {
            config.departmentFilter = departments
        }
        return [
            "project": project.displayName,
            "markdown": exporter.markdown(for: project, config: config)
        ]
    }

    // MARK: - 写

    private func createProject(_ args: [String: Any]) throws -> Any {
        guard let customer = args["customer"] as? String else {
            throw ServiceError.invalidInput("缺少 customer")
        }
        var request = ProjectService.CreateRequest(customerName: customer)
        request.consultant = args["consultant"] as? String ?? ""
        if let industry = args["industry"] as? String, let parsed = Industry(rawValue: industry) {
            request.industry = parsed
        }
        if let scopes = args["scopes"] as? [String] {
            let parsed = scopes.compactMap { SurveyScope(rawValue: $0) }
            if !parsed.isEmpty { request.scopes = parsed }
        }
        if let departments = args["departments"] as? [String], !departments.isEmpty {
            request.departmentIds = departments
        }
        request.companyScale = args["companyScale"] as? String ?? ""
        request.headcount = args["headcount"] as? String ?? ""
        request.revenue = args["revenue"] as? String ?? ""
        request.existingSystems = args["existingSystems"] as? String ?? ""
        request.productInfo = args["productInfo"] as? String ?? ""
        request.surveyGoal = args["surveyGoal"] as? String ?? ""

        let project = try projects.create(request)
        return [
            "id": project.id.uuidString,
            "customer": project.customerName,
            "departments": project.selectedDepartmentIds,
            "total": project.totalQuestions
        ]
    }

    private func upsertAnswers(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        guard let rows = args["answers"] as? [[String: Any]], !rows.isEmpty else {
            throw ServiceError.invalidInput("缺少 answers")
        }
        let patches: [SurveyService.AnswerPatch] = rows.compactMap { row in
            guard let departmentId = row["department"] as? String,
                  let questionId = row["question"] as? String else { return nil }
            return SurveyService.AnswerPatch(
                departmentId: departmentId,
                questionId: questionId,
                text: row["text"] as? String,
                options: row["options"] as? [String],
                note: row["note"] as? String,
                transcript: nil
            )
        }
        let result = try survey.upsert(patches, into: project)
        projects.syncProgress(project)
        return [
            "written": result.written,
            "unknownQuestions": result.unknown,
            "answered": project.answeredQuestions,
            "total": project.totalQuestions
        ]
    }

    private func importTranscript(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        guard let departmentId = args["department"] as? String,
              let questionId = args["question"] as? String,
              let text = args["text"] as? String, !text.isEmpty else {
            throw ServiceError.invalidInput("缺少 department / question / text")
        }
        let result = try survey.upsert([
            SurveyService.AnswerPatch(
                departmentId: departmentId, questionId: questionId,
                text: nil, options: nil, note: nil, transcript: text
            )
        ], into: project)
        guard result.written > 0 else {
            throw ServiceError.notFound("题目 \(questionId)")
        }
        return ["ok": true, "question": questionId]
    }

    private func updateProject(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        guard let fields = args["fields"] as? [String: Any], !fields.isEmpty else {
            throw ServiceError.invalidInput("缺少 fields")
        }
        try projects.update(project) { target in
            if let value = fields["consultant"] as? String { target.consultant = value }
            if let value = fields["companyScale"] as? String { target.companyScale = value }
            if let value = fields["headcount"] as? String { target.headcount = value }
            if let value = fields["revenue"] as? String { target.revenue = value }
            if let value = fields["existingSystems"] as? String { target.existingSystems = value }
            if let value = fields["productInfo"] as? String { target.productInfo = value }
            if let value = fields["surveyGoal"] as? String { target.surveyGoal = value }
            if let value = fields["status"] as? String,
               let status = ProjectStatus(rawValue: value) {
                target.status = status
            }
        }
        return ["id": project.id.uuidString, "updated": Array(fields.keys)]
    }

    // MARK: - Helper

    private func resolve(_ args: [String: Any]) throws -> Project {
        guard let identifier = args["project"] as? String else {
            throw ServiceError.invalidInput("缺少 project（可传 UUID 或客户名）")
        }
        guard let project = try projects.resolveProject(identifier) else {
            throw ServiceError.notFound("项目「\(identifier)」")
        }
        return project
    }
}
