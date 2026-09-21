import Foundation
import SwiftData

/// 题目与答案读写 —— 视图与 MCP 共用。
@MainActor
struct SurveyService {
    let context: ModelContext
    let pluginLoader: PluginLoader

    init(context: ModelContext, pluginLoader: PluginLoader) {
        self.context = context
        self.pluginLoader = pluginLoader
    }

    // MARK: - 题目

    /// 某部门的题目流：模板题 + 已采纳追问（追问紧跟其父题目）
    func questions(for project: Project, departmentId: String) -> [QuestionTemplate] {
        let base = pluginLoader.questions(for: departmentId, scopes: project.surveyScopes)
        let followups = adoptedFollowups(for: project, departmentId: departmentId)
        var result: [QuestionTemplate] = []
        for question in base {
            result.append(question)
            for followup in followups where followup.parentQuestionId == question.id {
                result.append(followup.asTemplate(section: question.section))
            }
        }
        return result
    }

    func adoptedFollowups(for project: Project, departmentId: String? = nil) -> [AdoptedFollowup] {
        let projectId = project.id
        let all = (try? context.fetch(
            FetchDescriptor<AdoptedFollowup>(predicate: #Predicate { $0.projectId == projectId })
        )) ?? []
        return all
            .filter { departmentId == nil || $0.departmentId == departmentId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - 答案

    func answers(for project: Project) -> [Answer] {
        let projectId = project.id
        return (try? context.fetch(
            FetchDescriptor<Answer>(predicate: #Predicate { $0.projectId == projectId })
        )) ?? []
    }

    /// 取出（必要时创建）某题的答案记录
    @discardableResult
    func answer(for project: Project, departmentId: String, questionId: String) -> Answer {
        if let existing = answers(for: project).first(
            where: { $0.departmentId == departmentId && $0.questionId == questionId }
        ) {
            return existing
        }
        let created = Answer(projectId: project.id, departmentId: departmentId, questionId: questionId)
        context.insert(created)
        return created
    }

    struct AnswerPatch {
        var departmentId: String
        var questionId: String
        var text: String?
        var options: [String]?
        var otherText: String? = nil
        var note: String?
        var transcript: String?
    }

    struct ValidationIssue: Equatable {
        let departmentId: String
        let questionId: String
        let code: String
        let message: String

        var payload: [String: Any] {
            [
                "department": departmentId,
                "question": questionId,
                "code": code,
                "message": message
            ]
        }
    }

    struct AnswerValidationError: LocalizedError, MCPStructuredError {
        let issues: [ValidationIssue]

        var errorDescription: String? { "答案校验失败（\(issues.count) 项）" }
        var payload: [String: Any] {
            [
                "code": "ANSWER_VALIDATION_FAILED",
                "message": errorDescription ?? "答案校验失败",
                "retryable": false,
                "details": ["issues": issues.map(\.payload)]
            ]
        }
    }

    /// 批量写回答案。返回实际写入的条数与被忽略的题号（题库里不存在的）。
    @discardableResult
    func upsert(
        _ patches: [AnswerPatch],
        into project: Project,
        saveChanges: Bool = true
    ) throws -> (written: Int, unknown: [String]) {
        guard project.status != .archived else {
            throw ServiceError.archived("项目已归档；请先明确取消归档再写入")
        }

        let issues = validate(patches, into: project)
        guard issues.isEmpty else { throw AnswerValidationError(issues: issues) }

        var written = 0
        var unknown: [String] = []

        for patch in patches {
            let known = questions(for: project, departmentId: patch.departmentId)
                .contains { $0.id == patch.questionId }
            guard known else {
                unknown.append(patch.questionId)
                continue
            }

            let record = answer(
                for: project, departmentId: patch.departmentId, questionId: patch.questionId
            )
            if let text = patch.text { record.textValue = text }
            if let options = patch.options { record.selectedOptions = options }
            if let otherText = patch.otherText { record.otherText = otherText }
            if let note = patch.note { record.noteText = note }
            if let transcript = patch.transcript {
                record.voiceTranscript += (record.voiceTranscript.isEmpty ? "" : "\n") + transcript
            }
            let question = questions(for: project, departmentId: patch.departmentId)
                .first { $0.id == patch.questionId }
            if let question {
                record.status = AnswerValidator.evaluate(record, for: question).isValid ? .answered : .unanswered
            }
            written += 1
        }

        project.updatedAt = .now
        project.revision += 1
        if saveChanges { try context.save() }
        return (written, unknown)
    }

    /// 在不修改 SwiftData 的情况下验证整批写入；调用方可据此实现 dry-run / preview。
    func validate(_ patches: [AnswerPatch], into project: Project) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let existingAnswers = answers(for: project)

        for patch in patches {
            guard project.selectedDepartmentIds.contains(patch.departmentId) else {
                issues.append(.init(
                    departmentId: patch.departmentId,
                    questionId: patch.questionId,
                    code: "DEPARTMENT_NOT_SELECTED",
                    message: "部门不在该项目调研范围中"
                ))
                continue
            }
            guard let question = questions(for: project, departmentId: patch.departmentId)
                .first(where: { $0.id == patch.questionId }) else {
                issues.append(.init(
                    departmentId: patch.departmentId,
                    questionId: patch.questionId,
                    code: "QUESTION_NOT_FOUND",
                    message: "题库中不存在该题号"
                ))
                continue
            }

            let existing = existingAnswers.first {
                $0.departmentId == patch.departmentId && $0.questionId == patch.questionId
            }
            let text = patch.text ?? existing?.textValue ?? ""
            let options = patch.options ?? existing?.selectedOptions ?? []
            let otherText = patch.otherText ?? existing?.otherText ?? ""
            let hasAnswerPayload = !options.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let changesAnswerPayload = patch.text != nil || patch.options != nil || patch.otherText != nil

            if changesAnswerPayload, hasAnswerPayload {
                let result = AnswerValidator.evaluate(
                    text: text,
                    selectedOptions: options,
                    otherText: otherText,
                    for: question
                )
                if !result.isValid {
                    issues.append(.init(
                        departmentId: patch.departmentId,
                        questionId: patch.questionId,
                        code: result.code ?? "ANSWER_INVALID",
                        message: result.message ?? "答案不符合题型要求"
                    ))
                }
            }
        }
        return issues
    }

    // MARK: - 备忘

    func memoItems(for project: Project) -> [MemoItem] {
        let projectId = project.id
        let all = (try? context.fetch(
            FetchDescriptor<MemoItem>(predicate: #Predicate { $0.projectId == projectId })
        )) ?? []
        return all.sorted { $0.createdAt < $1.createdAt }
    }
}
