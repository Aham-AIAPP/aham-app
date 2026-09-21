import Foundation
import SwiftData

/// 一次可追溯的 MCP 写入。当前撤销能力聚焦答案批次；其他工具仍记录结果用于幂等回放。
@Model
final class MCPChangeSet {
    var id: UUID
    @Attribute(.unique) var requestId: String
    var projectId: UUID
    var tool: String
    var createdAt: Date
    var beforeJSON: Data
    var afterJSON: Data
    var resultJSON: Data
    var undoneAt: Date?

    init(
        requestId: String,
        projectId: UUID,
        tool: String,
        beforeJSON: Data = Data(),
        afterJSON: Data = Data(),
        resultJSON: Data = Data()
    ) {
        id = UUID()
        self.requestId = requestId
        self.projectId = projectId
        self.tool = tool
        createdAt = .now
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.resultJSON = resultJSON
        undoneAt = nil
    }
}
