import Testing
import Foundation
@testable import Aham

// MARK: - PromptTemplates 测试

@Suite("PromptTemplates - 项目文档问题重构")
struct PromptTemplatesDocTests {

    @Test("Prompt 包含部门列表")
    func promptContainsDeptList() {
        let depts = [
            DepartmentTemplate(id: "production", name: "生产", icon: "gearshape", defaultSelected: true, description: ""),
            DepartmentTemplate(id: "warehouse", name: "仓储", icon: "archivebox", defaultSelected: false, description: "")
        ]
        let msgs = PromptTemplates.projectDocumentQuestionRebuild(
            docContent: "库存积压严重，手工录入单据",
            customerName: "测试客户",
            departments: depts
        )
        #expect(msgs.count == 2)
        let user = msgs[1].content
        #expect(user.contains("production"))
        #expect(user.contains("warehouse"))
        #expect(user.contains("库存积压"))
    }

    @Test("Prompt system 包含 JSON 格式说明")
    func promptSystemContainsJSONFormat() {
        let msgs = PromptTemplates.projectDocumentQuestionRebuild(
            docContent: "test",
            customerName: "客户A",
            departments: []
        )
        let system = msgs[0].content
        #expect(system.contains("supplements"))
        #expect(system.contains("section"))
    }

    @Test("文档内容超长时被截断")
    func longDocTruncated() {
        let longDoc = String(repeating: "x", count: 20000)
        let msgs = PromptTemplates.projectDocumentQuestionRebuild(
            docContent: longDoc,
            customerName: "客户",
            departments: []
        )
        // user message 应截断到合理长度
        #expect(msgs[1].content.count < 12000)
    }
}

// MARK: - AIProjectEnhancement 模型测试

@Suite("AIProjectEnhancement - importedDocsSummary")
struct AIProjectEnhancementTests {

    @Test("初始化时 importedDocsSummary 为空")
    func defaultImportedDocsSummaryEmpty() {
        let e = AIProjectEnhancement()
        #expect(e.importedDocsSummary.isEmpty)
    }

    @Test("追加文档记录")
    func appendDocSummary() {
        var e = AIProjectEnhancement()
        e.importedDocsSummary.append("需求说明书.docx")
        e.importedDocsSummary.append("组织架构.xlsx")
        #expect(e.importedDocsSummary.count == 2)
        #expect(e.importedDocsSummary.first == "需求说明书.docx")
    }

    @Test("Codable 序列化含新字段")
    func codableRoundTrip() throws {
        var e = AIProjectEnhancement()
        e.importedDocsSummary = ["doc1.pdf", "report.docx"]
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(AIProjectEnhancement.self, from: data)
        #expect(decoded.importedDocsSummary == ["doc1.pdf", "report.docx"])
    }
}

// MARK: - ProjectDocumentAnalyzer 解析测试

@Suite("ProjectDocumentAnalyzer - parseDocQuestion")
struct ProjectDocumentAnalyzerParseTests {

    /// 模拟 LLM 返回的合法 JSON 能被正确解析为 AIGeneratedQuestion
    @Test("合法 JSON 解析为 AIGeneratedQuestion")
    func parseValidJSON() throws {
        let json = """
        {
          "supplements": {
            "production": [
              {
                "id": "doc_production_001",
                "departmentId": "production",
                "section": "painpoint",
                "text": "当前工单下达到生产开始的平均等待时长是多少？",
                "type": "text",
                "options": [],
                "reason": "文档提及交期问题频繁"
              }
            ]
          }
        }
        """
        let analyzer = ProjectDocumentAnalyzer()
        let result = analyzer.parseDocQuestions(from: json)
        #expect(result.count == 1)
        let q = try #require(result.first)
        #expect(q.id == "doc_production_001")
        #expect(q.departmentId == "production")
        #expect(q.section == "painpoint")
        #expect(!q.text.isEmpty)
    }

    @Test("多部门 JSON 均被解析")
    func parseMultipleDepts() throws {
        let json = """
        {
          "supplements": {
            "production": [{"id":"doc_production_001","departmentId":"production","section":"painpoint","text":"Q1","type":"text","options":[],"reason":"r"}],
            "warehouse":  [{"id":"doc_warehouse_001","departmentId":"warehouse","section":"process","text":"Q2","type":"text","options":[],"reason":"r"}]
          }
        }
        """
        let analyzer = ProjectDocumentAnalyzer()
        let result = analyzer.parseDocQuestions(from: json)
        #expect(result.count == 2)
        let depts = Set(result.map(\.departmentId))
        #expect(depts.contains("production"))
        #expect(depts.contains("warehouse"))
    }

    @Test("格式错误 JSON 返回空数组")
    func parseMalformedJSON() {
        let analyzer = ProjectDocumentAnalyzer()
        let result = analyzer.parseDocQuestions(from: "not json at all")
        #expect(result.isEmpty)
    }

    @Test("缺少必填字段的条目被跳过")
    func parseMissingFields() {
        let json = """
        {
          "supplements": {
            "production": [
              {"id":"doc_production_001"},
              {"id":"doc_production_002","departmentId":"production","section":"painpoint","text":"完整问题","type":"text","options":[],"reason":"r"}
            ]
          }
        }
        """
        let analyzer = ProjectDocumentAnalyzer()
        let result = analyzer.parseDocQuestions(from: json)
        // 第一条缺字段被跳过，第二条保留
        #expect(result.count == 1)
    }
}
