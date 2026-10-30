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


    @discardableResult
    func performWrite(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { writeError = error.localizedDescription; return false }
    }
}
