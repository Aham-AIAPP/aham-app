#!/usr/bin/env python3
"""Create a synthetic store with the pre-fix schema, migrate and reopen it.

Run from any directory: python3 Tests/Integration/storage-migration.py
No installed App or customer database is accessed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "b7841bd79f964129b90ea6c3994c98b264b0c615"
MODELS = ["Project", "Answer", "MemoItem", "AdoptedFollowup", "MCPChangeSet",
          "Industry", "SurveyScope", "QuestionTemplate"]
COMMON = '''import Foundation
import SwiftData
// Raw values match the UI enum; presentation properties are not part of the schema.
enum MemoCategory: String { case forms, metrics, approvals, needs }
@main struct StorageProbe {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: Project.self, Answer.self, MemoItem.self,
            AdoptedFollowup.self, MCPChangeSet.self,
            configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
        let context = container.mainContext
        BODY
        print("storage probe passed")
    }
}
'''
SEED = '''
        let project = Project(name: "旧项目", customerName: "迁移测试客户")
        project.selectedDepartmentIds = ["procurement"]
        context.insert(project)
        let answer = Answer(projectId: project.id, departmentId: "procurement", questionId: "PUR_003")
        answer.selectedOptions = ["__other__"]
        answer.otherText = "旧版其他说明"
        answer.noteText = "旧版顾问笔记"
        answer.voiceTranscript = "旧版访谈转写"
        context.insert(answer)
        context.insert(MemoItem(projectId: project.id, category: .needs, text: "旧版备忘"))
        context.insert(AdoptedFollowup(id: "followup-migration", projectId: project.id,
            departmentId: "procurement", parentQuestionId: "PUR_003", topic: "追问",
            questionText: "旧版追问", type: .text, options: [], hint: "", order: 0))
        context.insert(MCPChangeSet(requestId: "legacy-migration", projectId: project.id,
            tool: "upsert_answers", resultJSON: Data("{}".utf8)))
        try context.save()
'''
VERIFY = '''
        let projects = try context.fetch(FetchDescriptor<Project>())
        let answers = try context.fetch(FetchDescriptor<Answer>())
        let changes = try context.fetch(FetchDescriptor<MCPChangeSet>())
        precondition(projects.count == 1 && projects[0].customerName == "迁移测试客户")
        precondition(answers.count == 1 && answers[0].otherText == "旧版其他说明")
        precondition(answers[0].noteText == "旧版顾问笔记" && answers[0].voiceTranscript == "旧版访谈转写")
        precondition(changes.count == 1 && changes[0].requestFingerprint == "")
        precondition(try context.fetch(FetchDescriptor<MemoItem>()).count == 1)
        precondition(try context.fetch(FetchDescriptor<AdoptedFollowup>()).count == 1)
        if CommandLine.arguments.count == 2 {
            precondition(answers[0].evidence == "" && answers[0].revision == 0)
            answers[0].evidence = "迁移后新增证据"
            answers[0].revision = 1
            try context.save()
        } else {
            precondition(answers[0].evidence == "迁移后新增证据" && answers[0].revision == 1)
        }
'''
# Throwing fetches must be evaluated outside precondition's nonthrowing autoclosure.
VERIFY = VERIFY.replace('precondition(try context.fetch(FetchDescriptor<MemoItem>()).count == 1)',
                        'let memos = try context.fetch(FetchDescriptor<MemoItem>()); precondition(memos.count == 1)')
VERIFY = VERIFY.replace('precondition(try context.fetch(FetchDescriptor<AdoptedFollowup>()).count == 1)',
                        'let followups = try context.fetch(FetchDescriptor<AdoptedFollowup>()); precondition(followups.count == 1)')

def run(args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)

with tempfile.TemporaryDirectory(prefix="aham-storage-migration-") as directory:
    work = Path(directory)
    for stage, body in [("legacy", SEED), ("current", VERIFY)]:
        sources = work / stage
        sources.mkdir()
        for model in MODELS:
            path = f"Aham/Models/{model}.swift"
            text = (subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT, text=True)
                    if stage == "legacy" else (ROOT / path).read_text())
            (sources / f"{model}.swift").write_text(text)
        (sources / "Probe.swift").write_text(COMMON.replace("BODY", body))
        run(["xcrun", "swiftc", "-parse-as-library", "-module-name", "AhamStorageProbe",
             *map(str, sorted(sources.glob("*.swift"))), "-o", str(work / stage / "probe")])
        run([str(work / stage / "probe"), str(work / "survey.store")])
    run([str(work / "current/probe"), str(work / "survey.store"), "reopen"])
print("PASS: legacy schema migration preserves all five models; new evidence survives reopen")
