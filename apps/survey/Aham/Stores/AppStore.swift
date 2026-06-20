import Foundation
import SwiftUI

/// 应用级状态管理
@Observable
final class AppStore {
    /// 当前选中的项目 ID
    var selectedProjectId: UUID?

    /// 是否显示新建项目 Sheet
    var showNewProject = false

    /// 是否在调研模式中
    var isSurveying = false
}
