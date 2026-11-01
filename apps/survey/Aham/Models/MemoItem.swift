import Foundation
import SwiftData

/// 现场备忘条目（表单 / 指标 / 审批 / 需求四类）
///
/// 改为 SwiftData 持久化之前，备忘是 SurveyView 的 @State：切走即清零、
/// 不进数据库、也不进导出报告 —— AI 润色提取出来的关键信息全部丢失。
@Model
final class MemoItem {
    var id: UUID
    var projectId: UUID
    var category: String        // MemoCategory.rawValue
    var text: String
    var createdAt: Date

    init(projectId: UUID, category: MemoCategory, text: String) {
        self.id = UUID()
        self.projectId = projectId
        self.category = category.rawValue
        self.text = text
        self.createdAt = .now
    }

    var categoryEnum: MemoCategory? {
        MemoCategory(rawValue: category)
    }
}
