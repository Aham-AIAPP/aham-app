import Foundation

/// 调研范围 — 决定调研哪些部门、问什么方向的问题
enum SurveyScope: String, Codable, CaseIterable, Identifiable {
    case erp = "erp"
    case mes = "mes"
    case wms = "wms"
    case plm = "plm"
    case qms = "qms"
    case aps = "aps"
    case fullDiag = "full"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .erp: "ERP"
        case .mes: "MES"
        case .wms: "WMS"
        case .plm: "PLM"
        case .qms: "QMS"
        case .aps: "APS"
        case .fullDiag: "全面诊断"
        }
    }

    var fullName: String {
        switch self {
        case .erp: "企业资源计划"
        case .mes: "制造执行系统"
        case .wms: "仓储管理系统"
        case .plm: "产品生命周期管理"
        case .qms: "质量管理系统"
        case .aps: "高级计划排程"
        case .fullDiag: "全面诊断"
        }
    }

    var icon: String {
        switch self {
        case .erp: "building.2.crop.circle"
        case .mes: "gearshape.2"
        case .wms: "shippingbox"
        case .plm: "flask"
        case .qms: "checkmark.shield"
        case .aps: "calendar.badge.clock"
        case .fullDiag: "magnifyingglass"
        }
    }

    /// 该范围默认关联的部门 ID
    var defaultDepartmentIds: Set<String> {
        switch self {
        case .erp:
            ["executive", "sales", "planning", "procurement", "warehouse", "finance", "it"]
        case .mes:
            ["executive", "production", "quality", "equipment", "process-tech", "it"]
        case .wms:
            ["warehouse", "procurement", "production", "sales", "it"]
        case .plm:
            ["rd-project", "process-tech", "quality", "production", "it"]
        case .qms:
            ["quality", "production", "procurement", "rd-project", "it"]
        case .aps:
            ["planning", "production", "sales", "procurement", "it"]
        case .fullDiag:
            ["executive", "sales", "rd-project", "planning", "production",
             "procurement", "warehouse", "quality", "equipment", "process-tech",
             "finance", "it"]
        }
    }

    /// 该范围下重点的问题 section
    var focusSections: Set<String> {
        switch self {
        case .erp: ["process", "painpoint"]
        case .mes: ["process", "compliance"]
        case .wms: ["process", "painpoint"]
        case .plm: ["process", "expectation"]
        case .qms: ["compliance", "painpoint"]
        case .aps: ["process", "painpoint"]
        case .fullDiag: ["opening", "process", "painpoint", "expectation", "compliance"]
        }
    }

    /// 合并多个 scope 的部门并集
    static func mergedDepartmentIds(_ scopes: [SurveyScope]) -> Set<String> {
        scopes.reduce(into: Set<String>()) { $0.formUnion($1.defaultDepartmentIds) }
    }
}
