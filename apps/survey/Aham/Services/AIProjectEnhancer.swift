import Foundation

/// AI 项目增强服务 — 在项目创建后根据客户属性和行业生成动态选项集、优先级等
/// 采用按部门分批调用策略，避免超时
@Observable
final class AIProjectEnhancer {
    private let settings: SettingsManager

    var isEnhancing = false
    var progress: String = ""
    var progressFraction: Double = 0  // 0.0 ~ 1.0
    var lastError: String?

    init(settings: SettingsManager) {
        self.settings = settings
    }

    private var provider: (any LLMProvider)? {
        settings.llmProvider
    }

    /// 对项目执行 AI 增强（按部门分批）
    func enhance(project: Project, questionsByDept: [String: [QuestionTemplate]]) async -> AIProjectEnhancement? {
        guard let provider else {
            lastError = "LLM 未配置"
            return nil
        }

        isEnhancing = true
        lastError = nil
        progressFraction = 0
        defer { isEnhancing = false }

        var enhancement = AIProjectEnhancement()
        let deptIds = Array(questionsByDept.keys).sorted()
        let total = deptIds.count

        for (index, deptId) in deptIds.enumerated() {
            let questions = questionsByDept[deptId] ?? []
            guard !questions.isEmpty else { continue }

            progress = "正在分析部门 \(index + 1)/\(total)..."
            progressFraction = Double(index) / Double(max(total, 1))

            let messages = buildDeptPrompt(
                project: project,
                departmentId: deptId,
                questions: Array(questions.prefix(25))
            )

            do {
                let response = try await provider.chat(
                    messages: messages,
                    options: LLMOptions(maxTokens: 2000, temperature: 0.3, timeout: 60)
                )
                mergeDeptResult(response, into: &enhancement)
            } catch {
                // 单个部门失败不影响其他部门
                print("[AIProjectEnhancer] 部门 \(deptId) 增强失败: \(error)")
                continue
            }
        }

        // 最后生成行业上下文摘要（轻量调用）
        progress = "正在生成行业摘要..."
        progressFraction = 0.9
        if let context = await generateIndustryContext(project: project, provider: provider) {
            enhancement.industryContext = context
        }

        // 带入文档分析的上下文
        if let docContext = project.aiEnhancement?.documentContext, !docContext.isEmpty {
            enhancement.documentContext = docContext
        }

        return enhancement
    }

    // MARK: - 按部门的 Prompt（精简，只处理选项和优先级）

    private func buildDeptPrompt(project: Project, departmentId: String, questions: [QuestionTemplate]) -> [LLMMessage] {
        let industry = project.industryEnum

        let system = """
        为调研问题生成选项和优先级。输出JSON：
        {"optionSets":{"问题ID":["选项1","选项2","选项3"]},"priorities":{"问题ID":1},"skips":["问题ID"]}
        规则：选项3-6个，不含"其他"。priority:1必问2重要3一般4可跳5不适用。skips:对该客户不适用的。
        """

        var profile = "行业:\(industry.label)"
        if !project.companyScale.isEmpty { profile += " 规模:\(project.companyScale)" }
        if !project.headcount.isEmpty { profile += " 人员:\(project.headcount)" }
        if !project.revenue.isEmpty { profile += " 营收:\(project.revenue)" }
        if !project.existingSystems.isEmpty { profile += " 已有系统:\(project.existingSystems)" }

        let qList = questions.enumerated().map { i, q in
            "[\(q.id)] \(q.question)"
        }.joined(separator: "\n")

        let user = "\(project.customerName) | \(profile)\n部门:\(departmentId)\n\(qList)"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    private func mergeDeptResult(_ response: String, into enhancement: inout AIProjectEnhancement) {
        guard let json = LLMJSONParser.parse(response) as? [String: Any] else { return }

        if let opts = json["optionSets"] as? [String: [String]] {
            enhancement.optionSets.merge(opts) { _, new in new }
        }
        if let priorities = json["priorities"] as? [String: Int] {
            enhancement.priorityAdjustments.merge(priorities) { _, new in new }
        }
        if let skips = json["skips"] as? [String] {
            enhancement.skipSuggestions.append(contentsOf: skips)
        }
    }

    // MARK: - 行业上下文摘要

    private func generateIndustryContext(project: Project, provider: any LLMProvider) async -> String? {
        let industry = project.industryEnum
        let scopes = project.surveyScopes

        let system = "用1-2句话概括该客户的行业特征和调研重点。直接输出文本，不要JSON。"
        let user = "\(project.customerName) | \(industry.label) | 调研:\(scopes.map(\.label).joined(separator: "+")) | 关注:\(industry.focusAreas.joined(separator: "、"))"

        do {
            return try await provider.chat(
                messages: [
                    LLMMessage(role: .system, content: system),
                    LLMMessage(role: .user, content: user)
                ],
                options: LLMOptions(maxTokens: 200, temperature: 0.3, timeout: 15)
            )
        } catch {
            return nil
        }
    }
}
