import Foundation

/// 调研 AI 增强服务 — 调用平台 LLM 服务为调研模块提供 AI 能力
@Observable
final class AISurveyEnhancer {
    private let settings: SettingsManager

    var lastError: String?

    init(settings: SettingsManager) {
        self.settings = settings
    }

    private let knowledgeStore = KnowledgeStore()

    private var provider: (any LLMProvider)? {
        settings.llmProvider
    }

    /// 获取知识库上下文摘要
    private var knowledgeContext: String {
        knowledgeStore.knowledgeSummary()
    }

    // MARK: - 笔记润色 + 数据提取

    struct PolishResult {
        let polished: String
        let extracts: [String: [String]]
    }

    func polishNote(
        project: Project,
        department: String,
        question: String,
        answer: String,
        note: String
    ) async -> PolishResult? {
        guard let provider else { return nil }

        let messages = PromptTemplates.notePolishAndExtract(
            department: department,
            question: question,
            answer: answer,
            note: note
        )

        do {
            let response = try await provider.chat(messages: messages, options: .polishing)
            if let json = LLMJSONParser.parse(response) as? [String: Any] {
                let polished = json["polished"] as? String ?? note
                let extracts = (json["extracts"] as? [String: Any])?.compactMapValues { value in
                    value as? [String]
                } ?? [:]
                return PolishResult(polished: polished, extracts: extracts)
            }
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    // MARK: - 智能追问

    struct FollowupQuestion {
        let question: String
        let options: [String]
        let method: String
        let reason: String
    }

    func generateFollowup(
        project: Project,
        department: String,
        question: String,
        questionType: String = "",
        options: [String] = [],
        answer: String,
        note: String = "",
        context: String = ""
    ) async -> [FollowupQuestion] {
        guard let provider else { return [] }

        let profile = PromptTemplates.formatProfile(project: project)
        let messages = PromptTemplates.aiFollowup(
            profile: profile,
            department: department,
            question: question,
            questionType: questionType,
            options: options,
            answer: answer,
            note: note,
            context: context,
            knowledgeContext: knowledgeContext
        )

        do {
            let response = try await provider.chat(messages: messages, options: .followup)
            if let array = LLMJSONParser.parse(response) as? [[String: Any]] {
                return array.compactMap { dict in
                    guard let q = dict["question"] as? String else { return nil }
                    return FollowupQuestion(
                        question: q,
                        options: dict["options"] as? [String] ?? [],
                        method: dict["method"] as? String ?? "",
                        reason: dict["reason"] as? String ?? ""
                    )
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        return []
    }

    // MARK: - 备忘录智能分类

    struct MemoCategorizeResult {
        let category: String  // forms/metrics/approvals/needs or ""
        let text: String
        let action: String    // add/skip/replace
        let replaceIndex: Int
    }

    func categorizeMemo(
        text: String,
        existingItems: [String: [String]]
    ) async -> MemoCategorizeResult? {
        guard let provider else { return nil }

        let messages = PromptTemplates.memoCategorize(text: text, existingItems: existingItems)

        do {
            let response = try await provider.chat(messages: messages, options: .followup)
            if let json = LLMJSONParser.parse(response) as? [String: Any] {
                let category = json["category"] as? String ?? ""
                let normalized = json["text"] as? String ?? text
                let action = json["action"] as? String ?? "add"
                let replaceIndex = json["replaceIndex"] as? Int ?? 0
                return MemoCategorizeResult(category: category, text: normalized, action: action, replaceIndex: replaceIndex)
            }
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }
}
