import SwiftUI

/// 项目内通用 ButtonStyle — 筛选 Chip（胶囊形，选中高亮）
/// 用于 ProjectListView 等处
struct PillButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, AHSpacing.s).padding(.vertical, AHSpacing.xxs)
            .background(selected ? Color.ahSelected : Color.ahPaperAlt)
            .foregroundStyle(selected ? Color.ahInk : Color.ahInk60)
            .clipShape(Capsule())
    }
}
