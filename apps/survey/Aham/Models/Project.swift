import Foundation
import SwiftData

/// 项目状态
enum ProjectStatus: String, Codable, CaseIterable {
    case draft = "draft"              // 草稿（刚创建，未开始调研）
    case inProgress = "inProgress"    // 进行中
    case completed = "completed"      // 已完成
    case archived = "archived"        // 已归档

    var label: String {
        switch self {
        case .draft: "草稿"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .archived: "已归档"
        }
    }

    var icon: String {
        switch self {
        case .draft: "doc"
        case .inProgress: "pencil.circle"
        case .completed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }
}

/// 组织形态选项
enum OrgScale: String, CaseIterable {
    case unset = ""
    case single = "单工厂"
    case multiFactory = "多工厂"
    case multiOrg = "多组织"
    case group = "集团型"

    var label: String {
        self == .unset ? "请选择" : rawValue
    }
}

/// 员工规模选项
enum StaffScale: String, CaseIterable {
    case unset = ""
    case under50 = "50人以下"
    case s50_200 = "50-200人"
    case s200_500 = "200-500人"
    case s500_1000 = "500-1000人"
    case s1000_5000 = "1000-5000人"
    case above5000 = "5000人以上"

    var label: String {
        self == .unset ? "请选择" : rawValue
    }
}

/// 年营收选项
enum RevenueScale: String, CaseIterable {
    case unset = ""
    case under1 = "1亿以下"
    case r1_5 = "1-5亿"
    case r5_10 = "5-10亿"
    case r10_50 = "10-50亿"
    case above50 = "50亿以上"

    var label: String {
        self == .unset ? "请选择" : rawValue
    }
}

/// 常见 ERP/信息系统
enum ERPSystem: String, CaseIterable, Identifiable {
    case yonyou = "用友"
    case kingdee = "金蝶"
    case sap = "SAP"
    case oracle = "Oracle"
    case digiwin = "鼎捷"
    case infor = "Infor"
    case custom = "自研系统"
    case excel = "Excel/手工"
    case none = "无"

    var id: String { rawValue }
}

/// 调研项目
@Model
final class Project {
    var id: UUID
    var name: String
    var customerName: String
    var consultant: String
    var surveyDate: Date
    var createdAt: Date
    var updatedAt: Date
    var status: ProjectStatus
    // 行业与调研范围
    var industry: String = "general"
    var surveyScopeIds: [String] = ["full"]
    var aiEnhancementData: Data?
    var knowledgeQuestionVersion: Int = 0   // 0=不加载知识补充问题；>0=创建时的知识问题版本
    var usesQuestionExclusions: Bool = false  // true=创建时已应用问题排除规则

    // 客户信息
    var companyScale: String      // 组织形态
    var headcount: String         // 员工规模
    var revenue: String           // 年营收
    var existingSystems: String   // 现有系统
    var productInfo: String = ""  // 产品与工艺信息（AI 搜索或手工填写）
    var surveyGoal: String        // 调研目标

    // 选择的部门
    var selectedDepartmentIds: [String]

    // 进度追踪
    var totalQuestions: Int
    var answeredQuestions: Int

    init(
        name: String = "",
        customerName: String = "",
        consultant: String = "",
        surveyDate: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.customerName = customerName
        self.consultant = consultant
        self.surveyDate = surveyDate
        self.createdAt = .now
        self.updatedAt = .now
        self.status = .draft
        self.industry = Industry.general.rawValue
        self.surveyScopeIds = [SurveyScope.fullDiag.rawValue]
        self.aiEnhancementData = nil
        self.companyScale = ""
        self.headcount = ""
        self.revenue = ""
        self.existingSystems = ""
        self.surveyGoal = ""
        self.selectedDepartmentIds = []
        self.totalQuestions = 0
        self.answeredQuestions = 0
    }

    var progress: Double = 0

    var displayName: String {
        if !customerName.isEmpty { return customerName }
        if !name.isEmpty { return name }
        return "未命名项目"
    }

    // MARK: - 类型安全访问

    var industryEnum: Industry {
        get { Industry(rawValue: industry) ?? .general }
        set { industry = newValue.rawValue }
    }

    var surveyScopes: [SurveyScope] {
        get { surveyScopeIds.compactMap { SurveyScope(rawValue: $0) } }
        set { surveyScopeIds = newValue.map(\.rawValue) }
    }

    var aiEnhancement: AIProjectEnhancement? {
        get {
            guard let data = aiEnhancementData else { return nil }
            return try? JSONDecoder().decode(AIProjectEnhancement.self, from: data)
        }
        set {
            aiEnhancementData = try? JSONEncoder().encode(newValue)
        }
    }

    /// 根据调研范围自动计算的部门集合
    var scopeDepartmentIds: Set<String> {
        SurveyScope.mergedDepartmentIds(surveyScopes)
    }
}
