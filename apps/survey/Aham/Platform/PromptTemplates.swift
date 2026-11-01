import Foundation

/// 平台提示词模板引擎
/// 迁移自 DSIE 的 8 个核心提示词 + 辅助格式化函数
enum PromptTemplates {

    // MARK: - 1. 笔记润色 + 智能数据提取

    static func notePolishAndExtract(
        department: String,
        question: String,
        answer: String,
        note: String
    ) -> [LLMMessage] {
        let system = """
        润色调研笔记并提取关键数据。只输出JSON：
        {"polished":"润色后笔记","extracts":{"forms":[],"metrics":[],"approvals":[],"needs":[]}}
        forms=表单/报表/系统名称, metrics=KPI/指标, approvals=审批/签字环节, needs=客户明确表达的需求。
        没有的类别留空数组。只提取明确提到的内容。
        """

        let user = """
        [\(department)] \(question)
        回答：\(answer)\(note.isEmpty ? "" : "\n笔记：\(note)")
        """

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 2. 智能追问

    static func aiFollowup(
        profile: String,
        department: String,
        question: String,
        questionType: String = "",
        options: [String] = [],
        answer: String,
        note: String,
        context: String
    ) -> [LLMMessage] {
        let system = """
        你是企业数字化调研专家。根据客户回答判断是否需要追问。

        必须生成追问的场景（高风险信号）：
        1. 选择了表示缺失/不足的选项（如"无"、"没有"、"不了解"、"手工"、"Excel"、"不清楚"）
        2. 指标类问题回答偏低或异常（如合格率低、周转天数过长、交期达成率低）
        3. 回答暴露管理风险（如"领导审批"而非系统审批、"口头通知"而非系统通知）
        4. 流程缺失或不规范的信号（如"没有标准流程"、"靠经验"、"各部门自己管"）
        5. 系统相关的负面回答（如"系统不好用"、"数据不准"、"手工录入"）

        可以不追问的场景：
        - 回答详细且未暴露风险
        - 已经给出了具体数据和完整说明

        最多1-2个追问。每个追问需要options字段（适合选择的提供选项数组，开放性追问留空数组）。
        输出JSON：[{"question":"...","reason":"追问原因","options":["选项1","选项2"],"method":"直接询问/引导式/数据验证"}] 或 []
        """

        var userParts: [String] = ["\(profile) | \(department)"]
        userParts.append("问：\(question)")
        if !options.isEmpty {
            userParts.append("选项：\(options.joined(separator: " / "))")
        }
        userParts.append("答：\(answer)")
        if !note.isEmpty { userParts.append("笔记：\(note)") }
        if !context.isEmpty { userParts.append("上下文：\(context)") }

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: userParts.joined(separator: "\n"))
        ]
    }

    // MARK: - 辅助格式化

    /// 构建客户画像摘要
    static func formatProfile(project: Project) -> String {
        var parts: [String] = []
        if !project.customerName.isEmpty { parts.append("客户：\(project.customerName)") }
        if !project.companyScale.isEmpty { parts.append("规模：\(project.companyScale)") }
        if !project.headcount.isEmpty { parts.append("人数：\(project.headcount)") }
        if !project.revenue.isEmpty { parts.append("营收：\(project.revenue)") }
        if !project.existingSystems.isEmpty { parts.append("已有系统：\(project.existingSystems)") }
        if !project.productInfo.isEmpty { parts.append("产品工艺：\(project.productInfo)") }
        return parts.isEmpty ? "暂无客户信息" : parts.joined(separator: "；")
    }

    /// 格式化问题列表（供优先级排序和语音填充使用）
    static func formatQuestionList(_ questions: [QuestionTemplate]) -> String {
        let maxCount = 30
        var result = questions.prefix(maxCount).enumerated().map { i, q in
            var line = "\(i + 1). [\(q.id)] \(q.question)"
            if let opts = q.options, !opts.isEmpty {
                line += " 选项：" + opts.joined(separator: "/")
            }
            return line
        }.joined(separator: "\n")
        if questions.count > maxCount {
            result += "\n...（共 \(questions.count) 题，已截断显示前 \(maxCount) 题）"
        }
        return result
    }
}
