#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { MCPStdioClient } from "../../../../plugins/aham-app/skills/aham-survey/scripts/mcp-client.mjs";

const args = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};
const adapter = resolve(value("adapter") ?? "Aham/Resources/aham-survey-mcp.mjs");
const config = resolve(value("config") ?? "");
if (!value("config")) {
  process.stderr.write("用法：mcp-e2e.mjs --config <descriptor> [--adapter <adapter>]\n");
  process.exit(2);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const client = new MCPStdioClient(adapter, config, 15_000);
const call = async (name, parameters = {}, allowError = false) => {
  const result = await client.request("tools/call", { name, arguments: parameters });
  if (result?.isError && !allowError) {
    throw new Error(`${name}: ${result.structuredContent?.code ?? "ERROR"} ${result.structuredContent?.message ?? ""}`);
  }
  return result?.isError ? result : result?.structuredContent?.result;
};

const checks = [];
const pass = (name, detail) => checks.push({ name, ok: true, detail });

try {
  const configMode = (await stat(config)).mode & 0o777;
  assert((configMode & 0o077) === 0, `descriptor 权限过宽：${configMode.toString(8)}`);
  pass("descriptor-permissions", configMode.toString(8));

  const descriptor = JSON.parse(await readFile(config, "utf8"));
  const unauthorized = await fetch(`${descriptor.endpoint}/rpc`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer invalid" },
    body: JSON.stringify({ tool: "get_capabilities", args: {} }),
  });
  assert(unauthorized.status === 401, `错误 Token 应返回 401，实际 ${unauthorized.status}`);
  pass("http-auth-rejection", "401");

  const forbiddenOrigin = await fetch(`${descriptor.endpoint}/rpc`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${descriptor.token}`,
      Origin: "https://untrusted.example",
    },
    body: JSON.stringify({ tool: "get_capabilities", args: {} }),
  });
  assert(forbiddenOrigin.status === 403, `非本机 Origin 应返回 403，实际 ${forbiddenOrigin.status}`);
  pass("http-origin-rejection", "403");

  const initialized = await client.request("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "aham-survey-e2e", version: "1.0.0" },
  });
  assert(initialized.protocolVersion === "2025-06-18", "协议协商失败");
  client.notify("notifications/initialized");
  await client.request("ping");
  pass("initialize-ping", initialized.serverInfo.version);

  const toolList = await client.request("tools/list");
  const names = new Set(toolList.tools.map((tool) => tool.name));
  for (const required of [
    "get_capabilities", "list_departments", "create_project", "list_questions",
    "preview_answer_import", "commit_answer_import", "get_change_log", "undo_change_set",
  ]) assert(names.has(required), `缺少工具 ${required}`);
  assert(names.size === 15, `工具数应为 15，实际 ${names.size}`);
  pass("tools-list", `${names.size} tools`);

  const prompts = await client.request("prompts/list");
  const resources = await client.request("resources/list");
  assert(prompts.prompts.length === 4, "Prompt 数量不正确");
  assert(resources.resources.length === 2, "Resource 数量不正确");
  pass("prompts-resources", `${prompts.prompts.length}/${resources.resources.length}`);

  const capabilities = await call("get_capabilities");
  assert(capabilities.mcpContractVersion === 1, "MCP Contract 不是 v1");
  assert(capabilities.questionCatalogVersion >= 1, "题库版本无效");
  assert(capabilities.localOnly === true, "服务必须标记 localOnly");
  pass("capabilities", `app ${capabilities.app.version}, contract ${capabilities.mcpContractVersion}`);

  const departmentPayload = await call("list_departments");
  const department = departmentPayload.departments.find((item) => item.questions > 0);
  assert(department, "没有可测试的已安装部门");
  pass("department-discovery", `${department.id}:${department.questions}`);

  const createArgs = {
    customer: `E2E 隔离项目 ${Date.now()}`,
    consultant: "Self verification",
    scopes: ["erp"],
    departments: [department.id],
    request_id: `e2e-create-${Date.now()}`,
  };
  const created = await call("create_project", createArgs);
  const replayed = await call("create_project", createArgs);
  const conflictingCreate = await call("create_project", { ...createArgs, customer: "不应重复创建" }, true);
  assert(conflictingCreate.structuredContent?.code === "IDEMPOTENCY_CONFLICT", "不同创建内容复用了 request_id");
  assert(created.id === replayed.id, "create_project 幂等失败");
  pass("create-idempotency", created.id);

  const project = await call("get_project", { project: created.id });
  assert(project.revision >= 1, "项目 revision 无效");
  const search = await call("search_projects", { query: createArgs.customer.slice(0, 6) });
  assert(search.some((item) => item.id === created.id), "search_projects 未返回项目");
  pass("project-read-search", `revision ${project.revision}`);

  const questions = await call("list_questions", { project: created.id, department: department.id });
  const target = questions.find((item) => item.type === "single_choice" && item.options?.length > 0)
    ?? questions.find((item) => item.type === "text");
  assert(target, "题库没有可写测试题");
  const row = target.type === "single_choice"
    ? { department: department.id, question: target.id, options: [target.options[0]], note: "E2E 明确测试答案" }
    : { department: department.id, question: target.id, text: "E2E 明确测试答案" };
  row.evidence = "E2E 来源原文 00:12";
  const invalid = target.type === "single_choice"
    ? await call("preview_answer_import", {
        project: created.id,
        answers: [{ department: department.id, question: target.id, options: ["__非法选项__"] }],
      })
    : null;
  if (invalid) assert(invalid.valid === false && invalid.issues.length > 0, "非法选项未被 preview 拒绝");

  const preview = await call("preview_answer_import", { project: created.id, answers: [row] });
  assert(preview.valid === true && preview.preview_token, "有效答案 preview 失败");
  const commitArgs = {
    project: created.id,
    answers: [row],
    preview_token: preview.preview_token,
    request_id: `e2e-commit-${Date.now()}`,
  };
  const committed = await call("commit_answer_import", commitArgs);
  const replayedCommit = await call("commit_answer_import", commitArgs);
  assert(committed.changeSet === replayedCommit.changeSet, "commit_answer_import 幂等失败");
  pass("preview-commit-idempotency", committed.changeSet);

  const afterQuestions = await call("list_questions", { project: created.id, department: department.id });
  assert(afterQuestions.find((item) => item.id === target.id)?.answered === true, "写入后答案未通过校验");
  const changes = await call("get_change_log", { project: created.id });
  assert(changes.some((item) => item.id === committed.changeSet), "变更日志缺少提交记录");
  const report = await call("export_report", { project: created.id });
  assert(report.markdown.includes(createArgs.customer), "导出报告缺少客户名");
  assert(afterQuestions.find((item) => item.id === target.id)?.evidence === row.evidence, "来源证据未回读");
  assert(report.markdown.includes(row.evidence), "来源证据未进入报告");
  assert(report.markdown.includes("待确认与调研缺口"), "报告缺少调研缺口");
  pass("readback-log-export", `report revision ${report.revision}`);

  const undone = await call("undo_change_set", {
    change_set: committed.changeSet,
    request_id: `e2e-undo-${Date.now()}`,
  });
  assert(undone.undone === true, "撤销失败");
  const undoneQuestions = await call("list_questions", { project: created.id, department: department.id });
  assert(undoneQuestions.find((item) => item.id === target.id)?.answered === false, "撤销后答案仍有效");
  pass("undo-readback", `revision ${undone.revision}`);

  const otherRow = { department: department.id, question: target.id, options: ["__other__"], otherText: "E2E 其他说明", evidence: "E2E 保存证据" };
  const otherPreview = await call("preview_answer_import", { project: created.id, answers: [otherRow] });
  const otherCommit = await call("commit_answer_import", { project: created.id, answers: [otherRow],
    preview_token: otherPreview.preview_token, request_id: `e2e-other-${Date.now()}` });
  const transcriptQuestion = questions.find((item) => item.id !== target.id);
  await call("import_transcript", { project: created.id, department: department.id,
    question: transcriptQuestion.id, text: "E2E 未答题转写", request_id: `e2e-transcript-${Date.now()}` });
  const fullReport = await call("export_report", { project: created.id });
  assert(fullReport.markdown.includes("E2E 其他说明"), "报告遗漏其他说明");
  assert(fullReport.markdown.includes("E2E 未答题转写"), "报告遗漏未答题转写");
  pass("report-preserves-partial-evidence", fullReport.revision);

  await call("upsert_answers", { project: created.id, answers: [{ department: department.id, question: target.id, note: "E2E 后续修改" }] });
  const conflict = await call("undo_change_set", { change_set: otherCommit.changeSet, request_id: `e2e-conflict-${Date.now()}` }, true);
  assert(conflict.structuredContent?.code === "UNDO_CONFLICT", "撤销未保护后续修改");
  const preserved = await call("list_questions", { project: created.id, department: department.id });
  assert(preserved.find((item) => item.id === target.id)?.note === "E2E 后续修改", "冲突撤销覆盖了后续内容");
  pass("undo-conflict-protection", conflict.structuredContent.code);

  const completion = await call("update_project", { project: created.id, fields: { status: "completed" } }, true);
  assert(completion.structuredContent?.code === "INVALID_INPUT", "必答题缺失仍标记完成");
  pass("required-completion-validation", completion.structuredContent.code);

  const current = await call("get_project", { project: created.id });
  await call("update_project", {
    project: created.id,
    expected_revision: current.revision,
    fields: { status: "archived" },
    request_id: `e2e-archive-${Date.now()}`,
  });
  const archivedWrite = await call("upsert_answers", {
    project: created.id,
    answers: [row],
    request_id: `e2e-archived-write-${Date.now()}`,
  }, true);
  assert(archivedWrite.isError === true, "归档项目写入未被拒绝");
  assert(archivedWrite.structuredContent?.code === "PROJECT_ARCHIVED", "归档错误码不正确");
  pass("archive-write-protection", archivedWrite.structuredContent.code);

  process.stdout.write(`${JSON.stringify({ ok: true, checks }, null, 2)}\n`);
} catch (error) {
  process.stderr.write(`${JSON.stringify({ ok: false, message: error.message, checks }, null, 2)}\n`);
  process.exitCode = 1;
} finally {
  client.close();
}
