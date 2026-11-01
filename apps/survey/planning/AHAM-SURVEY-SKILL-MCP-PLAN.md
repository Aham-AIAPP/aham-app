# Aham Survey · Agent Skill + MCP 完整规划

> 状态：规划稿，不包含实现。  
> 日期：2026-08-11  
> 目标：让 Codex、Claude、VS Code Copilot、Cursor 等本地 AI 工具通过统一 Skill 理解调研工作流，并经 MCP 安全调用 Aham Survey.app。

## 1. 结论先行

Aham Survey 应采用“一个业务 Skill、一个稳定 MCP 能力层、多种客户端安装壳”的架构，而不是为每个 AI 工具分别写一套业务逻辑。

- **Agent Skill**：告诉 AI 什么时候使用 Aham Survey、怎样规划调研、按什么顺序调用工具、哪些事实不能臆测、哪些写入需要确认。
- **MCP Server / Adapter**：负责真实读写 App，不承载大段业务方法论。
- **Aham Survey.app**：保持本地事实源，负责题库、SwiftData、状态、校验、审计、现场 UI 与导出。
- **客户端安装壳**：只处理不同 AI 工具的 Skill 目录和 MCP 配置差异，不复制业务规则。

推荐 Skill 名称：`aham-survey`。MCP 服务名称也保持 `aham-survey`，让用户和模型只记一个名字。

## 2. 对现有软件的理解

### 2.1 产品定位

Aham Survey 是 macOS 本地优先的结构化现场调研终端，面向 ERP、MES、WMS、PLM、QMS、APS 等售前或实施调研。

它的职责边界应保持清晰：

- AI 负责理解用户意图、整理客户资料、把访谈证据映射到题目、发现缺口并组织下一步。
- App 负责项目、题库、答案、状态、进度、触发规则、持久化和导出。
- App 不应把模型推理结果直接当成客户事实；AI 不应绕过 App 直接修改 SwiftData。

### 2.2 当前数据与能力

当前 App 使用 SwiftData 保存：

- Project：客户、顾问、行业、调研范围、部门、状态、进度。
- Answer：选项、文本、顾问笔记、润色文本、转写和回答状态。
- MemoItem、AdoptedFollowup：现场备忘和采纳的追问。
- 内置 JSON 题库：目前对外示例只包含采购部 34 道题。

当前 MCP 暴露 8 个工具：

1. `list_projects`
2. `get_project`
3. `list_questions`
4. `export_report`
5. `create_project`
6. `upsert_answers`
7. `import_transcript`
8. `update_project`

当前链路是：

```text
AI 客户端
  └─ stdio JSON-RPC
      └─ aham-survey-mcp.mjs（Node 18+）
          └─ POST http://127.0.0.1:<动态端口>/rpc
              └─ Aham Survey.app
                  └─ SwiftData + 内置题库 + 导出服务
```

当前方案已经能跑通，但 App 内 HTTP 不是标准 MCP Streamable HTTP；标准 MCP 生命周期和工具清单由 Node 适配器实现。

## 3. 设计原则

### 3.1 单一事实源

- 工具名称、JSON Schema、枚举、错误码和读写属性必须来自一份机器可读契约。
- Swift 端、MCP 适配器、Skill 参考文档和 App 首页不得各自手写一份工具定义。
- 题目 ID、部门 ID、项目 ID 由 App 返回，AI 不猜测。

### 3.2 Skill 与连接配置分离

- Skill 可以公开、版本控制和跨客户端复制。
- MCP Token、动态端口、客户数据和 API Key 不得进入 Skill、仓库、命令行参数或日志。
- Skill 缺失不应导致 MCP 工具不可用；MCP 工具描述要能支持最基本的安全调用。

### 3.3 本地优先

- 默认仅支持同一台 Mac 上的本地 AI 客户端。
- App 继续只监听 loopback，不开放局域网和公网。
- 云端 AI 无法直接访问 localhost；如未来支持，必须是独立、可选的安全中继方案，不能暗中改变本地优先承诺。

### 3.4 证据优先、未知留空

- AI 只能把用户材料、转写或用户明确说明中的事实写入答案。
- 推测、建议和追问不能伪装成客户回答。
- 不确定内容保留为空、标为待确认，或进入顾问笔记；不得提升为已确认答案。

### 3.5 写入可预览、可追踪、可恢复

- 批量答案导入先预览，再确认提交。
- 每次写入携带幂等键、来源、时间、客户端和项目版本。
- App 保留变更日志和撤销能力；重试不得重复追加转写或重复建项目。

## 4. 目标架构

```text
┌──────────────────────────────────────────────────────────────┐
│ AI 工具                                                       │
│ Codex / Claude / VS Code Copilot / Cursor / 其他 MCP Client  │
└───────────────┬───────────────────────────┬──────────────────┘
                │ Agent Skill               │ MCP 配置
                ▼                           ▼
┌─────────────────────────────┐   ┌────────────────────────────┐
│ aham-survey Skill           │   │ 签名的本地 MCP Adapter     │
│ 工作流、边界、调用顺序       │   │ stdio 为主，HTTP 为可选     │
│ 不含 Token 和客户数据        │   │ 自动诊断 App 与版本         │
└───────────────┬─────────────┘   └──────────────┬─────────────┘
                │                                │ 本地受鉴权 RPC
                └──────────────┬─────────────────┘
                               ▼
                    ┌──────────────────────────┐
                    │ Aham Survey.app          │
                    │ 能力契约 / 校验 / 审计    │
                    │ SwiftData / 题库 / 导出   │
                    └──────────────────────────┘
```

### 4.1 推荐传输策略

第一阶段继续以 **stdio MCP Adapter** 为主，因为它最适合本机工具、兼容面广，并避免在 Swift App 内一次性实现完整 MCP 协议。

后续可增加标准 **Streamable HTTP `/mcp`**，但它是可选入口，不应立即替换 stdio：

- stdio：Codex、Claude Code、Cursor、VS Code 等本地客户端的默认方式。
- Streamable HTTP：支持该传输并运行在本机的客户端使用。
- 当前 `/rpc`：只作为 App 与 Adapter 的内部协议，未来可版本化为 `/internal/v1/rpc`。

长期建议把 Node 脚本替换为随 App 签名、通用架构的轻量 CLI Adapter，消除 Node 18 依赖；Node 版本继续作为开发和兼容后备。

## 5. Skill 包结构

```text
aham-survey/
├── SKILL.md
├── LICENSE.txt
├── references/
│   ├── product-model.md
│   ├── workflows.md
│   ├── tool-contracts.md
│   ├── answer-rules.md
│   ├── safety-and-confirmation.md
│   ├── client-setup.md
│   ├── troubleshooting.md
│   └── compatibility.md
├── scripts/
│   ├── doctor                 # 只诊断，不输出密钥
│   ├── install-client         # 按客户端安装 Skill 与 MCP 配置
│   └── verify-connection      # initialize / list / read-only smoke test
├── assets/
│   ├── project-brief.schema.json
│   ├── transcript-map.schema.json
│   └── examples/
└── evals/
    ├── trigger-cases.jsonl
    ├── workflow-cases.jsonl
    └── safety-cases.jsonl
```

说明：上述脚本和文件是未来实现清单，本规划阶段不创建。

### 5.1 `SKILL.md` 只放核心规则

`SKILL.md` 控制在 500 行和 5,000 tokens 内，只包含：

- 触发条件与非适用场景。
- 首次连接检查。
- 六条标准工作流。
- 读写确认规则。
- 事实边界和失败恢复。
- 按需读取哪个 reference 的路由说明。

建议 frontmatter：

```yaml
---
name: aham-survey
description: 使用 Aham Survey macOS App 创建和管理 ERP、MES、WMS、PLM、QMS、APS 调研项目，读取结构化问卷，将访谈材料映射并回写为可追溯答案，检查缺口并导出报告。用户提到现场调研、客户访谈、调研问卷、答案回写、调研进度或调研报告时使用；需要已连接的 aham-survey MCP。
license: MIT
compatibility: Requires Aham Survey for macOS and a local MCP-capable AI client.
metadata:
  author: Aham AIAPP
  version: "1.0.0"
  aham-app-min: "1.1.0"
  aham-mcp-contract: "1"
---
```

不建议在通用 frontmatter 中固定 `allowed-tools`，因为不同客户端的 MCP 工具命名和命名空间不同；权限策略放在正文和客户端安装壳中。

## 6. Skill 的标准工作流

### 6.1 连接预检

每次首次使用时：

1. 调用 `get_capabilities`。
2. 检查 App 版本、MCP 契约版本、Skill 最低版本和题库版本。
3. 确认 App 正在运行且当前连接是 localhost。
4. 只报告 Token 指纹或连接 ID，绝不显示 Token。
5. 若不兼容，停止写入并给出明确升级路径。

### 6.2 创建调研项目

1. 从用户材料提取客户名、行业、范围、顾问、目标和已知系统。
2. 调用 `list_departments` / `get_capabilities` 取得合法枚举。
3. 将缺失事实留空，并向用户展示项目摘要。
4. 用户已经明确要求“创建”时可直接写；否则先确认。
5. 调用 `create_project`，保存返回的 UUID。
6. 调用 `get_project` 回读校验，不用模糊名称继续写。

### 6.3 导入访谈或转写

1. 读取项目和目标部门题目。
2. 把材料拆成“原始证据片段”，逐条映射到 question ID。
3. 区分：答案、选项、顾问笔记、原始转写、待确认项。
4. 单选和多选只能使用题库返回的选项原文。
5. 生成预览：题目、拟写内容、证据、置信度、冲突和跳过原因。
6. 调用 `preview_answer_import` 做服务端校验。
7. 用户确认后调用 `commit_answer_import`。
8. 回读项目进度和被拒绝记录。

### 6.4 现场逐题记录

1. 按 App 返回的题序读取当前题目。
2. 保留客户原话，不主动润色成承诺。
3. 当回答不足以满足题型时只写笔记或转写，不计为完成。
4. 触发规则只作为追问提示，不自动生成客户答案。
5. 每批写入后回读已答数和当前修订号。

### 6.5 缺口检查与追问

1. 只读取 required 且尚未形成有效答案的问题。
2. 按部门、主题和风险分组，不一次抛出全部问题。
3. 每轮给出少量高价值追问及其原因。
4. AI 建议与客户事实分栏输出。

### 6.6 更新项目与状态

- 普通客户资料变更：展示字段差异后写入。
- `completed`：必须检查必答题、冲突和待确认项，并由用户确认。
- `archived`：必须明确确认；归档后默认只读。
- 不提供 MCP 永久删除工具；删除继续留在 App UI 并要求人工确认。

### 6.7 导出报告

1. 回读项目、进度、部门和待确认项。
2. 明确导出范围和格式。
3. MCP 返回结构化 Markdown 和报告元数据。
4. Word/PDF 由 App 导出时，返回文件路径、生成时间和内容快照版本。
5. 不把“生成成功”等同于“客户确认”或“最终版”。

## 7. MCP 能力契约规划

### 7.1 V1 必须保留的稳定工具

为兼容已有配置，现有 8 个工具名继续保留，但输入输出升级为严格 JSON Schema 和结构化错误。

| 工具 | 性质 | 规划调整 |
|---|---|---|
| `list_projects` | 读 | 支持状态过滤、分页和稳定 UUID |
| `get_project` | 读 | 默认只接受 UUID；名称搜索返回候选，不静默模糊命中 |
| `list_questions` | 读 | 返回题型、合法选项、required、顺序、答案有效性 |
| `export_report` | 读/生成 | 返回 Markdown、快照版本、缺口和生成元数据 |
| `create_project` | 写 | 支持 `request_id`，重复调用不重复创建 |
| `upsert_answers` | 写 | 过渡兼容；新增严格校验、原子批次和 dry-run |
| `import_transcript` | 写 | 支持来源 ID 和幂等追加，避免重试重复文本 |
| `update_project` | 写 | 支持字段白名单、expected revision 和状态规则 |

### 7.2 建议新增的核心工具

| 工具 | 目的 |
|---|---|
| `get_capabilities` | 连接预检、版本和 feature flags |
| `list_departments` | 返回实际安装题库中的部门、范围和版本 |
| `search_projects` | 明确返回候选，取代危险的静默模糊解析 |
| `preview_answer_import` | 校验题型、选项、冲突、未知题号，不写数据 |
| `commit_answer_import` | 使用 preview token / hash 原子提交 |
| `get_change_log` | 查看 MCP 写入来源和变更记录 |
| `undo_change_set` | 在限定时间内撤销某次 MCP 批量写入 |

不要急于增加“删除项目”“自动完成项目”“AI 直接改题库”等高风险工具。

### 7.3 MCP Resources 与 Prompts

为了兼容“支持 MCP、但不支持 Agent Skills”的客户端，后续 MCP 应同时提供：

**Resources**

- `aham://capabilities`
- `aham://departments`
- `aham://schemas/project`
- `aham://schemas/answer-import`
- `aham://projects/{id}/summary`

**Prompts**

- `create-survey-project`
- `map-interview-to-questions`
- `review-survey-gaps`
- `prepare-survey-report`

这些 Prompt 是精简降级版，不能替代完整 Skill，但可让普通 MCP 客户端获得正确的调用顺序。

### 7.4 统一错误格式

所有错误返回稳定结构：

```json
{
  "code": "ANSWER_OPTION_INVALID",
  "message": "单选题选项不在题库中",
  "retryable": false,
  "field": "answers[2].options[0]",
  "details": {},
  "suggestedAction": "重新调用 list_questions 获取合法选项"
}
```

错误至少覆盖：App 未运行、版本不兼容、鉴权失败、项目歧义、项目已归档、题号未知、题型不匹配、修订冲突、批次过大和重复请求。

## 8. 数据正确性与安全模型

### 8.1 答案有效性

必须由 App 按题型判断，而不是只判断文本非空：

- text：去空白后非空。
- number：可解析数字并满足题目约束。
- single_choice：恰好一个合法选项。
- multi_choice：至少一个合法选项且去重。
- boolean：合法布尔值或标准选项。
- note / transcript 不单独增加完成进度。

### 8.2 批量写入

- 先全量校验，后一次事务提交；默认不允许“部分成功”。
- `previewHash` 绑定项目修订号和拟写内容，确认后内容发生变化则失效。
- `request_id` 保证重试幂等。
- 每个答案保存 `sourceType`、`sourceRef`、`agentClient`、`changeSetId` 和时间。

### 8.3 鉴权与秘密

短期可行方案：

- App 只监听 `127.0.0.1`。
- 精确校验 `Authorization: Bearer <token>`。
- Token 默认遮挡，不进入命令行参数；通过客户端环境配置或权限为 0600 的本机配置注入。
- Token 写入 macOS Keychain；Skill 和日志永远不保存明文。
- 支持轮换、失效旧 Token、调用限速和审计。

中期方案：

- 提供随 App 签名的 Adapter / Helper。
- 优先研究 Unix Domain Socket 或签名 Helper + Keychain 的组合，进一步减少 localhost 攻击面。

### 8.4 HTTP/MCP 安全

- 正确读取完整 Header 和 `Content-Length`，处理 TCP 分包。
- 限制 Header、Body、转写和单批答案大小。
- 验证 Host / Origin，防止 DNS rebinding。
- 设置连接、读取和工具执行超时。
- 日志脱敏：Token、API Key、完整客户材料默认不打印。
- App 退出时关闭 listener；归档项目拒绝默认写入。

## 9. 客户端兼容方案

| 客户端 | Skill | MCP | 推荐接入 |
|---|---|---|---|
| Codex CLI / Desktop | 支持本地 Skill | stdio、Streamable HTTP | 用户级 Skill + stdio Adapter |
| Claude Code | 支持 Skill / 插件 | stdio、HTTP | 用户级 Skill + stdio Adapter |
| VS Code Copilot | 支持 Agent Skills | MCP | `.agents/skills` + `mcp.json` |
| Cursor | Skill 支持需逐版验证，可用 Rules 降级 | MCP | MCP + 生成 `.cursor/rules` 薄壳 |
| Claude Desktop | 完整 Skill 支持需逐版验证 | MCP | MCP Prompts/Resources + stdio |
| 其他本地 MCP Client | 不一定 | 通常支持其一 | MCP 工具描述 + Prompt 降级 |
| ChatGPT/Claude.ai 等云端客户端 | 不能直接访问本机 localhost | 远程 MCP 需要可达地址 | V1 不支持；未来可选安全中继 |

客户端版本变化较快，每次发布都应重新跑兼容矩阵，不能把一次验证永久写成“支持”。

## 10. 安装与发现体验

### 10.1 用户目标体验

App 首页最终提供“安装 AI 接入”向导：

1. 检测已安装的 Codex、Claude Code、VS Code、Cursor。
2. 用户勾选目标客户端。
3. 安装同一份 Skill 到客户端支持的位置。
4. 写入 MCP 配置，但不在界面或日志显示完整 Token。
5. 运行 `doctor` 和只读连接测试。
6. 给出每个客户端的通过、待重启或失败状态。

### 10.2 Skill 的规范位置

首选维护一份 canonical Skill：

- 用户共享位置：`~/.agents/skills/aham-survey/`
- 对不能扫描该目录的客户端，安装器复制或建立受控链接到其专属目录。
- 项目级安装仅用于团队仓库，希望固定某个 Skill 版本时使用。

### 10.3 App 发现

Adapter 应按以下顺序发现 App：

1. 明确环境变量或配置文件。
2. App 写出的本机 endpoint descriptor。
3. 默认应用路径和自动启动。
4. 超时后返回可操作诊断，不无限重试。

Descriptor 只包含端口、协议版本、进程实例 ID 和 Token 引用；不保存客户数据。

## 11. 版本与发布

至少维护四个独立版本：

- App SemVer。
- Skill SemVer。
- MCP contract version。
- Question catalog version。

`get_capabilities` 返回这些版本和 feature flags。Skill 启动时检查最低兼容版本；兼容性不满足时允许只读诊断，禁止写入。

发布形态：

1. Skill 随 App Bundle 分发，版本严格配套。
2. GitHub Release 另提供纯 Skill ZIP，便于审阅和手动安装。
3. 后续按 Codex/ChatGPT、Claude、VS Code 的插件格式增加薄包装；包装中仍复用同一 Skill 和 Adapter。

## 12. 测试与质量门

### 12.1 Skill 质量

- 用 `skills-ref validate` 校验目录和 frontmatter。
- 正向触发：创建调研、导入访谈、检查缺口、导出报告。
- 负向触发：普通 Word、PPT、代码审查、与调研无关的问卷。
- 用不同模型验证同一材料得到一致的工具调用顺序和事实边界。

### 12.2 MCP 契约

- initialize、notifications、tools/list、tools/call、ping。
- JSON Schema 正反例、结构化错误和协议版本协商。
- stdio 分帧、并发请求、乱序响应和进程退出。
- HTTP TCP 分包、超长 Body、错误 Content-Length、Origin 和鉴权。
- 幂等、修订冲突、事务回滚和重复转写。

### 12.3 端到端场景

建立隔离测试库，不触碰用户真实项目：

1. 创建装备制造 MES 项目。
2. 读取实际可用部门，不假设题库完整。
3. 导入包含明确事实、模糊说法和冲突说法的访谈。
4. 验证单选、多选、文本、数字和空白处理。
5. 检查进度、缺口、触发规则和归档保护。
6. 导出 Markdown、Word，并做内容及渲染检查。
7. 在 Codex、Claude Code、VS Code 和 Cursor 至少各跑一次。

### 12.4 发布门槛

- P0 修复项全部关闭。
- App、Adapter、Skill 契约测试全绿。
- 跨客户端矩阵有当前版本证据。
- 安装器不泄露 Token，卸载不删除调研数据。
- 写入预览、确认、回读和撤销均通过。
- 人工确认 Skill 不会把建议或推测写成客户事实。

## 13. 分阶段实施路线

### Phase 0：契约冻结与样例

- 冻结产品边界、六条工作流、读写确认矩阵和术语。
- 定义工具 JSON Schema、错误码、版本字段和黄金测试材料。
- 输出 ADR，决定 stdio 主通道和云端暂不支持。

### Phase 1：修复当前基线

- 按题型校验答案和进度。
- 修复 HTTP 分包、严格 Bearer、Body 限制和 Token 展示。
- 修复筛选选中错位、归档写入、题序分裂。
- 建立测试 Target 和 MCP 冒烟测试。

### Phase 2：MCP Contract v1

- 单一机器可读工具契约。
- `get_capabilities`、`list_departments`、项目候选解析。
- preview / commit、幂等、修订号、变更日志和结构化错误。
- 现有 8 工具保持兼容。

### Phase 3：Portable Skill v1

- 编写 `SKILL.md` 和按需 references。
- 建立触发、安全和工作流 evals。
- 增加 MCP Prompt/Resource 降级层。
- Skill 与 App 版本兼容检查。

### Phase 4：多客户端安装

- 先支持 Codex、Claude Code。
- 再支持 VS Code Copilot、Cursor。
- App 内提供检测、安装、doctor、升级和卸载。
- 将 Node 适配器替换或补充为签名通用 CLI。

### Phase 5：发布与观测

- App Bundle + Skill ZIP + 客户端薄插件。
- 只记录脱敏的本地调用统计、错误码和版本，不上传客户内容。
- 建立兼容矩阵和回归发布流程。

### Phase 6：可选云端桥接（独立立项）

只有用户明确需要 ChatGPT Web、Claude.ai 或远程 Agent 调用本机 App 时再做：

- App 主动建立出站加密连接。
- 设备配对、短期令牌、细粒度授权、端到端加密和随时断开。
- 默认关闭，明确展示哪些数据会离开本机。
- 不允许为了“全平台”而直接暴露本机端口。

## 14. 当前已知修复清单

### P0

1. 答案按题型校验，进度只统计有效答案。
2. MCP HTTP 完整读取请求，支持 TCP 分包和 Content-Length。
3. Authorization 精确匹配 Bearer Token；增加大小、超时和 Origin 防护。
4. Token 默认遮挡并迁移到 Keychain；配置、日志和进程参数不泄露。

### P1

1. 项目筛选后清理不可见选中项。
2. 已归档项目默认只读，完成/归档有状态门。
3. 统一题目排序的事实源。
4. 增加单元测试、MCP 契约测试和端到端测试。
5. 评估最低 macOS 部署版本。
6. 项目名称解析返回候选，不再静默模糊命中后写入。

### P2

1. 提高侧栏字号和对比度。
2. 优化导出面板首屏信息密度。
3. 完善 AI 模型预设、配置指导和错误解释。
4. Word 导出增加渲染级回归检查。

## 15. 实施前需要最终确认的决策

1. Skill 是公开 MIT 发布，还是只随 App 分发。
2. V1 是否只支持本机客户端；本方案建议“是”。
3. 批量回写是每次都确认，还是用户明确命令可直接写；建议“明确命令直写，材料自动映射必须预览确认”。
4. 是否接受新增答案变更日志和撤销数据模型；本方案建议“接受”。
5. 首批客户端优先级；本方案建议 Codex → Claude Code → VS Code → Cursor。

## 16. V1 完成定义

只有同时满足以下条件，才能称为“Aham Survey Skill v1 可交付”：

- 同一份 Skill 可被至少 Codex、Claude Code、VS Code 正确发现。
- 三者都能通过 MCP 完成连接预检、建项目、读题、预览答案、确认写入和导出。
- Cursor 至少可通过 MCP + Rules 降级方式完成相同主链路。
- AI 不会写入非法选项、未知题号、归档项目或无证据事实。
- 重试不产生重复项目、重复答案或重复转写。
- Token 不出现在 Skill、日志、截图、命令行参数和 Git 中。
- App 未运行、版本不兼容和题库缺失时都有明确可恢复错误。
- 所有客户端测试使用隔离数据，且有自动清理和人工复核证据。

