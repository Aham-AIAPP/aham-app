import AppKit
import SwiftData
import XCTest
@testable import Aham_Survey

@MainActor
final class WriteIntegrityTests: XCTestCase {
    struct Fixture {
        let container: ModelContainer
        let loader = PluginLoader()
        let project: Project
        var context: ModelContext { container.mainContext }
        var tools: MCPTools { MCPTools(context: context, pluginLoader: loader) }
        var survey: SurveyService { SurveyService(context: context, pluginLoader: loader) }
        var projects: ProjectService { ProjectService(context: context, pluginLoader: loader) }
        var exporter: ExportService { ExportService(context: context, pluginLoader: loader) }
        var id: String { project.id.uuidString }

        init() throws {
            container = try ModelContainer(for: Project.self, Answer.self, MemoItem.self,
                                           AdoptedFollowup.self, MCPChangeSet.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            project = try ProjectService(context: container.mainContext, pluginLoader: loader)
                .create(.init(customerName: "完整性测试", departmentIds: ["procurement"]))
        }

        func rows(question: String = "PUR_003", evidence: String = "访谈 00:12 客户明确说明") -> [[String: Any]] {
            [["department": "procurement", "question": question,
              "options": ["__other__"], "otherText": "供应商约 60 家", "evidence": evidence]]
        }
        func call(_ tool: String, _ args: [String: Any]) throws -> [String: Any] {
            let result = try tools.call(tool, args: args)
            return try XCTUnwrap(result as? [String: Any])
        }
        func commit(_ rows: [[String: Any]], request: String = UUID().uuidString) throws -> [String: Any] {
            let preview = try call("preview_answer_import", ["project": id, "answers": rows])
            return try call("commit_answer_import", ["project": id, "answers": rows,
                "preview_token": XCTUnwrap(preview["preview_token"]), "request_id": request])
        }
        func answer(_ question: String = "PUR_003") throws -> Answer {
            try XCTUnwrap(survey.answers(for: project).first { $0.questionId == question })
        }
    }

    func assertCode(_ code: String, _ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual((error as? MCPStructuredError)?.payload["code"] as? String, code, file: file, line: line)
        }
    }

    func testEvidenceRoundTripAndUndoRestorePreviousEvidence() throws {
        let f = try Fixture()
        _ = try f.commit(f.rows(evidence: "原始证据"))
        let change = try f.commit(f.rows(evidence: "补充证据"))
        let rows = try XCTUnwrap(f.tools.call("list_questions", args: ["project": f.id, "department": "procurement"]) as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == "PUR_003" })
        XCTAssertEqual(row["evidence"] as? String, "补充证据")
        XCTAssertEqual(row["otherText"] as? String, "供应商约 60 家")
        _ = try f.call("undo_change_set", ["change_set": XCTUnwrap(change["changeSet"]), "request_id": UUID().uuidString])
        XCTAssertEqual(try f.answer().evidence, "原始证据")
    }

    func testUIEditInvalidatesPreviewAndUpdatesProgressImmediately() throws {
        let f = try Fixture()
        try f.survey.prepareAnswers(for: f.project)
        let preview = try f.call("preview_answer_import", ["project": f.id, "answers": f.rows()])
        let before = f.project.revision
        try f.survey.editAnswer(f.answer(), in: f.project) {
            $0.selectedOptions = ["__other__"]; $0.otherText = "现场回答"
        }
        XCTAssertEqual(f.project.revision, before + 1)
        XCTAssertEqual(f.project.answeredQuestions, 1)
        assertCode("PREVIEW_STALE") {
            _ = try f.call("commit_answer_import", ["project": f.id, "answers": f.rows(),
                "preview_token": XCTUnwrap(preview["preview_token"]), "request_id": UUID().uuidString])
        }
        XCTAssertEqual(try f.answer().otherText, "现场回答")
    }

    func testUndoRejectsLaterUIEditsEvenWhenValueChangedBack() throws {
        let f = try Fixture()
        let result = try f.commit(f.rows())
        let answer = try f.answer()
        try f.survey.editAnswer(answer, in: f.project) { $0.noteText = "后续修改" }
        try f.survey.editAnswer(answer, in: f.project) { $0.noteText = "" }
        let revision = f.project.revision
        assertCode("UNDO_CONFLICT") {
            _ = try f.call("undo_change_set", ["change_set": XCTUnwrap(result["changeSet"]), "request_id": UUID().uuidString])
        }
        XCTAssertEqual(f.project.revision, revision)
        XCTAssertEqual(answer.otherText, "供应商约 60 家")
        XCTAssertNil(try f.context.fetch(FetchDescriptor<MCPChangeSet>()).first?.undoneAt)
    }

    func testUndoAllowsUnrelatedProjectEditAndIsIdempotent() throws {
        let f = try Fixture()
        let result = try f.commit(f.rows())
        try f.projects.update(f.project, fields: ["surveyGoal": "保留后续项目修改"])
        let args: [String: Any] = ["change_set": try XCTUnwrap(result["changeSet"]), "request_id": UUID().uuidString]
        let first = try f.call("undo_change_set", args)
        let retry = try f.call("undo_change_set", args)
        XCTAssertEqual(first["revision"] as? Int, retry["revision"] as? Int)
        XCTAssertEqual(f.project.surveyGoal, "保留后续项目修改")
        XCTAssertEqual(f.project.answeredQuestions, 0)
    }

    func testConflictingIdempotencyPayloadIsRejectedForSameTool() throws {
        let f = try Fixture()
        let args: [String: Any] = ["project": f.id, "answers": f.rows(), "request_id": "same-request-001"]
        _ = try f.call("upsert_answers", args)
        let revision = f.project.revision
        _ = try f.call("upsert_answers", args)
        XCTAssertEqual(f.project.revision, revision)
        var changed = args; changed["answers"] = f.rows(evidence: "不同内容")
        assertCode("IDEMPOTENCY_CONFLICT") { _ = try f.call("upsert_answers", changed) }
        XCTAssertEqual(try f.answer().evidence, "访谈 00:12 客户明确说明")
    }

    func testLegacyChangeCannotReplayOrUndoWithoutVerificationData() throws {
        let f = try Fixture()
        let legacy = MCPChangeSet(requestId: "legacy-request-001", projectId: f.project.id, tool: "upsert_answers",
                                  resultJSON: Data("{}".utf8))
        f.context.insert(legacy); try f.context.save()
        assertCode("IDEMPOTENCY_CONFLICT") {
            _ = try f.call("upsert_answers", ["project": f.id, "answers": f.rows(), "request_id": legacy.requestId])
        }
        assertCode("UNDO_CONFLICT") {
            _ = try f.call("undo_change_set", ["change_set": legacy.id.uuidString, "request_id": UUID().uuidString])
        }
    }

    func testCompletionAndArchiveRulesAreSharedByUIAndMCP() throws {
        let f = try Fixture()
        assertCode("INVALID_INPUT") { try f.projects.update(f.project, fields: ["status": "completed"]) }
        assertCode("INVALID_INPUT") {
            _ = try f.call("update_project", ["project": f.id, "fields": ["status": "completed"]])
        }
        try f.survey.prepareAnswers(for: f.project)
        let answer = try f.answer()
        try f.projects.update(f.project, fields: ["status": "archived"])
        let revision = f.project.revision
        assertCode("PROJECT_ARCHIVED") { try f.survey.editAnswer(answer, in: f.project) { $0.noteText = "不能写入" } }
        assertCode("PROJECT_ARCHIVED") { try f.projects.update(f.project, fields: ["productInfo": "不能写入"]) }
        assertCode("PROJECT_ARCHIVED") { try f.survey.addMemo("不能写入", category: .needs, to: f.project) }
        XCTAssertEqual(f.project.revision, revision)
        XCTAssertTrue(answer.noteText.isEmpty)
        _ = try f.call("update_project", ["project": f.id, "fields": ["status": "inProgress"]])
        XCTAssertEqual(f.project.status, .inProgress)
    }

    func testInvalidBatchAndDuplicateTargetsWriteNothing() throws {
        let f = try Fixture()
        let revision = f.project.revision
        let duplicate = f.rows() + f.rows(evidence: "重复目标")
        assertCode("ANSWER_VALIDATION_FAILED") { _ = try f.call("upsert_answers", ["project": f.id, "answers": duplicate]) }
        let mixed = f.rows() + [["department": "procurement", "question": "missing", "text": "不存在"]]
        assertCode("ANSWER_VALIDATION_FAILED") { _ = try f.call("upsert_answers", ["project": f.id, "answers": mixed]) }
        XCTAssertTrue(f.survey.answers(for: f.project).isEmpty)
        XCTAssertEqual(f.project.revision, revision)
    }

    func testEvidenceOnlyWriteIsStoredButNotCountedAsAnswer() throws {
        let f = try Fixture()
        _ = try f.call("upsert_answers", ["project": f.id, "answers": [[
            "department": "procurement", "question": "PUR_003", "evidence": "等待客户补充数字"
        ]]])
        XCTAssertEqual(try f.answer().evidence, "等待客户补充数字")
        XCTAssertEqual(f.project.answeredQuestions, 0)
    }

    func testMalformedEvidenceAndProjectFieldsAreRejected() throws {
        let f = try Fixture()
        var rows = f.rows(); rows[0]["evidence"] = 123
        assertCode("INVALID_INPUT") { _ = try f.call("upsert_answers", ["project": f.id, "answers": rows]) }
        assertCode("INVALID_INPUT") { _ = try f.call("update_project", ["project": f.id, "fields": ["headcount": 100]]) }
        XCTAssertTrue(f.survey.answers(for: f.project).isEmpty)
    }

    func testFollowupProgressAndDraftValidationUseOneQuestionSet() throws {
        let f = try Fixture()
        let followup = AdoptedFollowup(id: "followup-test", projectId: f.project.id, departmentId: "procurement",
            parentQuestionId: "PUR_003", topic: "数量", questionText: "实际数量？", type: .number,
            options: [], hint: "", order: 0)
        let answer = try f.survey.adoptFollowup(followup, into: f.project)
        XCTAssertEqual(f.project.totalQuestions, 35)
        try f.survey.editAnswer(answer, in: f.project) { $0.textValue = "待确认" }
        XCTAssertEqual(f.project.answeredQuestions, 0)
        assertCode("ANSWER_VALIDATION_FAILED") {
            _ = try f.call("upsert_answers", ["project": f.id, "answers": [[
                "department": "procurement", "question": followup.id, "text": "仍未确认"
            ]]])
        }
        try f.survey.editAnswer(answer, in: f.project) { $0.textValue = "60" }
        XCTAssertEqual(f.project.answeredQuestions, 1)
        let snapshot = f.exporter.snapshot(for: f.project)
        XCTAssertEqual(snapshot.totalQuestions, 35)
        XCTAssertEqual(snapshot.answeredQuestions, 1)
        let project = try f.call("get_project", ["project": f.id])
        XCTAssertEqual(project["total"] as? Int, 35)
    }

    func testAsyncAIResultCannotOverwriteEditedOrArchivedAnswer() throws {
        let f = try Fixture()
        _ = try f.commit(f.rows())
        let answer = try f.answer(); let revision = answer.revision
        try f.survey.editAnswer(answer, in: f.project) { $0.noteText = "用户新笔记" }
        assertCode("REVISION_CONFLICT") {
            try f.survey.editAnswer(answer, in: f.project, expectedRevision: revision) { $0.polishedText = "过期 AI 结果" }
        }
        XCTAssertTrue(answer.polishedText.isEmpty)
    }

    func testReportIncludesOtherEvidenceNotesTranscriptAndGaps() throws {
        let f = try Fixture()
        _ = try f.commit(f.rows())
        try f.projects.update(f.project, fields: ["productInfo": "客户产品工艺信息"])
        _ = try f.call("upsert_answers", ["project": f.id, "answers": [[
            "department": "procurement", "question": "PUR_004", "note": "仅笔记也必须导出"
        ]]])
        _ = try f.call("import_transcript", ["project": f.id, "department": "procurement", "question": "PUR_005", "text": "仅转写也必须导出"])
        let markdown = f.exporter.markdown(for: f.project)
        for expected in ["供应商约 60 家", "访谈 00:12", "仅笔记也必须导出", "仅转写也必须导出", "待确认与调研缺口", "尚未形成有效答案", "客户产品工艺信息"] {
            XCTAssertTrue(markdown.contains(expected), expected)
        }
        XCTAssertFalse(markdown.contains("__other__"))
        XCTAssertEqual(f.project.answeredQuestions, 1)
        var config = ExportConfig.default; config.includeNotes = false; config.includeVoice = false
        let filtered = f.exporter.markdown(for: f.project, config: config)
        XCTAssertFalse(filtered.contains("仅笔记也必须导出"))
        XCTAssertFalse(filtered.contains("仅转写也必须导出"))
        XCTAssertTrue(filtered.contains("访谈 00:12"))
    }

    func testCompletedProjectReturnsToInProgressWhenRequiredAnswerIsCleared() throws {
        let f = try Fixture()
        let rows: [[String: Any]] = f.loader.questions(for: "procurement").filter(\.required).map { question in
            var row: [String: Any] = ["department": "procurement", "question": question.id]
            if let option = question.options?.first { row["options"] = [option] }
            else { row["text"] = question.type == .number ? "1" : "明确回答" }
            return row
        }
        _ = try f.call("upsert_answers", ["project": f.id, "answers": rows])
        try f.projects.update(f.project, fields: ["status": "completed"])
        XCTAssertEqual(f.project.status, .completed)
        try f.survey.editAnswer(f.answer(), in: f.project) { $0.selectedOptions = []; $0.textValue = "" }
        XCTAssertEqual(f.project.status, .inProgress)
        XCTAssertFalse(f.projects.missingRequiredQuestions(f.project).isEmpty)
    }

    func testMemoWritesInvalidatePreviewAndArchivedRemovalIsRejected() throws {
        let f = try Fixture()
        let revision = f.project.revision
        try f.survey.addMemo("明确需求", category: .needs, to: f.project)
        XCTAssertEqual(f.project.revision, revision + 1)
        let memo = try XCTUnwrap(f.survey.memoItems(for: f.project).first)
        try f.projects.update(f.project, fields: ["status": "archived"])
        assertCode("PROJECT_ARCHIVED") { try f.survey.deleteMemo(memo, from: f.project) }
        XCTAssertEqual(f.survey.memoItems(for: f.project).count, 1)
        try f.projects.update(f.project, fields: ["status": "inProgress"])
        try f.survey.deleteMemo(memo, from: f.project)
        XCTAssertTrue(f.survey.memoItems(for: f.project).isEmpty)
    }

    func testTranscriptUndoAndProjectDeletionCleanUpChangeRecords() throws {
        let f = try Fixture()
        _ = try f.commit(f.rows())
        _ = try f.call("import_transcript", ["project": f.id, "department": "procurement", "question": "PUR_003",
            "text": "待撤销转写", "request_id": "transcript-undo-test"])
        let change = try XCTUnwrap(f.context.fetch(FetchDescriptor<MCPChangeSet>()).first { $0.requestId == "transcript-undo-test" })
        _ = try f.call("undo_change_set", ["change_set": change.id.uuidString, "request_id": UUID().uuidString])
        XCTAssertTrue(try f.answer().voiceTranscript.isEmpty)
        XCTAssertFalse(try f.answer().evidence.isEmpty)
        try f.projects.delete(f.project)
        XCTAssertTrue(try f.context.fetch(FetchDescriptor<MCPChangeSet>()).isEmpty)
        XCTAssertTrue(try f.context.fetch(FetchDescriptor<Answer>()).isEmpty)
    }

    func testDOCXContainsEvidenceAndUnansweredNotes() async throws {
        let f = try Fixture()
        _ = try f.commit(f.rows(evidence: "DOCX 来源证据"))
        _ = try f.call("upsert_answers", ["project": f.id, "answers": [[
            "department": "procurement", "question": "PUR_004", "note": "DOCX 未答题笔记"
        ]]])
        let generated = await MarkdownExporter.exportProjectAsDOCX(snapshot: f.exporter.snapshot(for: f.project), config: .default)
        let data = try XCTUnwrap(generated)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b])
        let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil).string
        for expected in ["DOCX 来源证据", "DOCX 未答题笔记", "供应商约 60 家", "待确认与调研缺口"] {
            XCTAssertTrue(text.contains(expected), expected)
        }
    }
}
