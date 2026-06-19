import Foundation

/// 问题类型
enum QuestionType: String, Codable {
    case text
    case singleChoice = "single_choice"
    case multiChoice = "multi_choice"
    case number
    case boolean
}

/// 问题分区
enum QuestionSection: String, Codable, CaseIterable {
    case opening
    case process
    case painpoint
    case expectation
    case compliance

    var label: String {
        switch self {
        case .opening: "开场概况"
        case .process: "业务流程"
        case .painpoint: "痛点困难"
        case .expectation: "期望想法"
        case .compliance: "体系标准"
        }
    }

    var icon: String {
        switch self {
        case .opening: "person.wave.2"
        case .process: "arrow.triangle.branch"
        case .painpoint: "exclamationmark.triangle"
        case .expectation: "lightbulb"
        case .compliance: "checkmark.seal"
        }
    }
}

/// 触发规则
struct TriggerRule: Codable, Hashable {
    let condition: String
    let type: String       // followup, tip, warning, rule
    let content: String
    let model: String?
}

/// 问题模板（从插件 JSON 加载，只读）
struct QuestionTemplate: Codable, Identifiable, Hashable {
    let id: String
    let section: QuestionSection
    let topic: String
    let question: String
    let type: QuestionType
    let options: [String]?
    let required: Bool
    let hints: [String]?
    let triggers: [TriggerRule]?
    let meceGroup: String?
    let knowledgeRef: String?
    let industrySpecific: Bool?
    let order: Int
}

/// 部门问题集合（JSON 文件的根结构）
struct DepartmentQuestions: Codable {
    let department: String
    let departmentName: String
    let version: String
    let totalQuestions: Int
    let sections: [String: String]
    let questions: [QuestionTemplate]
}

/// 行业补充问题集合（按行业叠加在通用问题之上）
struct IndustrySupplementFile: Codable {
    let industry: String
    let industryName: String
    let version: String
    let supplements: [String: [QuestionTemplate]]  // departmentId -> questions
}
