import Foundation

/// 调研 AI 增强服务 — 调用平台 LLM 服务为调研模块提供 AI 能力
@Observable
final class AISurveyEnhancer {
    private let settings: SettingsManager

    var lastError: String?

    init(settings: SettingsManager) {
        self.settings = settings
    }

    private var provider: (any LLMProvider)? {
        settings.llmProvider
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
            context: context
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
}
