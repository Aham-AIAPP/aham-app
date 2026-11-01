import SwiftUI

/// 触发器类型的图标和颜色（SurveyView + FocusedCardContent 共用）
func triggerIcon(for type: TriggerEngine.TriggerType) -> String {
    switch type {
    case .followup: "bubble.left.and.bubble.right"
    case .tip: "lightbulb"
    case .warning: "exclamationmark.triangle"
    case .rule: "info.circle"
    }
}

func triggerColor(for type: TriggerEngine.TriggerType) -> Color {
    switch type {
    case .followup: .ahAccent
    case .tip: .ahWarning
    case .warning: .ahDanger
    case .rule: .ahInk60
    }
}
