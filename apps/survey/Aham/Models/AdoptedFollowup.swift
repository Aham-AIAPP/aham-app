import Foundation
import SwiftData

/// 已采纳的 AI 追问（插入为二级问题）
///
/// 字段拍平存储、读取时重建 `QuestionTemplate`：QuestionTemplate 内含
/// 可选嵌套数组（triggers），直接作为 SwiftData 复合属性存储容易出问题。
@Model
final class AdoptedFollowup {
    var id: String              // "followup-<uuid>"，与 Answer.questionId 一致
    var projectId: UUID
    var departmentId: String
    var parentQuestionId: String
    var topic: String
    var questionText: String
    var typeRaw: String         // QuestionType.rawValue
    var options: [String]
    var hint: String
    var order: Int
    var createdAt: Date

    init(
        id: String,
        projectId: UUID,
        departmentId: String,
        parentQuestionId: String,
        topic: String,
        questionText: String,
        type: QuestionType,
        options: [String],
        hint: String,
        order: Int
    ) {
        self.id = id
        self.projectId = projectId
        self.departmentId = departmentId
        self.parentQuestionId = parentQuestionId
        self.topic = topic
        self.questionText = questionText
        self.typeRaw = type.rawValue
        self.options = options
        self.hint = hint
        self.order = order
        self.createdAt = .now
    }

    /// 重建为题目模板，供问题流与导出复用
    func asTemplate(section: QuestionSection) -> QuestionTemplate {
        QuestionTemplate(
            id: id,
            section: section,
            topic: topic,
            question: questionText,
            type: QuestionType(rawValue: typeRaw) ?? .text,
            options: options.isEmpty ? nil : options,
            required: false,
            hints: hint.isEmpty ? nil : [hint],
            triggers: nil,
            meceGroup: nil,
            knowledgeRef: nil,
            industrySpecific: nil,
            order: order
        )
    }
}
