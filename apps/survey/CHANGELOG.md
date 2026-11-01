# Changelog 更新日志

本项目所有重要变更都记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 仓库

- 2026-11-01 并入 Aham-AIAPP/aham-app 的 `apps/survey`，提交历史一并保留。Agent Skill 移到 aham-app 插件的 `plugins/aham-app/skills/aham-survey`，内容不变，Claude Code 安装 aham-app 插件即可使用；集成测试 `mcp-e2e.mjs` 的引用路径随之改。README、贡献说明和介绍页的链接改到 aham-app 和 aham-design。新版本在 aham-app 发布，标签以 `survey-v` 开头。

### 移除

- 删除 deliverables/ 里两期公众号文章的成品。它们与 Survey App 无关，构建脚本依赖已停用的公众号排版仓库。

### 变更

- 主按钮按 AhamUI 10.1.1 改回主色蓝：常态 #336EE8、悬停 #2A62D6、按下 #2357C4，浅色和暗色同值；按钮文字改用新增的 `ahOnAction`（白色，两种外观同值），对三种底色的对比度为 4.63、5.50、6.50。`ahOnAccent` 保持不变。主题对比度测试改为检查 `ahOnAction`。
- 调研报告导出 Word 的样式改用 aham-design 的文档取值：中文、西文和数字同用微软雅黑，正文 10.5pt，标题 16/14/12pt，表格改为三线表（不画竖线、表头不加底色），颜色改为 aham-design 的墨色和主色蓝。

## [1.2.1] - 2026-10-30

### 修复

- 保留答题页三栏、相邻题预览、答案与笔记并排和常驻提示栏；仅统一控件交互。
- 修复 AHCard 多个子视图被分别绘制背景的问题：首页标题与正文形成同一张等宽卡片，卡内代码使用独立浅层背景。
- 首页随客户端切换说明和能力标题；复制反馈固定占位、示例就地反馈，缺少适配器时禁用复制。
- 补齐目录、页签、筛选和图标按钮的悬停、按下与焦点反馈，保持几何尺寸；切题不再触发布局位移动画。
- “其他”补充文字切换后可在会话内恢复；未选中的文字不进入当前答案。重复单选不产生写入或修订。
- 补充文字与笔记共用失败草稿、重试和修订冲突保护；客户名称保存失败保留输入。输入框焦点边框不改变尺寸。
- 搜索或筛选无结果时提供清除入口；删除失败保留当前选中项目；题目集合更新时按 ID 保留当前题目。
- 新增卡片分组尺寸、选项切换、失败重试及外部写入冲突回归。数据模型与 MCP Contract v1 保持不变。

## [1.2.0] - 2026-10-30

### 交互与视觉

- 原生控件对齐 AhamUI 10.1.0：中性主按钮、亮暗配对色、禁用优先于悬停/按下、稳定按钮尺寸、键盘焦点与减少动态效果支持。
- 保留答题页原三栏、相邻题预览、答案与笔记并排和右侧提示常驻；在原右栏增加可展开的来源证据与转写。
- 单/多选项可用键盘操作；更正润色快捷键说明。清除前二次确认，并校验修订号，拒绝覆盖 MCP 后续更新。
- 输入保存失败时保留会话草稿，可重试或显式放弃；AI 取消或答案变化后丢弃迟到结果。
- 导出生成期间锁定参数并防重复提交；设置连接测试保持按钮尺寸、取消过期任务。
- 新增原生控件状态、主题对比度、禁用前后尺寸、隔离设置测试。数据模型与 MCP Contract v1 不变。

## [1.1.0] - 2026-10-30

### 写入一致性与报告完整性（2026-10-30）

- App 的项目资料、状态、答案、备忘、追问和 AI 润色经服务层保存；统一归档保护、修订号、进度和必答题完成校验。逐字输入可保存草稿，但不计为有效答案；已完成项目失去有效必答答案时回到进行中。
- 基础题与已采纳追问共同计入项目、部门、MCP 和导出进度。
- 保存并回读答案 `evidence`，撤销快照同时保留证据；同一 `request_id` 的请求内容必须一致。
- 撤销先比较目标答案的内容、记录 ID 和单题修订号，拒绝覆盖后续修改。旧记录缺少校验信息时拒绝自动重放/撤销。
- Markdown 与 Word 保留“其他”说明、产品工艺、证据、仅笔记/转写的记录；注明无效/忽略/转移状态并列出缺口。导出统计按所选部门计算。
- 隔离测试使用临时 MCP 凭据、端口和连接文件，不读取正式 Keychain；新增共享测试 scheme 和旧模型数据库迁移测试。

### Added

- 新增 MCP Contract v1、答案导入 preview/commit、幂等写入、修订控制、变更日志与答案撤销。
- 新增可移植的 `aham-survey` Agent Skill、四客户端安装/诊断脚本与隔离端到端测试基础设施。

### Changed

- MCP Token 迁移至 Keychain，并通过权限受限的连接描述文件注入 Adapter；界面和命令行不再展示明文。
- 答案进度改为按题型严格校验；归档项目默认只读，项目解析不再静默模糊命中。
- 经 Debug/Release 编译验证，将最低部署版本由 macOS 26.4 调整为 macOS 15.0。

### Fixed

- 修复本机 HTTP 请求的 TCP 分包、Content-Length、Host/Origin、Bearer 精确校验和大小限制。
- 修复题目排序、筛选后残留选中项及 App/MCP 进度不一致。

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
