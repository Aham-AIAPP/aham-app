import Foundation

/// 平台提示词模板引擎
/// 迁移自 DSIE 的 8 个核心提示词 + 辅助格式化函数
enum PromptTemplates {

    // MARK: - 1. 笔记润色 + 智能数据提取

    static func notePolishAndExtract(
        department: String,
        question: String,
        answer: String,
        note: String,
        transcript: String
    ) -> [LLMMessage] {
        let system = """
        润色调研笔记并提取关键数据。只输出JSON：
        {"polished":"润色后笔记","extracts":{"forms":[],"metrics":[],"approvals":[],"needs":[]}}
        forms=表单/报表/系统名称, metrics=KPI/指标, approvals=审批/签字环节, needs=客户明确表达的需求。
        没有的类别留空数组。只提取明确提到的内容。
        """

        let user = """
        [\(department)] \(question)
        回答：\(answer)\(note.isEmpty ? "" : "\n笔记：\(note)")\(transcript.isEmpty ? "" : "\n转写：\(transcript)")
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
        context: String,
        knowledgeContext: String = ""
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
        if !knowledgeContext.isEmpty { userParts.append("参考：\(knowledgeContext)") }

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: userParts.joined(separator: "\n"))
        ]
    }

    // MARK: - 3. 语音自动填充

    static func voiceAutoFill(
        department: String,
        questions: String,
        transcript: String
    ) -> [LLMMessage] {
        let system = """
        将语音转写映射到调研问题。只映射明确提及的内容。输出JSON：
        {"answers":[{"questionId":"ID","answer":"回答","confidence":"high/medium/low"}],"note":"补充信息"}
        """

        let user = """
        [\(department)] 问题：\(questions)
        转写：\(transcript)
        """

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 4. 文档分析（支持分块）

    /// - Parameters:
    ///   - docContent: 当前块的文本（外部已截断至合理长度）
    ///   - extractProfile: 是否提取公司画像（仅第一块需要，后续块设为 false 节省 Token）
    static func documentAnalysis(docContent: String, extractProfile: Bool = true) -> [LLMMessage] {
        let profileField = extractProfile
            ? "\"companyProfile\":{\"industry\":\"\",\"scale\":\"\",\"products\":\"\",\"systems\":[],\"certifications\":[]},"
            : "\"companyProfile\":null,"

        let system = """
        分析客户文档片段，提取调研有价值的信息。输出JSON（严格格式）：
        {\(profileField)"knownIssues":[],"knownNeeds":[],"keyFindings":[]}
        \(extractProfile ? "" : "本片段无需提取 companyProfile，直接输出 null。")条目控制在3个以内，内容精炼。
        """

        let user = "文档片段：\n\(docContent)"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 5. 备忘录智能分类

    static func memoCategorize(
        text: String,
        existingItems: [String: [String]]
    ) -> [LLMMessage] {
        let existing = existingItems.map { "\($0.key): \($0.value.joined(separator: "; "))" }.joined(separator: "\n")
        let system = """
        将用户输入分类到备忘录类别。类别：forms(表单/报表/系统名称), metrics(KPI/指标/数据), approvals(审批/签字/流程), needs(客户明确需求)。
        如果与已有条目重复或包含，标记skip。如果是已有条目的更详细版本，标记replace并指定index。
        输出JSON：{"category":"forms/metrics/approvals/needs","text":"规范化文本","action":"add/skip/replace","replaceIndex":0}
        如果内容不属于任何类别，category为空字符串。
        """

        let user = "输入：\(text)\(existing.isEmpty ? "" : "\n已有：\(existing)")"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 5.5 项目文档补充问题重构（项目级，不写入全局知识库）

    /// 基于客户文档内容 + 项目已选部门，生成针对该项目的补充调研问题
    static func projectDocumentQuestionRebuild(
        docContent: String,
        customerName: String,
        departments: [DepartmentTemplate]
    ) -> [LLMMessage] {
        let system = """
        你是企业调研问题设计专家。根据客户提供的文档内容，为各调研部门生成有针对性的补充问题。

        规则：
        - 仅为文档中有明确相关信息的部门生成问题
        - 每个部门最多 3 道补充问题，聚焦文档中揭示的痛点、缺失或需求
        - 问题应比通用问题更具体，直接引用或呼应文档中的关键信息
        - id 格式：doc_{dept_id}_{3位序号}（如 doc_production_001）
        - section 必须是：opening / process / painpoint / expectation / compliance 之一
        - type 必须是：text / single_choice / multi_choice / number / boolean 之一
        - 选择题需提供 options 数组（3-5个选项）；开放题 options 为空数组

        输出 JSON（严格格式，无多余文字）：
        {
          "supplements": {
            "dept_id": [
              {
                "id": "doc_dept_001",
                "departmentId": "dept_id",
                "section": "painpoint",
                "text": "具体问题内容",
                "type": "text",
                "options": [],
                "reason": "生成原因（引用文档中的依据）"
              }
            ]
          }
        }
        """

        let deptList = departments.isEmpty
            ? "（使用项目已选部门）"
            : departments.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")

        let truncatedDoc = String(docContent.prefix(5000))
        let user = """
        客户：\(customerName)
        部门列表：
        \(deptList)

        文档内容：
        \(truncatedDoc)
        """

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
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
