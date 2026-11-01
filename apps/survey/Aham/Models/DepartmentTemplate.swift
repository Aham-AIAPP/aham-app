import Foundation

/// 部门模板（从插件 JSON 加载，只读）
struct DepartmentTemplate: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let defaultSelected: Bool
    let description: String

    /// 映射到 SF Symbols
    var sfSymbol: String {
        switch id {
        case "executive": "building.2"
        case "sales": "cart"
        case "rd-project": "flask"
        case "planning": "calendar"
        case "production": "gearshape.2"
        case "procurement": "shippingbox"
        case "warehouse": "archivebox"
        case "quality": "checkmark.shield"
        case "equipment": "wrench.and.screwdriver"
        case "process-tech": "gear.badge.checkmark"
        case "finance": "yensign.circle"
        case "it": "network"
        default: "folder"
        }
    }
}
