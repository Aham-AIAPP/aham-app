import SwiftData
import XCTest
@testable import Aham_Survey

@MainActor
final class MCPToolsIntegrationTests: XCTestCase {
    private var container: ModelContainer!

    func testPreviewCommitIdempotencyAndUndo() throws {
        let tools = try makeTools()
        let create = try dictionary(tools.call("create_project", args: [
            "customer": "MCP 集成测试",
            "consultant": "XCTest",
            "industry": "equipment",
            "scopes": ["erp"],
            "departments": ["procurement"],
            "request_id": "create-integration-001"
        ]))
        let projectId = try XCTUnwrap(create["id"] as? String)

        let replay = try dictionary(tools.call("create_project", args: [
            "customer": "此名称不应再创建",
            "departments": ["procurement"],
            "request_id": "create-integration-001"
        ]))
        XCTAssertEqual(replay["id"] as? String, projectId)

        let invalidRows: [[String: Any]] = [[
            "department": "procurement",
            "question": "PUR_003",
            "text": "50家以下，活跃率>80%"
        ]]
        let invalidPreview = try dictionary(tools.call("preview_answer_import", args: [
            "project": projectId,
            "answers": invalidRows
        ]))
        XCTAssertEqual(invalidPreview["valid"] as? Bool, false)

        let validRows: [[String: Any]] = [[
            "department": "procurement",
            "question": "PUR_003",
            "options": ["50家以下，活跃率>80%"],
            "evidence": "客户明确表示目前不足 50 家"
        ]]
        let preview = try dictionary(tools.call("preview_answer_import", args: [
            "project": projectId,
            "answers": validRows
        ]))
        XCTAssertEqual(preview["valid"] as? Bool, true)
        let previewToken = try XCTUnwrap(preview["preview_token"] as? String)

        let commitArgs: [String: Any] = [
            "project": projectId,
            "answers": validRows,
            "preview_token": previewToken,
            "request_id": "commit-integration-001"
        ]
        let committed = try dictionary(tools.call("commit_answer_import", args: commitArgs))
        XCTAssertEqual(committed["answered"] as? Int, 1)
        let changeSet = try XCTUnwrap(committed["changeSet"] as? String)

        let repeated = try dictionary(tools.call("commit_answer_import", args: commitArgs))
        XCTAssertEqual(repeated["changeSet"] as? String, changeSet)
        XCTAssertEqual(repeated["revision"] as? Int, committed["revision"] as? Int)

        let questions = try array(tools.call("list_questions", args: [
            "project": projectId,
            "department": "procurement"
        ]))
        let answered = try XCTUnwrap(questions.first { ($0["id"] as? String) == "PUR_003" })
        XCTAssertEqual(answered["answered"] as? Bool, true)

        let undone = try dictionary(tools.call("undo_change_set", args: [
            "change_set": changeSet,
            "request_id": "undo-integration-001"
        ]))
        XCTAssertEqual(undone["undone"] as? Bool, true)
        XCTAssertEqual(undone["answered"] as? Int, 0)
    }

    func testArchivedProjectRejectsAnswerWrite() throws {
        let tools = try makeTools()
        let create = try dictionary(tools.call("create_project", args: [
            "customer": "归档写保护测试",
            "scopes": ["erp"],
            "departments": ["procurement"]
        ]))
        let projectId = try XCTUnwrap(create["id"] as? String)
        _ = try tools.call("update_project", args: [
            "project": projectId,
            "fields": ["status": "archived"]
        ])

        XCTAssertThrowsError(try tools.call("upsert_answers", args: [
            "project": projectId,
            "answers": [[
                "department": "procurement",
                "question": "PUR_003",
                "options": ["50家以下，活跃率>80%"]
            ]]
        ]))
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeTools() throws -> MCPTools {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self,
            Answer.self,
            MemoItem.self,
            AdoptedFollowup.self,
            MCPChangeSet.self,
            configurations: configuration
        )
        return MCPTools(context: container.mainContext, pluginLoader: PluginLoader())
    }

    private func dictionary(_ value: Any) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any])
    }

    private func array(_ value: Any) throws -> [[String: Any]] {
        try XCTUnwrap(value as? [[String: Any]])
    }
}
