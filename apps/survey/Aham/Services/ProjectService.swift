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

    /// 按 UUID 或唯一精确名称定位。包含匹配只用于 searchProjects，不能静默用于写入。
    func resolveProject(_ identifier: String) throws -> Project? {
        if let uuid = UUID(uuidString: identifier) {
            return try project(id: uuid)
        }
        let projects = try allProjects()
        let exact = projects.filter {
            $0.displayName.localizedCaseInsensitiveCompare(identifier) == .orderedSame ||
            $0.customerName.localizedCaseInsensitiveCompare(identifier) == .orderedSame
        }
        if exact.count > 1 {
            throw ServiceError.ambiguous("存在多个同名项目，请改用 UUID", candidates: exact.map { $0.id.uuidString })
        }
        return exact.first
    }

    func searchProjects(_ query: String) throws -> [Project] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try allProjects() }
        return try allProjects().filter {
            $0.displayName.localizedCaseInsensitiveContains(needle) ||
            $0.customerName.localizedCaseInsensitiveContains(needle) ||
            $0.consultant.localizedCaseInsensitiveContains(needle)
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
    func create(_ request: CreateRequest, saveChanges: Bool = true) throws -> Project {
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
        let available = Set(pluginLoader.departments.map(\.id))
        let requested = Set(request.departmentIds
            ?? Array(SurveyScope.mergedDepartmentIds(project.surveyScopes)))
        let missing = requested.subtracting(available).sorted()
        if request.departmentIds != nil, !missing.isEmpty {
            throw ServiceError.invalidInput("当前题库未安装部门：\(missing.joined(separator: ", "))")
        }
        let selected = requested.intersection(available).sorted()
        guard !selected.isEmpty else {
            throw ServiceError.invalidInput("当前安装的题库没有适用于所选调研范围的部门，请先调用 list_departments")
        }
        project.selectedDepartmentIds = selected

        context.insert(project)
        syncProgress(project)
        project.revision = 1
        if saveChanges { try context.save() }
        return project
    }

    func update(_ project: Project, saveChanges: Bool = true, apply: (Project) -> Void) throws {
        apply(project)
        project.updatedAt = .now
        project.revision += 1
        if saveChanges { try context.save() }
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
        let questions = pluginLoader.questionsForProject(project)
        let answered = answers.filter { answer in
            guard selected.contains(answer.departmentId),
                  let question = questions[answer.departmentId]?.first(where: { $0.id == answer.questionId }) else {
                return false
            }
            return AnswerValidator.evaluate(answer, for: question).isValid
        }.count

        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }
}

// MARK: - 错误

enum ServiceError: LocalizedError {
    case invalidInput(String)
    case notFound(String)
    case forbidden(String)
    case archived(String)
    case revisionConflict(String)
    case previewStale(String)
    case idempotencyConflict(String)
    case changeSetAlreadyUndone(String)
    case ambiguous(String, candidates: [String])

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg): msg
        case .notFound(let what):    "未找到\(what)"
        case .forbidden(let msg):    msg
        case .archived(let msg),
             .revisionConflict(let msg),
             .previewStale(let msg),
             .idempotencyConflict(let msg),
             .changeSetAlreadyUndone(let msg): msg
        case .ambiguous(let msg, _): msg
        }
    }
}

protocol MCPStructuredError: Error {
    var payload: [String: Any] { get }
}

extension ServiceError: MCPStructuredError {
    var payload: [String: Any] {
        switch self {
        case .invalidInput(let message):
            return ["code": "INVALID_INPUT", "message": message, "retryable": false]
        case .notFound(let target):
            return ["code": "NOT_FOUND", "message": "未找到\(target)", "retryable": false]
        case .forbidden(let message):
            return ["code": "WRITE_FORBIDDEN", "message": message, "retryable": false]
        case .archived(let message):
            return ["code": "PROJECT_ARCHIVED", "message": message, "retryable": false]
        case .revisionConflict(let message):
            return ["code": "REVISION_CONFLICT", "message": message, "retryable": true]
        case .previewStale(let message):
            return ["code": "PREVIEW_STALE", "message": message, "retryable": true]
        case .idempotencyConflict(let message):
            return ["code": "IDEMPOTENCY_CONFLICT", "message": message, "retryable": false]
        case .changeSetAlreadyUndone(let message):
            return ["code": "CHANGE_SET_ALREADY_UNDONE", "message": message, "retryable": false]
        case .ambiguous(let message, let candidates):
            return [
                "code": "PROJECT_AMBIGUOUS",
                "message": message,
                "retryable": false,
                "details": ["candidateIds": candidates]
            ]
        }
    }
}
