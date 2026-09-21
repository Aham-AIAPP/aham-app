import CryptoKit
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

    static let catalog: [ToolSpec] = MCPContract.current.tools.map {
        ToolSpec(
            name: $0.name,
            summary: $0.summary,
            arguments: $0.arguments,
            isWrite: $0.isWrite
        )
    }

    let context: ModelContext
    let pluginLoader: PluginLoader

    private var projects: ProjectService { ProjectService(context: context, pluginLoader: pluginLoader) }
    private var survey: SurveyService { SurveyService(context: context, pluginLoader: pluginLoader) }
    private var exporter: ExportService { ExportService(context: context, pluginLoader: pluginLoader) }

    // MARK: - 分发

    func call(_ tool: String, args: [String: Any]) throws -> Any {
        switch tool {
        case "get_capabilities":      return getCapabilities()
        case "list_departments":      return listDepartments()
        case "list_projects":        return try listProjects(args)
        case "search_projects":       return try searchProjects(args)
        case "get_project":       return try getProject(args)
        case "list_questions":    return try listQuestions(args)
        case "export_report":     return try exportReport(args)
        case "create_project":    return try createProject(args)
        case "preview_answer_import": return try previewAnswerImport(args)
        case "commit_answer_import":  return try commitAnswerImport(args)
        case "upsert_answers":    return try upsertAnswers(args)
        case "import_transcript": return try importTranscript(args)
        case "update_project":    return try updateProject(args)
        case "get_change_log":        return try getChangeLog(args)
        case "undo_change_set":       return try undoChangeSet(args)
        default:
            throw ServiceError.invalidInput("未知工具：\(tool)")
        }
    }

    // MARK: - 读

    private func getCapabilities() -> Any {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "app": [
                "name": "Aham Survey",
                "version": info["CFBundleShortVersionString"] as? String ?? "development",
                "build": info["CFBundleVersion"] as? String ?? "development"
            ],
            "mcpContractVersion": MCPContract.current.version,
            "questionCatalogVersion": pluginLoader.catalogVersion,
            "protocolVersions": ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"],
            "transport": "stdio-adapter+localhost-rpc",
            "localOnly": true,
            "features": [
                "strictAnswerValidation": true,
                "answerPreviewCommit": true,
                "idempotentWrites": true,
                "revisionControl": true,
                "answerUndo": true,
                "prompts": true,
                "resources": true
            ],
            "departmentsInstalled": pluginLoader.departments.count,
            "tools": MCPContract.current.tools.map(\.name)
        ]
    }

    private func listDepartments() -> Any {
        [
            "departments": pluginLoader.departments.map { department in
                [
                    "id": department.id,
                    "name": department.name,
                    "description": department.description,
                    "questions": pluginLoader.questions(for: department.id).count
                ] as [String: Any]
            },
            "scopes": SurveyScope.allCases.map { scope in
                [
                    "id": scope.rawValue,
                    "name": scope.label,
                    "availableDepartments": Array(scope.defaultDepartmentIds)
                        .filter { id in pluginLoader.departments.contains(where: { $0.id == id }) }
                        .sorted()
                ] as [String: Any]
            }
        ]
    }

    private func listProjects(_ args: [String: Any] = [:]) throws -> Any {
        var all = try projects.allProjects()
        if let rawStatus = args["status"] as? String {
            guard let status = ProjectStatus(rawValue: rawStatus) else {
                throw ServiceError.invalidInput("未知项目状态：\(rawStatus)")
            }
            all = all.filter { $0.status == status }
        }
        return all.map { project in
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
                "revision": project.revision,
                "surveyDate": ISO8601DateFormatter().string(from: project.surveyDate)
            ]
        }
    }

    private func searchProjects(_ args: [String: Any]) throws -> Any {
        guard let query = args["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidInput("缺少 query")
        }
        return try projects.searchProjects(query).map { project in
            [
                "id": project.id.uuidString,
                "customer": project.customerName,
                "consultant": project.consultant,
                "status": project.status.rawValue,
                "revision": project.revision,
                "updatedAt": ISO8601DateFormatter().string(from: project.updatedAt)
            ] as [String: Any]
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
            "revision": project.revision,
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
            let validation = answer.map { AnswerValidator.evaluate($0, for: question) }
            var payload: [String: Any] = [
                "id": question.id,
                "section": question.section.label,
                "topic": question.topic,
                "question": question.question,
                "type": question.type.rawValue,
                "answered": validation?.isValid ?? false,
                "required": question.required,
                "order": question.order
            ]
            if let validation, !validation.isValid {
                payload["validation"] = [
                    "code": validation.code ?? "ANSWER_INVALID",
                    "message": validation.message ?? "答案不符合题型要求"
                ]
            }
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
            "projectId": project.id.uuidString,
            "revision": project.revision,
            "generatedAt": ISO8601DateFormatter().string(from: .now),
            "markdown": exporter.markdown(for: project, config: config)
        ]
    }

    // MARK: - 写

    private func createProject(_ args: [String: Any]) throws -> Any {
        let requestId = optionalRequestId(args)
        if let requestId, let replay = try replayResult(requestId: requestId, tool: "create_project") {
            return replay
        }
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

        let project = try projects.create(request, saveChanges: requestId == nil)
        let result: [String: Any] = [
            "id": project.id.uuidString,
            "customer": project.customerName,
            "departments": project.selectedDepartmentIds,
            "total": project.totalQuestions,
            "revision": project.revision
        ]
        if let requestId {
            try recordChange(
                requestId: requestId,
                project: project,
                tool: "create_project",
                result: result
            )
        }
        return result
    }

    private func previewAnswerImport(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        guard project.status != .archived else {
            throw ServiceError.archived("项目已归档；请先明确取消归档再写入")
        }
        let rows = try answerRows(args)
        let patches = try makePatches(rows)
        let issues = survey.validate(patches, into: project)
        let valid = issues.isEmpty
        var result: [String: Any] = [
            "projectId": project.id.uuidString,
            "projectRevision": project.revision,
            "valid": valid,
            "answerCount": rows.count,
            "issues": issues.map(\.payload)
        ]
        if valid {
            result["preview_token"] = try makePreviewToken(project: project, rows: rows)
        }
        return result
    }

    private func commitAnswerImport(_ args: [String: Any]) throws -> Any {
        let requestId = try requiredRequestId(args)
        if let replay = try replayResult(requestId: requestId, tool: "commit_answer_import") {
            return replay
        }
        let project = try resolve(args)
        let rows = try answerRows(args)
        guard let providedToken = args["preview_token"] as? String else {
            throw ServiceError.invalidInput("缺少 preview_token")
        }
        let expectedToken = try makePreviewToken(project: project, rows: rows)
        guard secureEquals(providedToken, expectedToken) else {
            throw ServiceError.previewStale("预览内容或项目修订已变化，请重新调用 preview_answer_import")
        }

        let patches = try makePatches(rows)
        let before = try answerSnapshot(project: project, patches: patches)
        let write = try survey.upsert(patches, into: project, saveChanges: false)
        projects.syncProgress(project)
        let after = try answerSnapshot(project: project, patches: patches)

        let change = MCPChangeSet(
            requestId: requestId,
            projectId: project.id,
            tool: "commit_answer_import",
            beforeJSON: try jsonData(before),
            afterJSON: try jsonData(after)
        )
        let result: [String: Any] = [
            "changeSet": change.id.uuidString,
            "written": write.written,
            "answered": project.answeredQuestions,
            "total": project.totalQuestions,
            "revision": project.revision
        ]
        try persist(change: change, result: result)
        return result
    }

    private func upsertAnswers(_ args: [String: Any]) throws -> Any {
        let requestId = optionalRequestId(args)
        if let requestId, let replay = try replayResult(requestId: requestId, tool: "upsert_answers") {
            return replay
        }
        let project = try resolve(args)
        let rows = try answerRows(args)
        let patches = try makePatches(rows)
        let before = try answerSnapshot(project: project, patches: patches)
        let result = try survey.upsert(patches, into: project, saveChanges: requestId == nil)
        projects.syncProgress(project)
        let payload: [String: Any] = [
            "written": result.written,
            "unknownQuestions": result.unknown,
            "answered": project.answeredQuestions,
            "total": project.totalQuestions,
            "revision": project.revision
        ]
        if let requestId {
            let change = MCPChangeSet(
                requestId: requestId,
                projectId: project.id,
                tool: "upsert_answers",
                beforeJSON: try jsonData(before),
                afterJSON: try jsonData(answerSnapshot(project: project, patches: patches))
            )
            try persist(change: change, result: payload)
        }
        return payload
    }

    private func importTranscript(_ args: [String: Any]) throws -> Any {
        let requestId = optionalRequestId(args)
        if let requestId, let replay = try replayResult(requestId: requestId, tool: "import_transcript") {
            return replay
        }
        let project = try resolve(args)
        guard let departmentId = args["department"] as? String,
              let questionId = args["question"] as? String,
              let text = args["text"] as? String, !text.isEmpty else {
            throw ServiceError.invalidInput("缺少 department / question / text")
        }
        let patches = [SurveyService.AnswerPatch(
            departmentId: departmentId, questionId: questionId,
            text: nil, options: nil, otherText: nil, note: nil, transcript: text
        )]
        let before = try answerSnapshot(project: project, patches: patches)
        let result = try survey.upsert(patches, into: project, saveChanges: requestId == nil)
        guard result.written > 0 else {
            throw ServiceError.notFound("题目 \(questionId)")
        }
        let payload: [String: Any] = [
            "ok": true,
            "question": questionId,
            "revision": project.revision
        ]
        if let requestId {
            let change = MCPChangeSet(
                requestId: requestId,
                projectId: project.id,
                tool: "import_transcript",
                beforeJSON: try jsonData(before),
                afterJSON: try jsonData(answerSnapshot(project: project, patches: patches))
            )
            try persist(change: change, result: payload)
        }
        return payload
    }

    private func updateProject(_ args: [String: Any]) throws -> Any {
        let requestId = optionalRequestId(args)
        if let requestId, let replay = try replayResult(requestId: requestId, tool: "update_project") {
            return replay
        }
        let project = try resolve(args)
        guard let fields = args["fields"] as? [String: Any], !fields.isEmpty else {
            throw ServiceError.invalidInput("缺少 fields")
        }
        let allowed = Set(["consultant", "companyScale", "headcount", "revenue", "existingSystems", "productInfo", "surveyGoal", "status"])
        let unknown = Set(fields.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw ServiceError.invalidInput("不允许更新字段：\(unknown.sorted().joined(separator: ", "))")
        }
        if let expected = args["expected_revision"] as? Int, expected != project.revision {
            throw ServiceError.revisionConflict("项目当前修订号为 \(project.revision)，不是 \(expected)")
        }
        if project.status == .archived {
            guard fields.count == 1, fields["status"] as? String == ProjectStatus.completed.rawValue else {
                throw ServiceError.archived("归档项目只允许通过 status=completed 明确取消归档")
            }
        }
        if let rawStatus = fields["status"] as? String {
            guard let targetStatus = ProjectStatus(rawValue: rawStatus) else {
                throw ServiceError.invalidInput("未知项目状态：\(rawStatus)")
            }
            if targetStatus == .completed {
                try ensureRequiredQuestionsAnswered(project)
            }
        }
        try projects.update(project, saveChanges: requestId == nil) { target in
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
        let result: [String: Any] = [
            "id": project.id.uuidString,
            "updated": Array(fields.keys).sorted(),
            "revision": project.revision,
            "status": project.status.rawValue
        ]
        if let requestId {
            try recordChange(
                requestId: requestId,
                project: project,
                tool: "update_project",
                result: result
            )
        }
        return result
    }

    private func getChangeLog(_ args: [String: Any]) throws -> Any {
        let project = try resolve(args)
        return try allChangeSets()
            .filter { $0.projectId == project.id }
            .sorted { $0.createdAt > $1.createdAt }
            .map { change in
                [
                    "id": change.id.uuidString,
                    "requestId": change.requestId,
                    "tool": change.tool,
                    "createdAt": ISO8601DateFormatter().string(from: change.createdAt),
                    "undone": change.undoneAt != nil,
                    "undoneAt": change.undoneAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
                ] as [String: Any]
            }
    }

    private func undoChangeSet(_ args: [String: Any]) throws -> Any {
        let requestId = try requiredRequestId(args)
        if let replay = try replayResult(requestId: requestId, tool: "undo_change_set") {
            return replay
        }
        guard let rawId = args["change_set"] as? String,
              let id = UUID(uuidString: rawId),
              let source = try allChangeSets().first(where: { $0.id == id }) else {
            throw ServiceError.notFound("变更集")
        }
        guard source.undoneAt == nil else { throw ServiceError.changeSetAlreadyUndone("该变更集已经撤销") }
        guard ["commit_answer_import", "upsert_answers", "import_transcript"].contains(source.tool) else {
            throw ServiceError.forbidden("该类型变更目前不支持撤销")
        }
        guard let project = try projects.project(id: source.projectId) else {
            throw ServiceError.notFound("项目")
        }
        guard project.status != .archived else {
            throw ServiceError.archived("归档项目不能撤销写入，请先取消归档")
        }
        let snapshot = try jsonObject(source.beforeJSON) as? [[String: Any]] ?? []
        try restoreAnswerSnapshot(snapshot, project: project, saveChanges: false)
        source.undoneAt = .now
        project.revision += 1
        project.updatedAt = .now
        projects.syncProgress(project)

        let undo = MCPChangeSet(
            requestId: requestId,
            projectId: project.id,
            tool: "undo_change_set"
        )
        let result: [String: Any] = [
            "changeSet": source.id.uuidString,
            "undone": true,
            "revision": project.revision,
            "answered": project.answeredQuestions,
            "total": project.totalQuestions
        ]
        try persist(change: undo, result: result)
        return result
    }

    // MARK: - Helper

    private func answerRows(_ args: [String: Any]) throws -> [[String: Any]] {
        guard let rows = args["answers"] as? [[String: Any]], !rows.isEmpty else {
            throw ServiceError.invalidInput("缺少 answers")
        }
        guard rows.count <= 200 else { throw ServiceError.invalidInput("单批答案不能超过 200 条") }
        return rows
    }

    private func makePatches(_ rows: [[String: Any]]) throws -> [SurveyService.AnswerPatch] {
        try rows.enumerated().map { index, row in
            guard let departmentId = row["department"] as? String, !departmentId.isEmpty,
                  let questionId = row["question"] as? String, !questionId.isEmpty else {
                throw ServiceError.invalidInput("answers[\(index)] 缺少 department 或 question")
            }
            let hasWritableField = ["text", "options", "otherText", "note"].contains { row.keys.contains($0) }
            guard hasWritableField else {
                throw ServiceError.invalidInput("answers[\(index)] 至少需要 text、options、otherText 或 note 之一")
            }
            if row.keys.contains("options"), row["options"] as? [String] == nil {
                throw ServiceError.invalidInput("answers[\(index)].options 必须是字符串数组")
            }
            return SurveyService.AnswerPatch(
                departmentId: departmentId,
                questionId: questionId,
                text: row["text"] as? String,
                options: row["options"] as? [String],
                otherText: row["otherText"] as? String,
                note: row["note"] as? String,
                transcript: nil
            )
        }
    }

    private func makePreviewToken(project: Project, rows: [[String: Any]]) throws -> String {
        let payload: [String: Any] = [
            "project": project.id.uuidString,
            "revision": project.revision,
            "answers": rows
        ]
        let data = try jsonData(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func secureEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    private func answerSnapshot(
        project: Project,
        patches: [SurveyService.AnswerPatch]
    ) throws -> [[String: Any]] {
        let answers = survey.answers(for: project)
        return patches.map { patch in
            guard let answer = answers.first(where: {
                $0.departmentId == patch.departmentId && $0.questionId == patch.questionId
            }) else {
                return [
                    "department": patch.departmentId,
                    "question": patch.questionId,
                    "existed": false
                ] as [String: Any]
            }
            return [
                "department": answer.departmentId,
                "question": answer.questionId,
                "existed": true,
                "options": answer.selectedOptions,
                "text": answer.textValue,
                "otherText": answer.otherText,
                "note": answer.noteText,
                "polished": answer.polishedText,
                "transcript": answer.voiceTranscript,
                "status": answer.status.rawValue
            ] as [String: Any]
        }
    }

    private func restoreAnswerSnapshot(
        _ rows: [[String: Any]],
        project: Project,
        saveChanges: Bool = true
    ) throws {
        for row in rows {
            guard let department = row["department"] as? String,
                  let question = row["question"] as? String else { continue }
            let existing = survey.answers(for: project).first {
                $0.departmentId == department && $0.questionId == question
            }
            if row["existed"] as? Bool == false {
                if let existing { context.delete(existing) }
                continue
            }
            let answer = existing ?? survey.answer(for: project, departmentId: department, questionId: question)
            answer.selectedOptions = row["options"] as? [String] ?? []
            answer.textValue = row["text"] as? String ?? ""
            answer.otherText = row["otherText"] as? String ?? ""
            answer.noteText = row["note"] as? String ?? ""
            answer.polishedText = row["polished"] as? String ?? ""
            answer.voiceTranscript = row["transcript"] as? String ?? ""
            answer.status = (row["status"] as? String).flatMap(AnswerStatus.init(rawValue:)) ?? .unanswered
        }
        if saveChanges { try context.save() }
    }

    private func ensureRequiredQuestionsAnswered(_ project: Project) throws {
        let answers = survey.answers(for: project)
        var missing: [String] = []
        for department in project.selectedDepartmentIds {
            for question in survey.questions(for: project, departmentId: department) where question.required {
                let answer = answers.first { $0.departmentId == department && $0.questionId == question.id }
                if answer.map({ AnswerValidator.evaluate($0, for: question).isValid }) != true {
                    missing.append(question.id)
                }
            }
        }
        guard missing.isEmpty else {
            throw ServiceError.invalidInput("仍有 \(missing.count) 道必答题未形成有效答案：\(missing.prefix(8).joined(separator: ", "))")
        }
    }

    private func optionalRequestId(_ args: [String: Any]) -> String? {
        guard let value = args["request_id"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requiredRequestId(_ args: [String: Any]) throws -> String {
        guard let value = optionalRequestId(args), value.count >= 8 else {
            throw ServiceError.invalidInput("缺少至少 8 个字符的 request_id")
        }
        return value
    }

    private func allChangeSets() throws -> [MCPChangeSet] {
        try context.fetch(FetchDescriptor<MCPChangeSet>())
    }

    private func replayResult(requestId: String, tool: String) throws -> Any? {
        guard let existing = try allChangeSets().first(where: { $0.requestId == requestId }) else { return nil }
        guard existing.tool == tool else {
            throw ServiceError.idempotencyConflict("request_id 已被工具 \(existing.tool) 使用")
        }
        return try jsonObject(existing.resultJSON)
    }

    private func recordChange(
        requestId: String,
        project: Project,
        tool: String,
        result: Any
    ) throws {
        let change = MCPChangeSet(requestId: requestId, projectId: project.id, tool: tool)
        try persist(change: change, result: result)
    }

    private func persist(change: MCPChangeSet, result: Any) throws {
        do {
            change.resultJSON = try jsonData(result)
            context.insert(change)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func jsonData(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ServiceError.invalidInput("内部数据无法序列化为 JSON")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> Any {
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func resolve(_ args: [String: Any]) throws -> Project {
        guard let identifier = args["project"] as? String else {
            throw ServiceError.invalidInput("缺少 project（推荐传 UUID，也可传唯一精确客户名）")
        }
        guard let project = try projects.resolveProject(identifier) else {
            throw ServiceError.notFound("项目「\(identifier)」")
        }
        return project
    }
}
