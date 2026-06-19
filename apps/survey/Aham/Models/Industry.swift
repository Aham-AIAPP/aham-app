import Foundation

/// 行业分类 — 基于金蝶八大行业解决方案 + 通用
enum Industry: String, Codable, CaseIterable, Identifiable {
    case general = "general"
    case automotive = "automotive"           // 汽车零部件
    case electronics = "electronics"         // 电子电器
    case equipment = "equipment"             // 装备制造
    case food = "food"                       // 食品饮料
    case pharma = "pharma"                   // 医药化工
    case materials = "materials"             // 新材料
    case textile = "textile"                 // 纺织服装
    case metal = "metal"                     // 五金建材

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "通用制造"
        case .automotive: "汽车零部件"
        case .electronics: "电子电器"
        case .equipment: "装备制造"
        case .food: "食品饮料"
        case .pharma: "医药化工"
        case .materials: "新材料"
        case .textile: "纺织服装"
        case .metal: "五金建材"
        }
    }

    var icon: String {
        switch self {
        case .general: "building.2"
        case .automotive: "car"
        case .electronics: "cpu"
        case .equipment: "wrench.and.screwdriver"
        case .food: "cup.and.saucer"
        case .pharma: "flask"
        case .materials: "cube"
        case .textile: "tshirt"
        case .metal: "hammer"
        }
    }

    /// 行业特有的关注领域，AI 增强时作为上下文
    var focusAreas: [String] {
        switch self {
        case .general:
            ["生产管理", "供应链", "财务管理"]
        case .automotive:
            ["IATF16949", "APQP/PPAP", "追溯管理", "JIT/JIS配送", "模具管理"]
        case .electronics:
            ["SMT管理", "序列号追溯", "RoHS合规", "快速换线", "MRP计算"]
        case .equipment:
            ["项目制造", "长周期计划", "BOM多层管理", "现场装配", "售后服务"]
        case .food:
            ["批次追溯", "保质期管理", "配方管理", "食品安全(HACCP)", "冷链物流"]
        case .pharma:
            ["GMP合规", "批记录管理", "效期管理", "电子监管码", "验证管理"]
        case .materials:
            ["配方优化", "质量检测", "批次管理", "环保合规", "能耗管理"]
        case .textile:
            ["色号管理", "排版排料", "外协加工", "快速反应(QR)", "多款少量"]
        case .metal:
            ["模具管理", "表面处理", "多工序流转", "计件工资", "边角料管理"]
        }
    }
}
