import Foundation

/// 题型感知的答案校验。
///
/// `Answer.hasContent` 只表示记录里存在原始内容，不能用于判断一道题是否真正完成。
/// 所有进度、MCP 回写与导出状态都应以这里的结果为准。
enum AnswerValidator {
    struct Result: Equatable {
        let isValid: Bool
        let code: String?
        let message: String?

        static let valid = Result(isValid: true, code: nil, message: nil)

        static func invalid(_ code: String, _ message: String) -> Result {
            Result(isValid: false, code: code, message: message)
        }
    }

    static func evaluate(_ answer: Answer, for question: QuestionTemplate) -> Result {
        guard answer.status != .ignored, answer.status != .transferred else {
            return .invalid("ANSWER_NOT_ACTIVE", "已忽略或已转移的答案不计入完成进度")
        }
        return evaluate(
            text: answer.textValue,
            selectedOptions: answer.selectedOptions,
            otherText: answer.otherText,
            for: question
        )
    }

    static func evaluate(
        text: String,
        selectedOptions: [String],
        otherText: String = "",
        for question: QuestionTemplate
    ) -> Result {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOther = otherText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch question.type {
        case .text:
            return trimmedText.isEmpty
                ? .invalid("ANSWER_TEXT_REQUIRED", "文本题需要非空回答")
                : .valid

        case .number:
            guard !trimmedText.isEmpty else {
                return .invalid("ANSWER_NUMBER_REQUIRED", "数字题需要填写数值")
            }
            let normalized = trimmedText.replacingOccurrences(of: ",", with: "")
            return Double(normalized) == nil
                ? .invalid("ANSWER_NUMBER_INVALID", "数字题答案无法解析为数值")
                : .valid

        case .singleChoice:
            guard selectedOptions.count == 1, let selected = selectedOptions.first else {
                return .invalid("ANSWER_SINGLE_CHOICE_REQUIRED", "单选题必须且只能选择一个选项")
            }
            return validateChoice(selected, otherText: trimmedOther, options: question.options ?? [])

        case .multiChoice:
            guard !selectedOptions.isEmpty else {
                return .invalid("ANSWER_MULTI_CHOICE_REQUIRED", "多选题至少需要选择一个选项")
            }
            guard Set(selectedOptions).count == selectedOptions.count else {
                return .invalid("ANSWER_OPTION_DUPLICATED", "多选题包含重复选项")
            }
            for selected in selectedOptions {
                let result = validateChoice(selected, otherText: trimmedOther, options: question.options ?? [])
                if !result.isValid { return result }
            }
            return .valid

        case .boolean:
            if !(question.options ?? []).isEmpty {
                guard selectedOptions.count == 1, let selected = selectedOptions.first else {
                    return .invalid("ANSWER_BOOLEAN_REQUIRED", "布尔题必须选择一个合法选项")
                }
                return validateChoice(selected, otherText: trimmedOther, options: question.options ?? [])
            }
            let accepted = Set(["true", "false", "yes", "no", "是", "否", "有", "无"])
            return accepted.contains(trimmedText.lowercased())
                ? .valid
                : .invalid("ANSWER_BOOLEAN_INVALID", "布尔题需要明确的是/否答案")
        }
    }

    private static func validateChoice(_ selected: String, otherText: String, options: [String]) -> Result {
        if selected == "__other__" {
            return otherText.isEmpty
                ? .invalid("ANSWER_OTHER_TEXT_REQUIRED", "选择“其他”时必须填写补充内容")
                : .valid
        }
        return options.contains(selected)
            ? .valid
            : .invalid("ANSWER_OPTION_INVALID", "所选内容不在题库合法选项中")
    }
}
