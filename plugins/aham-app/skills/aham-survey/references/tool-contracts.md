# MCP 工具契约

机器可读 JSON Schema 由 App 随 Adapter 分发的 `mcp-contract.json` 提供，`tools/list` 是运行时事实源。本文件只说明稳定语义，不复制 Schema。

读工具：

- `get_capabilities`：版本、contract、features、工具清单。
- `list_departments`：当前实际安装部门。
- `list_projects`：按状态列项目。
- `search_projects`：名称候选；不会静默模糊命中。
- `get_project`：按 UUID 或唯一精确名称读项目。
- `list_questions`：题型、required、合法选项、答案有效性和顺序。
- `export_report`：生成当前快照的结构化 Markdown/元数据。
- `get_change_log`：读取 MCP 变更及撤销状态。

写工具：

- `create_project`：支持 request_id 幂等。
- `preview_answer_import`：只校验，返回 revision、valid、issues、preview_token。
- `commit_answer_import`：要求相同内容、有效 token 和 request_id，原子提交。
- `upsert_answers`：兼容明确的小批答案；仍做整批校验。
- `import_transcript`：追加原始转写，不增加回答进度。
- `update_project`：字段白名单、expected_revision 和状态门。
- `undo_change_set`：恢复该答案批次的前快照；撤销本身也使用 request_id。

所有写入都应回读。工具调用错误使用结构化 `code/message/retryable/field/details/suggestedAction`；客户端命名空间不是契约的一部分。

