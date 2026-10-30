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

    @discardableResult
    func performWrite(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { writeError = error.localizedDescription; return false }
    }
}
