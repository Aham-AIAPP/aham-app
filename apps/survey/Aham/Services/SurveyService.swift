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
        var evidence: String? = nil
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
            if let evidence = patch.evidence { record.evidence = evidence }
            if let transcript = patch.transcript {
                record.voiceTranscript += (record.voiceTranscript.isEmpty ? "" : "\n") + transcript
            }
            let question = questions(for: project, departmentId: patch.departmentId)
                .first { $0.id == patch.questionId }
            if let question { refreshStatus(record, for: question) }
            record.revision += 1
            written += 1
        }

        try ProjectService(context: context, pluginLoader: pluginLoader)
            .didMutate(project, saveChanges: saveChanges)
        return (written, unknown)
    }

    /// 在不修改 SwiftData 的情况下验证整批写入；调用方可据此实现 dry-run / preview。
    func validate(_ patches: [AnswerPatch], into project: Project) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let existingAnswers = answers(for: project)

        var seen = Set<String>()
        for patch in patches {
            guard seen.insert("\(patch.departmentId)::\(patch.questionId)").inserted else {
                issues.append(.init(departmentId: patch.departmentId, questionId: patch.questionId,
                                    code: "QUESTION_DUPLICATED", message: "同一批次不能重复写入同一道题"))
                continue
            }
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

    /// UI 输入可以暂时不完整，但必须遵循相同的归档保护、题型状态及修订规则。
    func editAnswer(_ answer: Answer, in project: Project, expectedRevision: Int? = nil,
                    apply: (Answer) -> Void) throws {
        let projects = ProjectService(context: context, pluginLoader: pluginLoader)
        try projects.requireWritable(project)
        guard answer.projectId == project.id,
              answers(for: project).contains(where: { $0.id == answer.id }),
              project.selectedDepartmentIds.contains(answer.departmentId),
              let question = questions(for: project, departmentId: answer.departmentId)
                .first(where: { $0.id == answer.questionId }) else {
            throw ServiceError.invalidInput("答案不属于当前项目题库")
        }
        if let expectedRevision, answer.revision != expectedRevision {
            throw ServiceError.revisionConflict("答案已被修改，请重新生成 AI 结果")
        }
        apply(answer)
        refreshStatus(answer, for: question)
        answer.revision += 1
        try projects.didMutate(project)
    }

    private func refreshStatus(_ answer: Answer, for question: QuestionTemplate) {
        // 笔记/证据修改不应解除用户明确设置的忽略或转移状态。
        guard answer.status != .ignored, answer.status != .transferred else { return }
        answer.status = AnswerValidator.evaluate(answer, for: question).isValid ? .answered : .unanswered
    }

    /// 仅为界面准备空记录，不改变业务修订；所有后续内容写入均走 editAnswer/upsert。
    func prepareAnswers(for project: Project) throws {
        try ProjectService(context: context, pluginLoader: pluginLoader).requireWritable(project)
        for department in project.selectedDepartmentIds {
            for question in questions(for: project, departmentId: department) {
                _ = answer(for: project, departmentId: department, questionId: question.id)
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    @discardableResult
    func adoptFollowup(_ followup: AdoptedFollowup, into project: Project) throws -> Answer {
        let projects = ProjectService(context: context, pluginLoader: pluginLoader)
        try projects.requireWritable(project)
        guard followup.projectId == project.id,
              !adoptedFollowups(for: project).contains(where: { $0.id == followup.id }),
              project.selectedDepartmentIds.contains(followup.departmentId),
              pluginLoader.questions(for: followup.departmentId).contains(where: { $0.id == followup.parentQuestionId }) else {
            throw ServiceError.invalidInput("追问必须关联当前项目的基础题")
        }
        context.insert(followup)
        let record = answer(for: project, departmentId: followup.departmentId, questionId: followup.id)
        try projects.didMutate(project)
        return record
    }

    func addMemo(_ text: String, category: MemoCategory, to project: Project, merge: Bool = false) throws {
        let projects = ProjectService(context: context, pluginLoader: pluginLoader)
        try projects.requireWritable(project)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = memoItems(for: project).filter { $0.category == category.rawValue }
        if merge, let older = existing.first(where: {
            $0.text.localizedCaseInsensitiveContains(trimmed) || trimmed.localizedCaseInsensitiveContains($0.text)
        }) {
            guard trimmed.count > older.text.count else { return }
            older.text = trimmed
        } else {
            guard existing.count < 20 else { throw ServiceError.invalidInput("该类备忘已达到 20 条上限") }
            context.insert(MemoItem(projectId: project.id, category: category, text: trimmed))
        }
        try projects.didMutate(project)
    }

    func deleteMemo(_ memo: MemoItem, from project: Project) throws {
        let projects = ProjectService(context: context, pluginLoader: pluginLoader)
        try projects.requireWritable(project)
        guard memo.projectId == project.id else { throw ServiceError.invalidInput("备忘不属于当前项目") }
        context.delete(memo)
        try projects.didMutate(project)
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
