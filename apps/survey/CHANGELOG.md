# Changelog 更新日志

本项目所有重要变更都记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增
- **MCP 服务**：App 内置绑定 `127.0.0.1` 的本地服务 + 随包分发的 stdio 适配器 `aham-survey-mcp.mjs`，Claude Code 与 Codex 均可接入。8 个工具：`list_projects` / `get_project` / `list_questions` / `export_report` / `create_project` / `upsert_answers` / `import_transcript` / `update_project`。
- **首页改为 MCP 控制台**：服务状态、接入命令（一键复制）、工具清单、示例指令。
- **Service 层**：`ProjectService` / `SurveyService` / `ExportService`，视图与 MCP 共用同一套业务逻辑。

### 移除
- **新建项目 UI**：`NewProjectView`、⌘N、侧栏 + 按钮全部删除。项目只能由 MCP 创建。
- **复制项目**。
- **备份导出 / 导入**：`BackupManager` 与设置页「备份」Tab 删除，App 内不再派生 `zip` / `unzip` 子进程。
- **实时录音与语音转写**：删除 `SpeechRecognitionService` 及右侧面板录音区、语音自动填充；转写交由 [Aham Voice](https://github.com/Aham-AIAPP/aham-voice) 承担，后续通过外部通道注入文本。App 不再申请麦克风与语音识别权限。
- **Obsidian 对接**：沙盒下未使用 security-scoped bookmark，重启后写入必然失败；Markdown / Word 导出已覆盖该场景。
- **项目级 AI 增强**：动态选项集、优先级排序、跳过建议。
- **客户文档分析**：文档导入与由文档生成补充问题。
- **知识库训练与题库管理**：`Platform/Knowledge` 全目录、训练页与题库管理页。旧备份仍可正常导入。
- **行业补充题库**：`Industry` 枚举保留为项目标签。
- **产品 / 工艺 AI 搜索**、**备忘录 AI 分类**。

### 新增
- **现场备忘与已采纳追问持久化**：两者此前是内存状态，退出调研页即丢失且不进报告；现落库并纳入 Markdown / Word 导出（新增「现场备忘」章节，追问紧跟父题目输出）。

### 变更
- 设置页只剩「通用」一个 Tab（LLM 配置）。
- 删除项目现在会一并清除该项目的备忘与已采纳追问（原实现只删答案，留下孤儿记录）。
- **AI 润色改为手动触发**：按钮或 `⌘⇧P`，不再随每次输入自动调用。现场追问仍为自动。

### 修复
- **触发规则解析器**：原实现只支持单条件，含 `||` / `&&` 的复合条件被解析成永不匹配的字符串且无任何报错。内置采购题库 30 条规则中有 8 条（含 5 条 warning）从未触发。改为递归下降解析器，支持 `&&` / `||` / 括号 / `answer.number` 数值比较，生效规则数 22/30 → 30/30；并在 DEBUG 构建下加载题库时全量自检，防止哑规则再次出现。
- 备忘录：AI 判定输入「不属于任何类别」时会静默丢弃用户手打的内容，现非空输入必定落地。

### 变更
- 仓库迁移至新账号 [Aham-AIAPP](https://github.com/Aham-AIAPP)（旧账号不可用），全部链接更新；README 徽章行加「联系我（微信）」，「关于 Aham」加公众号/作者微信二维码，产品矩阵补 Aham Word。


## [1.0.1] - 2026-06-21

### 新增
- 仓库门面：补充 `LICENSE`（MIT）、`CONTRIBUTING.md`、README 顶部徽章（License / Release）。
- README 增加下载链接与首次打开（Gatekeeper）安装说明。

### 变更
- 产品显示名统一为 **Aham Survey**（应用包 bundle 与 Finder 显示名一致）。
- 应用内版本号（Xcode `MARKETING_VERSION`）对齐对外发版线，由 `2.5` 改为 `1.0.1`。

## [1.0.0] - 2026-06-20

### 新增
- **Aham Survey** 品牌下首个对外公开版本：现场调研工具（macOS · Swift / SwiftUI / SwiftData · 本地优先）。
- 项目制调研：按客户 / 项目建调研，状态分进行中 / 草稿 / 已完成 / 已归档，可复制、归档、导出。
- 行业 + 部门模板：按调研范围（ERP / MES / WMS / PLM / QMS / APS / 全面诊断）自动匹配部门与题目。
- 聚焦式问答流。
- AI 增强（自带 Key）：记录润色、AI 追问建议、客户文档分析、产品 / 工艺搜索。
  （注：1.0.0 的发布说明曾提及「说话人识别（声纹）」，该能力从未实现，为记录错误。）
- 导出：Markdown 报告、单部门导出、Obsidian URI。

### 变更
- 全面对齐兄弟仓库 [aham-ui](https://github.com/Aham-AIAPP/aham-ui) 设计系统，独立 App 化，更新调研图标。

### 安全
- 语音强制本地识别；从代码与 git 历史中移除内部行业知识库与 `xcuserdata`。

[Unreleased]: https://github.com/Aham-AIAPP/aham-survey/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Aham-AIAPP/aham-survey/releases/tag/v1.0.1
[1.0.0]: https://github.com/Aham-AIAPP/aham-survey/releases/tag/v1.0.0
