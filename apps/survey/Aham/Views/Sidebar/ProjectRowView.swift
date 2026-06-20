import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: AHSpacing.s) {
            // 左：中性图标容器（项目图标，非状态色 —— 状态靠下方点+文字）
            AHIconTile(symbol: project.status.icon, size: AHIconBox.lg, tint: .ahInk60)

            // 中：主标题 + 状态点·文字 + 元信息
            VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                Text(project.displayName)
                    .ahBody()
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: AHSpacing.xs) {
                    AHStatusDot(color: statusColor)
                    Text(project.status.label)
                        .ahCaption()
                        .foregroundStyle(Color.ahInk60)
                    if !project.consultant.isEmpty {
                        Text("·").ahCaption()
                        Text(project.consultant).ahCaption()
                    }
                    Text("·").ahCaption()
                    Text(project.surveyDate, format: .dateTime.month().day())
                        .ahCaption()
                }
            }

            Spacer()

            // 右：进度 mono 数字 + 细进度条（至多一个蓝）
            if project.totalQuestions > 0 {
                VStack(alignment: .trailing, spacing: AHSpacing.xxs) {
                    Text("\(project.answeredQuestions)/\(project.totalQuestions)")
                        .ahMono(12)
                        .foregroundStyle(Color.ahInk40)
                    ProgressView(value: project.progress)
                        .tint(Color.ahAccent)
                        .frame(width: 44)
                }
            }
        }
        .padding(.vertical, AHSpacing.xxs)
    }

    /// 状态点颜色 —— 极弱辅助，语义由文字承载（differentiate without color）。
    private var statusColor: Color {
        switch project.status {
        case .draft:      .ahInk40
        case .inProgress: .ahAccent
        case .completed:  .ahSuccess
        case .archived:   .ahInk20
        }
    }
}
