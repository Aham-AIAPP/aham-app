import Foundation
import SwiftData

/// 项目读写 —— 视图与 MCP 共用的唯一入口。
///
/// 业务逻辑从 View 里抽出来的目的：MCP 需要在没有视图上下文的情况下建项目、
/// 读进度、算统计。所有方法都在 MainActor 上跑，与 SwiftData 的 ModelContext 同域。
@MainActor
struct ProjectService {
    let context: ModelContext
    let pluginLoader: PluginLoader

    init(context: ModelContext, pluginLoader: PluginLoader) {
        self.context = context
        self.pluginLoader = pluginLoader
    }

    // MARK: - 读

    func allProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func project(id: UUID) throws -> Project? {
        try allProjects().first { $0.id == id }
    }

    /// 按 UUID 或客户名模糊定位 —— MCP 调用方通常只有客户名
    func resolveProject(_ identifier: String) throws -> Project? {
        if let uuid = UUID(uuidString: identifier) {
            return try project(id: uuid)
        }
        let projects = try allProjects()
        if let exact = projects.first(where: { $0.displayName == identifier }) {
            return exact
        }
        return projects.first {
            $0.displayName.localizedCaseInsensitiveContains(identifier) ||
            $0.customerName.localizedCaseInsensitiveContains(identifier)
        }
    }

    // MARK: - 写

    struct CreateRequest {
        var customerName: String
        var consultant: String = ""
        var surveyDate: Date = .now
        var industry: Industry = .general
        var scopes: [SurveyScope] = [.fullDiag]
        var departmentIds: [String]? = nil     // nil = 按 scope 自动匹配
        var companyScale: String = ""
        var headcount: String = ""
        var revenue: String = ""
        var existingSystems: String = ""
        var productInfo: String = ""
        var surveyGoal: String = ""
    }

    @discardableResult
    func create(_ request: CreateRequest) throws -> Project {
        let name = request.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ServiceError.invalidInput("客户名称不能为空") }

        let project = Project(
            name: name,
            customerName: name,
            consultant: request.consultant,
            surveyDate: request.surveyDate
        )
        project.industryEnum = request.industry
        project.surveyScopes = request.scopes.isEmpty ? [.fullDiag] : request.scopes
        project.companyScale = request.companyScale
        project.headcount = request.headcount
        project.revenue = request.revenue
        project.existingSystems = request.existingSystems
        project.productInfo = request.productInfo
        project.surveyGoal = request.surveyGoal
        project.selectedDepartmentIds = request.departmentIds
            ?? Array(SurveyScope.mergedDepartmentIds(project.surveyScopes)).sorted()

        context.insert(project)
        syncProgress(project)
        try context.save()
        return project
    }

    func update(_ project: Project, apply: (Project) -> Void) throws {
        apply(project)
        project.updatedAt = .now
        try context.save()
    }

    func delete(_ project: Project) throws {
        let projectId = project.id
        for answer in try context.fetch(
            FetchDescriptor<Answer>(predicate: #Predicate { $0.projectId == projectId })
        ) {
            context.delete(answer)
        }
        for memo in try context.fetch(
            FetchDescriptor<MemoItem>(predicate: #Predicate { $0.projectId == projectId })
        ) {
            context.delete(memo)
        }
        for followup in try context.fetch(
            FetchDescriptor<AdoptedFollowup>(predicate: #Predicate { $0.projectId == projectId })
        ) {
            context.delete(followup)
        }
        context.delete(project)
        try context.save()
    }

    // MARK: - 进度

    /// 重算题目总数与已答数
    func syncProgress(_ project: Project) {
        let selected = Set(project.selectedDepartmentIds)
        let total = pluginLoader.questionsForProject(project).values.reduce(0) { $0 + $1.count }
        let projectId = project.id
        let answers = (try? context.fetch(
            FetchDescriptor<Answer>(predicate: #Predicate { $0.projectId == projectId })
        )) ?? []
        let answered = answers.filter { selected.contains($0.departmentId) && $0.hasContent }.count

        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }
}

// MARK: - 错误

enum ServiceError: LocalizedError {
    case invalidInput(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg): msg
        case .notFound(let what):    "未找到\(what)"
        }
    }
}
