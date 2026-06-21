# 更新日志

本项目所有重要变更都记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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
- 聚焦式问答流，本地语音录音 + 本地 ASR 转写 + 说话人识别（声纹）。
- AI 增强（自带 Key）：记录润色、AI 追问建议、客户文档分析、产品 / 工艺搜索。
- 导出：Markdown 报告、单部门导出、Obsidian URI。

### 变更
- 全面对齐兄弟仓库 [aham-ui](https://github.com/li599198347-svg/aham-ui) 设计系统，独立 App 化，更新调研图标。

### 安全
- 语音强制本地识别；从代码与 git 历史中移除内部行业知识库与 `xcuserdata`。

[Unreleased]: https://github.com/li599198347-svg/aham-survey/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/li599198347-svg/aham-survey/releases/tag/v1.0.1
[1.0.0]: https://github.com/li599198347-svg/aham-survey/releases/tag/v1.0.0
