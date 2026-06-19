import SwiftUI

/// 备忘录条目类型
/// 准入规则：
/// - 表单：客户明确提到在用的表单、报表、系统通道（如"我们用 Excel 管排产"）
/// - 指标：客户提到的具体 KPI、数据、量化场景（如"良率要求 99.5%"）
/// - 审批：客户描述的审批流程、签字环节（如"采购超5万需要总经理签"）
/// - 需求：客户明确表达的功能诉求或痛点期望（如"希望能手机上审批"）
enum MemoCategory: String, CaseIterable, Identifiable {
    case forms       // 表单/报表/系统
    case metrics     // 指标/KPI/数据
    case approvals   // 审批/签字/流程
    case needs       // 明确需求/期望

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forms: "表单/系统"
        case .metrics: "指标/KPI"
        case .approvals: "审批流程"
        case .needs: "明确需求"
        }
    }

    var icon: String {
        switch self {
        case .forms: "doc.text"
        case .metrics: "chart.bar.xaxis"
        case .approvals: "checkmark.seal"
        case .needs: "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .forms: .blue
        case .metrics: .orange
        case .approvals: .green
        case .needs: .purple
        }
    }

    /// 准入提示（输入框 placeholder）
    var placeholder: String {
        switch self {
        case .forms: "客户提到的表单/报表/系统名称..."
        case .metrics: "客户提到的具体指标或数据..."
        case .approvals: "客户描述的审批/签字环节..."
        case .needs: "客户明确表达的功能需求..."
        }
    }
}

/// AI 润色状态
enum PolishStatus: Equatable {
    case idle
    case pending
    case ready
    case error(String)
}

/// 已采纳的 AI 追问（插入为二级问题）
struct AdoptedFollowup: Identifiable {
    let id: String
    let parentQuestionId: String
    let departmentId: String
    let template: QuestionTemplate
}
