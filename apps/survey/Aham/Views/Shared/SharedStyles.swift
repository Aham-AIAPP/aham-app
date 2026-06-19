import SwiftUI

/// 项目内通用 ButtonStyle — 筛选 Chip（胶囊形，选中高亮）
/// 用于 ProjectListView、MeetingListView、SalesDashboardView 等处
struct PillButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption).fontWeight(selected ? .medium : .regular)
            .padding(.horizontal, AHSpacing.s).padding(.vertical, AHSpacing.xxs)
            .background(selected ? Color.ahAccentBG : Color.secondary.opacity(0.08))
            .foregroundStyle(selected ? Color.ahAccent : .secondary)
            .clipShape(Capsule())
    }
}
