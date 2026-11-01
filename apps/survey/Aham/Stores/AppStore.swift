import Foundation
import SwiftUI

/// 应用级状态管理
@Observable
@MainActor
final class AppStore {
    /// 当前选中的项目 ID
    var selectedProjectId: UUID?

    /// 是否在调研模式中
    var isSurveying = false
    var writeError: String?

    /// Failed text edits survive question/project navigation until retry or explicit discard.
    /// A revision check prevents a retry from overwriting a later MCP edit.
    struct AnswerTextDraft {
        var revision: Int
        var fields: [ReferenceWritableKeyPath<Answer, String>: String] = [:]
    }
    var answerTextDrafts: [UUID: AnswerTextDraft] = [:]


    /// Unselected “other” text is a session draft, never an active/reportable answer.
    var customerNameDrafts: [UUID: (value: String, revision: Int)] = [:]
    var otherOptionDrafts: [UUID: String] = [:]

    @discardableResult
    func saveAnswerText(_ value: String, at field: ReferenceWritableKeyPath<Answer, String>,
                        answer: Answer, project: Project, service: SurveyService) -> Bool {
        var draft = answerTextDrafts[answer.id] ?? .init(revision: answer.revision)
        draft.fields[field] = value
        answerTextDrafts[answer.id] = draft
        return retryAnswerText(answer: answer, project: project, service: service)
    }

    @discardableResult
    func retryAnswerText(answer: Answer, project: Project, service: SurveyService) -> Bool {
        guard let draft = answerTextDrafts[answer.id] else { return false }
        let saved = performWrite {
            try service.editAnswer(answer, in: project, expectedRevision: draft.revision) { record in
                for (key, value) in draft.fields { record[keyPath: key] = value }
                if draft.fields[\Answer.otherText] != nil { Self.syncChoiceText(record) }
            }
        }
        if saved { answerTextDrafts[answer.id] = nil }
        return saved
    }

    @discardableResult
    func selectAnswerOption(_ option: String, multiple: Bool, answer: Answer,
                            project: Project, service: SurveyService) -> Bool {
        guard answerTextDrafts[answer.id] == nil else {
            writeError = "请先保存或放弃未保存的输入，再切换选项。"
            return false
        }
        guard multiple || answer.selectedOptions != [option] else { return false }
        let previousOther = answer.otherText
        let hadOther = answer.selectedOptions.contains("__other__")
        let saved = performWrite {
            try service.editAnswer(answer, in: project, expectedRevision: answer.revision) { record in
                if multiple {
                    if record.selectedOptions.contains(option) { record.selectedOptions.removeAll { $0 == option } }
                    else { record.selectedOptions.append(option) }
                } else { record.selectedOptions = [option] }
                if !record.selectedOptions.contains("__other__") { record.otherText = "" }
                else if !hadOther { record.otherText = otherOptionDrafts[answer.id] ?? "" }
                Self.syncChoiceText(record)
            }
        }
        if saved && hadOther { otherOptionDrafts[answer.id] = previousOther }
        return saved
    }

    private static func syncChoiceText(_ answer: Answer) {
        answer.textValue = answer.selectedOptions.map {
            $0 == "__other__" ? (answer.otherText.isEmpty ? "其他" : answer.otherText) : $0
        }.joined(separator: " | ")
    }

    @discardableResult
    func performWrite(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { writeError = error.localizedDescription; return false }
    }
}
