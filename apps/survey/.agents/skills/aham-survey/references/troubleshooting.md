# 故障排查

1. App 未连接：启动 Aham Survey，确认首页 MCP 状态为运行；不要手工编辑端口或 token。
2. descriptor 不存在：让 App 重新启动 MCP 服务；检查路径和权限应为仅当前用户可读。
3. Node 不可用：安装 Node.js 18+，再执行 `node --check`。
4. initialize 失败：核对 Adapter 与同目录 `mcp-contract.json`，重新复制完整资源。
5. 鉴权失败：在 App 中明确确认后轮换 Token，再让客户端重启连接；不要粘贴 token 排查。
6. contract 不兼容：允许只读诊断，升级 App/Skill 后再写入。
7. 项目歧义：调用 `search_projects` 并选 UUID。
8. revision/preview 冲突：回读、重新映射、重新 preview 和确认。

使用 `doctor.mjs` 只输出脱敏结果；`verify-connection.mjs` 执行 initialize、tools/list、ping 和 get_capabilities，不写项目。

