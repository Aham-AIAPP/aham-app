import Foundation
import SwiftData

/// 导出快照构建 —— 从 ProjectDetailView 抽出，供视图与 MCP 共用。
@MainActor
struct ExportService {
    let context: ModelContext
    let pluginLoader: PluginLoader

    init(context: ModelContext, pluginLoader: PluginLoader) {
        self.context = context
        self.pluginLoader = pluginLoader
    }

    private var survey: SurveyService {
        SurveyService(context: context, pluginLoader: pluginLoader)
    }

    func snapshot(for project: Project) -> ExportSnapshot {
        let answers = survey.answers(for: project)
        var deptNames: [String: String] = [:]
        var deptSections: [String: [ExportSnapshot.ExportSectionData]] = [:]

        for deptId in project.selectedDepartmentIds {
            deptNames[deptId] = pluginLoader.departments.first { $0.id == deptId }?.name ?? deptId
            let deptAnswers = answers.filter { $0.departmentId == deptId }
            let followups = survey.adoptedFollowups(for: project, departmentId: deptId)

            func item(for question: QuestionTemplate, isFollowup: Bool) -> ExportSnapshot.ExportItem {
                let answer = deptAnswers.first { $0.questionId == question.id }
                return ExportSnapshot.ExportItem(
                    topic: question.topic,
                    question: question.question,
                    isFollowup: isFollowup,
                    selectedOptions: answer?.selectedOptions ?? [],
                    textValue: answer?.textValue ?? "",
                    noteText: answer?.noteText ?? "",
                    polishedText: answer?.polishedText ?? "",
                    voiceTranscript: answer?.voiceTranscript ?? "",
                    hasContent: answer?.hasContent ?? false
                )
            }

            deptSections[deptId] = pluginLoader.questionsBySection(for: deptId).map { section, questions in
                var items: [ExportSnapshot.ExportItem] = []
                for question in questions {
                    items.append(item(for: question, isFollowup: false))
                    // 现场采纳的 AI 追问紧跟其父题目输出
                    for followup in followups where followup.parentQuestionId == question.id {
                        items.append(item(for: followup.asTemplate(section: section), isFollowup: true))
                    }
                }
                return ExportSnapshot.ExportSectionData(label: section.label, items: items)
            }
        }

        let memos = survey.memoItems(for: project)
        let memoGroups = MemoCategory.allCases.map { category in
            (category: category.label,
             texts: memos.filter { $0.category == category.rawValue }.map(\.text))
        }

        return ExportSnapshot(
            displayName: project.displayName,
            customerName: project.customerName,
            consultant: project.consultant,
            surveyDate: project.surveyDate,
            statusLabel: project.status.label,
            industryLabel: project.industryEnum.label,
            companyScale: project.companyScale,
            headcount: project.headcount,
            revenue: project.revenue,
            existingSystems: project.existingSystems,
            surveyGoal: project.surveyGoal,
            totalQuestions: project.totalQuestions,
            answeredQuestions: project.answeredQuestions,
            progress: project.progress,
            selectedDepartmentIds: project.selectedDepartmentIds,
            departmentNames: deptNames,
            departmentSections: deptSections,
            memoItems: memoGroups
        )
    }

    func markdown(for project: Project, config: ExportConfig = .default) -> String {
        MarkdownExporter.exportProject(snapshot: snapshot(for: project), config: config)
    }

    func panelData(for project: Project) -> ExportPanelData {
        var deptNames: [String: String] = [:]
        var deptCounts: [String: Int] = [:]
        let answers = survey.answers(for: project)
        for deptId in project.selectedDepartmentIds {
            deptNames[deptId] = pluginLoader.departments.first { $0.id == deptId }?.name ?? deptId
            deptCounts[deptId] = answers.filter { $0.departmentId == deptId && $0.hasContent }.count
        }
        return ExportPanelData(
            projectName: project.displayName,
            selectedDeptIds: project.selectedDepartmentIds,
            deptNames: deptNames,
            deptAnsweredCounts: deptCounts
        )
    }
}
