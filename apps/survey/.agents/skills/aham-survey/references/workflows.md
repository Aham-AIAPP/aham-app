# 标准工作流

## 连接预检

`get_capabilities` → `list_departments`。核对 contract、features、App 与题库版本。只读诊断失败时不得继续写入。

## 创建项目

整理已知事实 → 列出合法部门 → 用户已明确要求创建或确认摘要 → `create_project(request_id)` → `get_project(UUID)` 回读。

## 访谈映射

`get_project` → `list_questions` → 拆分证据 → 映射合法题号/选项 → `preview_answer_import` → 展示预览 → 用户确认 → `commit_answer_import(request_id, preview_token)` → 回读。

同一批内容、同一语义重试必须沿用 request_id。改变内容则重新 preview，并生成新的 request_id。

## 现场记录

按 App 题序提问。明确答案可以小批 `upsert_answers`；模糊原话写 transcript/note。每批回读 revision 和校验结果。

## 缺口与追问

读取全部已选部门问题，按 required/answered、部门、主题归组。优先输出少量能影响范围、报价、集成或实施风险的问题。不要把建议写回答案。

## 状态更新

先取 revision，展示字段差异，再调用 `update_project(expected_revision)`。完成与归档需要明确确认；冲突后重新读取。

## 报告

回读快照 → 明确范围/格式 → `export_report` → 报告 revision、缺口、生成时间和路径/Markdown。质量状态不得超过证据：生成不代表客户认可。

