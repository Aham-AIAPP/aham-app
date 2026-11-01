# 客户端安装

推荐从仓库 Skill 根运行：

```sh
node scripts/install-client.mjs --client codex --adapter "/path/aham-survey-mcp.mjs" --config "/path/mcp-connection.json"
```

默认只预演；确认路径后增加 `--apply`。支持 `codex`、`claude`、`claude-desktop`、`vscode`、`cursor`。安装器复制同一份 Skill，并写入或输出对应 MCP 配置；不会读取或复制 descriptor 中的 token。

- Codex：用户 Skill 位于 `~/.agents/skills/aham-survey`；MCP 使用 `codex mcp add`。
- Claude Code：用户 Skill 位于 `~/.claude/skills/aham-survey`；MCP 使用 `claude mcp add-json --scope user`。
- Claude Desktop：合并到 `~/Library/Application Support/Claude/claude_desktop_config.json`；Skill 同步到 `~/.claude/skills/aham-survey`，供 Claude Code / Desktop Code 会话使用。修改后重启 Claude Desktop，并在“+ → Connectors”或开发者设置中确认工具状态。
- VS Code：用户 Skill 位于 `~/.agents/skills/aham-survey`；MCP 可写用户 profile，项目级使用 `.vscode/mcp.json`。
- Cursor：使用 `~/.cursor/mcp.json`；当前 Skill 发现能力不确定时，安装器同时生成最小 `.cursor/rules/aham-survey.mdc` 降级规则。

安装后运行 `node scripts/doctor.mjs ...`。客户端版本变化时以其官方文档和内置 MCP/Skills 页面为准。
