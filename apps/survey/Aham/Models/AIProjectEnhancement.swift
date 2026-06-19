import Foundation

/// AI 在项目创建时生成的增强数据
/// 包含根据客户属性和行业特征动态生成的选项集、优先级调整等
struct AIProjectEnhancement: Codable {
    /// 生成时间
    var generatedAt: Date

    /// 基于客户规模的选项集调整
    /// key = questionId, value = 动态生成的选项列表
    var optionSets: [String: [String]]

    /// 问题优先级调整 (1=最高, 5=最低)
    /// key = questionId, value = 优先级
    var priorityAdjustments: [String: Int]

    /// 建议跳过的问题 ID（对该客户不适用）
    var skipSuggestions: [String]

    /// AI 根据上传文档生成的补充问题
    var additionalQuestions: [AIGeneratedQuestion]

    /// 行业上下文摘要（AI 从文档中提取）
    var industryContext: String

    /// 文档分析结果摘要（用于 AI 增强时的上下文）
    var documentContext: String

    /// 已导入文档的记录（文件名 + 导入时间，用于 UI 展示历史）
    var importedDocsSummary: [String]

    init(
        generatedAt: Date = .now,
        optionSets: [String: [String]] = [:],
        priorityAdjustments: [String: Int] = [:],
        skipSuggestions: [String] = [],
        additionalQuestions: [AIGeneratedQuestion] = [],
        industryContext: String = "",
        documentContext: String = "",
        importedDocsSummary: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.optionSets = optionSets
        self.priorityAdjustments = priorityAdjustments
        self.skipSuggestions = skipSuggestions
        self.additionalQuestions = additionalQuestions
        self.industryContext = industryContext
        self.documentContext = documentContext
        self.importedDocsSummary = importedDocsSummary
    }
}

/// AI 生成的补充问题
struct AIGeneratedQuestion: Codable, Identifiable {
    var id: String
    var departmentId: String
    var section: String
    var text: String
    var type: String       // "single_choice" / "multi_choice"
    var options: [String]
    var reason: String     // AI 为什么建议增加这个问题
}
