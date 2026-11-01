---
name: aham-survey
description: 使用 Aham Survey macOS App 创建和管理 ERP、MES、WMS、PLM、QMS、APS 调研项目，读取结构化问卷，把访谈证据映射并回写为可追溯答案，检查缺口并导出报告。用户提到现场调研、客户访谈、调研问卷、答案回写、调研进度或调研报告时使用；需要本机已连接的 aham-survey MCP。不要用于普通问卷设计、通用文档排版或与客户调研无关的软件开发。
license: MIT
compatibility: Requires Aham Survey 1.1.0+ for macOS, Node.js 18+, and a local MCP-capable AI client.
metadata:
  author: Aham AIAPP
  version: "1.0.0"
  aham-app-min: "1.1.0"
  aham-mcp-contract: "1"
---

# Aham Survey

通过 `aham-survey` MCP 使用本机 Aham Survey。App 是项目、题库、答案、状态、审计和导出的事实源；不要直接修改 SwiftData 或猜测题号、部门、选项与项目 ID。

## 开始前

1. 找到当前客户端中属于 `aham-survey` 服务的工具；客户端可能给工具名增加命名空间。
2. 首次调用 `get_capabilities`，确认 `mcpContractVersion` 为 `1`、App 满足最低版本且 `answerPreviewCommit`、`idempotentWrites`、`answerUndo` 可用。
3. 调用 `list_departments` 获取本机实际安装的部门，不依据示例假设题库齐全。
4. 若 App 不可达、版本不兼容或连接不是本机，停止写入并按 [故障排查](references/troubleshooting.md) 处理。
5. 永远不读取、显示、转述或记录 MCP Token；连接配置只按路径传给 Adapter。

## 不可违反的事实规则

- 只把用户材料、客户原话或用户明确确认的信息写成客户事实。
- 未知、含糊、冲突内容保持空白、待确认或顾问笔记；建议和追问不是答案。
- 题目 ID、部门 ID、合法选项及题型必须来自 App。单选和多选使用 `list_questions` 返回的选项原文。
- 只有服务端题型校验通过的答案才算完成；note、transcript 和 evidence 单独存在时不增加进度。
- 使用项目 UUID 执行写入。名称只用于 `search_projects` 返回候选，歧义时让用户选择。
- 已归档项目只读。不要调用不存在的删除工具，也不要用状态更新模拟删除。

答案细则见 [答案规则](references/answer-rules.md)，安全与确认矩阵见 [安全规则](references/safety-and-confirmation.md)。

## 标准工作流

### 创建项目

1. 从用户材料提取已知客户、行业、范围、顾问、目标和现有系统，未知字段不补写。
2. 先读 capabilities 和 departments。
3. 用户明确要求创建时，带至少 8 字符且本次操作唯一的 `request_id` 调用 `create_project`；否则先展示摘要并确认。
4. 保存返回 UUID，再用 `get_project` 回读名称、范围、部门和 revision。

### 导入访谈或转写

1. 用 UUID 读取项目，再按部门调用 `list_questions`。
2. 将材料拆成最小证据片段，分别映射为答案、选项、顾问笔记、原始转写或待确认项。
3. 自动映射材料必须先调用 `preview_answer_import`。展示有效项、拒绝项、冲突和证据来源。
4. 用户确认后，以完全相同的 answers、`preview_token` 和唯一 `request_id` 调用 `commit_answer_import`。
5. 回读项目 revision、进度和相关问题。重试沿用原 request_id，不生成新键。

若用户明确要求把一段原文仅追加为转写，可调用 `import_transcript`，仍须携带稳定 `request_id`；转写不等于已回答。

### 现场逐题记录

1. 按 `list_questions` 的顺序逐题进行。
2. 明确的单条答案可用 `upsert_answers`，保留 evidence/source；批量或 AI 映射仍走 preview/commit。
3. 回答不足以满足题型时，只保存 transcript/note 或列为待确认。
4. 每批写入后回读 revision 与 answered 数，不根据本地计算宣称完成。

### 缺口检查

1. 读取项目及已选部门问题。
2. 只把 `required=true` 且 `answered=false` 的问题列为必答缺口；另列无效、冲突和待确认内容。
3. 按部门和主题分组，每轮给少量高价值追问，并将“客户事实”和“AI 建议”分开。

### 更新状态

- 普通资料变更：展示差异，带 `expected_revision` 调用 `update_project`，再回读。
- `completed`：先确认所有必答题有效且用户明确同意完成。
- `archived`：必须得到明确确认；归档后不再写答案。
- revision 冲突时重新读取、重新预览，不覆盖新数据。

### 导出报告

1. 回读项目、revision、部门、进度与缺口。
2. 确认格式和范围后调用 `export_report`。
3. 报告标注快照 revision 和生成时间；“生成成功”不等于客户确认、最终版或已交付。

完整调用顺序见 [工作流](references/workflows.md)，工具语义见 [工具契约](references/tool-contracts.md)。

## 失败恢复

- 结构化错误中的 `code` 是处理依据；不要只匹配中文 message。
- `PROJECT_AMBIGUOUS`：调用 `search_projects`，展示候选并取得 UUID。
- `REVISION_CONFLICT` 或 preview token 失效：重新读取、重新预览、重新确认。
- `ANSWER_*`：重新读取问题与合法选项，不强行改成文本答案。
- `PROJECT_ARCHIVED`：保持只读，除非用户明确要求并允许的状态迁移由 App 支持。
- `APP_UNREACHABLE`：检查 App、连接文件和 Node，不要求用户粘贴 Token。

## 按需读取

- 产品对象与状态：[product-model.md](references/product-model.md)
- 六条完整流程：[workflows.md](references/workflows.md)
- 工具和错误：[tool-contracts.md](references/tool-contracts.md)
- 题型校验：[answer-rules.md](references/answer-rules.md)
- 权限与事实边界：[safety-and-confirmation.md](references/safety-and-confirmation.md)
- 客户端安装：[client-setup.md](references/client-setup.md)
- 兼容范围：[compatibility.md](references/compatibility.md)
