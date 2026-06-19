import Foundation

/// 触发规则引擎：根据答案内容评估触发规则
struct TriggerEngine {

    /// 触发结果
    struct TriggerResult: Identifiable {
        let id = UUID()
        let type: TriggerType
        let content: String
        let model: String?
    }

    enum TriggerType: String {
        case followup
        case tip
        case warning
        case rule
    }

    /// 评估单个问题的触发规则
    static func evaluate(
        triggers: [TriggerRule],
        answer: String,
        selectedOptions: [String]
    ) -> [TriggerResult] {
        triggers.compactMap { trigger in
            let matched = evaluateCondition(
                trigger.condition,
                answer: answer,
                selectedOptions: selectedOptions
            )
            guard matched else { return nil }
            let type = TriggerType(rawValue: trigger.type) ?? .tip
            return TriggerResult(type: type, content: trigger.content, model: trigger.model)
        }
    }

    /// 简单的条件评估器
    /// 支持: answer == 'value', answer.includes('value'), !answer.includes('value')
    private static func evaluateCondition(
        _ condition: String,
        answer: String,
        selectedOptions: [String]
    ) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespaces)

        // answer == 'value'
        if trimmed.hasPrefix("answer == ") {
            let value = extractQuotedValue(from: trimmed, after: "answer == ")
            // 对于单选题，answer 就是选中的选项
            return answer == value || selectedOptions.contains(value)
        }

        // !answer.includes('value')
        if trimmed.hasPrefix("!answer.includes(") {
            let value = extractParenValue(from: trimmed, after: "!answer.includes(")
            return !selectedOptions.contains(value) && !answer.contains(value)
        }

        // answer.includes('value')
        if trimmed.hasPrefix("answer.includes(") {
            let value = extractParenValue(from: trimmed, after: "answer.includes(")
            return selectedOptions.contains(value) || answer.contains(value)
        }

        return false
    }

    private static func extractQuotedValue(from str: String, after prefix: String) -> String {
        let rest = String(str.dropFirst(prefix.count))
        return rest.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    private static func extractParenValue(from str: String, after prefix: String) -> String {
        let rest = String(str.dropFirst(prefix.count))
        // Remove trailing )
        let cleaned = rest.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }
}
