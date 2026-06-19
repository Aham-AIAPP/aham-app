import Foundation

/// 内置问题库清单 (manifest.json 的根结构)
struct QuestionManifest: Codable {
    let departmentFiles: [String]
    let departments: [DepartmentTemplate]
}
