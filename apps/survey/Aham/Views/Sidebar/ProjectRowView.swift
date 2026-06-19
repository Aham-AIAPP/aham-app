import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: AHSpacing.s) {
            // 左：状态图标容器
            AHIconTile(symbol: project.status.icon, size: AHIconBox.lg, tint: iconColor)

            // 中：主标题 + 副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .ahCallout()
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: AHSpacing.xxs) {
                    if !project.consultant.isEmpty {
                        Text(project.consultant)
                            .ahCaption()
                            .foregroundStyle(.secondary)
                    }
                    Text(project.surveyDate, format: .dateTime.month().day())
                        .ahCaption()
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 右：进度
            if project.totalQuestions > 0 {
                VStack(alignment: .trailing, spacing: AHSpacing.xxs) {
                    Text("\(project.answeredQuestions)/\(project.totalQuestions)")
                        .ahCaption()
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    ProgressView(value: project.progress)
                        .tint(progressColor)
                        .frame(width: 44)
                }
            }
        }
        .padding(.vertical, AHSpacing.xxs)
    }

    private var iconColor: Color {
        switch project.status {
        case .draft:      .gray
        case .inProgress: .blue
        case .completed:  .green
        case .archived:   .secondary
        }
    }

    private var progressColor: Color {
        project.progress >= 1.0 ? .green : .blue
    }
}
