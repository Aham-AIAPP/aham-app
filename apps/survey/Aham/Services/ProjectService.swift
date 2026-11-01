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
        if saveChanges {
            do { try context.save() } catch { context.rollback(); throw error }
        }
        return project
    }

    static let editableFields: Set<String> = [
        "customerName", "consultant", "companyScale", "headcount", "revenue",
        "existingSystems", "productInfo", "surveyGoal", "status"
    ]

    func requireWritable(_ project: Project) throws {
        guard project.status != .archived else {
            throw ServiceError.archived("项目已归档；请先取消归档再修改")
        }
    }

    /// 所有界面和 MCP 项目修改共用规则；校验发生在修改模型之前。
    func update(_ project: Project, fields: [String: String], expectedRevision: Int? = nil,
                saveChanges: Bool = true) throws {
        guard !fields.isEmpty, Set(fields.keys).isSubset(of: Self.editableFields) else {
            throw ServiceError.invalidInput("包含不允许更新的项目字段")
        }
        if let expectedRevision, expectedRevision != project.revision {
            throw ServiceError.revisionConflict("项目已被修改，请回读后重试")
        }
        let targetStatus = fields["status"].flatMap(ProjectStatus.init(rawValue:))
        if fields["status"] != nil, targetStatus == nil {
            throw ServiceError.invalidInput("未知项目状态")
        }
        if project.status == .archived {
            guard fields.count == 1, targetStatus == .inProgress || targetStatus == .completed else {
                throw ServiceError.archived("归档项目只允许明确恢复为进行中或已完成")
            }
        }
        if targetStatus == .completed { try ensureRequiredQuestionsAnswered(project) }
        if let name = fields["customerName"], name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServiceError.invalidInput("客户名称不能为空")
        }
        if let value = fields["customerName"] { project.customerName = value; project.name = value }
        if let value = fields["consultant"] { project.consultant = value }
        if let value = fields["companyScale"] { project.companyScale = value }
        if let value = fields["headcount"] { project.headcount = value }
        if let value = fields["revenue"] { project.revenue = value }
        if let value = fields["existingSystems"] { project.existingSystems = value }
        if let value = fields["productInfo"] { project.productInfo = value }
        if let value = fields["surveyGoal"] { project.surveyGoal = value }
        if let targetStatus { project.status = targetStatus }
        try didMutate(project, saveChanges: saveChanges)
    }

    /// 一次业务修改对应一次项目修订；进度包含基础题与已采纳追问。
    func didMutate(_ project: Project, saveChanges: Bool = true) throws {
        project.updatedAt = .now
        project.revision += 1
        syncProgress(project)
        if project.status == .completed, !missingRequiredQuestions(project).isEmpty {
            project.status = .inProgress
        }
        if saveChanges {
            do { try context.save() } catch { context.rollback(); throw error }
        }
    }

    func missingRequiredQuestions(_ project: Project) -> [String] {
        let survey = SurveyService(context: context, pluginLoader: pluginLoader)
        let answers = survey.answers(for: project)
        return project.selectedDepartmentIds.flatMap { department in
            survey.questions(for: project, departmentId: department).filter { question in
                question.required && !answers.contains {
                    $0.departmentId == department && $0.questionId == question.id &&
                    AnswerValidator.evaluate($0, for: question).isValid
                }
            }.map(\.id)
        }
    }

    func ensureRequiredQuestionsAnswered(_ project: Project) throws {
        let missing = missingRequiredQuestions(project)
        guard missing.isEmpty else {
            throw ServiceError.invalidInput("仍有 \(missing.count) 道必答题未形成有效答案：\(missing.prefix(8).joined(separator: ", "))")
        }
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
        for change in try context.fetch(FetchDescriptor<MCPChangeSet>(
            predicate: #Predicate { $0.projectId == projectId }
        )) { context.delete(change) }
        context.delete(project)
        do { try context.save() } catch { context.rollback(); throw error }
    }

    // MARK: - 进度

    /// 重算题目总数与已答数
    func syncProgress(_ project: Project) {
        let selected = Set(project.selectedDepartmentIds)
        let survey = SurveyService(context: context, pluginLoader: pluginLoader)
        let questions = Dictionary(uniqueKeysWithValues: project.selectedDepartmentIds.map {
            ($0, survey.questions(for: project, departmentId: $0))
        })
        let total = questions.values.reduce(0) { $0 + $1.count }
        let projectId = project.id
        let answers = (try? context.fetch(
            FetchDescriptor<Answer>(predicate: #Predicate { $0.projectId == projectId })
        )) ?? []
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
    case undoConflict(String)
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
             .changeSetAlreadyUndone(let msg),
             .undoConflict(let msg): msg
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
        case .undoConflict(let message):
            return ["code": "UNDO_CONFLICT", "message": message, "retryable": false]
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
