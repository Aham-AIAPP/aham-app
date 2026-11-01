# 兼容范围

V1 是本机方案：AI 客户端、Adapter 与 Aham Survey 在同一台 Mac 上。ChatGPT Web、Claude.ai 或远程 Agent 不能直接调用 localhost，除非未来独立实现经明确授权的安全中继。

基线：macOS App 1.1.0+、MCP contract 1、question catalog 1、Skill 1.0.0、Node.js 18+。Adapter 支持 stdio JSON-RPC、tools、prompts、resources 与 ping；内部 HTTP 只监听 loopback。

Codex、Claude Code 和 VS Code 使用原生 Skill + stdio MCP。Claude Desktop 可通过本机 `claude_desktop_config.json` 接入 stdio MCP；Skill 供 Claude Code / Desktop Code 会话发现，普通 Claude Desktop 对话是否发现 Skill 取决于客户端版本。Cursor 至少支持 MCP；如果当前版本不发现 Agent Skill，则用 Rules 薄壳降级。每次发布都要重跑发现、initialize、工具清单和只读 smoke test，不能把旧版结果当成当前证据。
