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
        var note: String?
        var transcript: String?
    }

    /// 批量写回答案。返回实际写入的条数与被忽略的题号（题库里不存在的）。
    @discardableResult
    func upsert(_ patches: [AnswerPatch], into project: Project) throws -> (written: Int, unknown: [String]) {
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
            if let note = patch.note { record.noteText = note }
            if let transcript = patch.transcript {
                record.voiceTranscript += (record.voiceTranscript.isEmpty ? "" : "\n") + transcript
            }
            if record.hasContent, record.status == .unanswered { record.status = .answered }
            written += 1
        }

        project.updatedAt = .now
        try context.save()
        return (written, unknown)
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
