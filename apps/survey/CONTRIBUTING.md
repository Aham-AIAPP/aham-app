# 贡献指南

感谢你对 **Aham Survey** 的关注。

## 开发环境

- macOS + Xcode，打开 `Aham.xcodeproj` 构建；当前仅支持 Apple Silicon（M 系列）。
- AI 能力需在「设置」里填入自己的 LLM API Key（仅存本机）。
- 视觉 / 设计改动须遵循仓库内 `CLAUDE.md` 与兄弟仓库 [aham-ui](https://github.com/li599198347-svg/aham-ui) 的设计系统铁规（颜色 / 间距 / 组件只走 design tokens）。

## 提交规范

- 提交信息使用 Conventional Commits 前缀：`feat:` / `fix:` / `docs:` / `refactor:` / `build:` / `chore:`。
- 一次提交只做一件事，信息写清「为什么」。

## 发版流程（维护者）

本仓库遵循 [语义化版本 SemVer](https://semver.org/lang/zh-CN/) 与 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)：

1. **定版本号**：破坏性变更 = MAJOR，向后兼容新功能 = MINOR，修复 / 文档 = PATCH。
2. **升版本号**：同步修改 Xcode 工程的 `MARKETING_VERSION`，保持与发版线一致。
3. **CHANGELOG**：把 `[Unreleased]` 内容移入 `## [X.Y.Z] - YYYY-MM-DD`，按 新增 / 变更 / 修复 / 移除 分组，补底部版本链接。
4. **提交推送**：commit 并 push 到 `main`。
5. **发布 Release（自动建 tag）**：
   ```sh
   gh release create vX.Y.Z --title "vX.Y.Z — 一句话主题" --notes-file <notes.md> --latest
   ```
6. **验证**：`gh release view vX.Y.Z`、`gh release list`。

## 报告问题

通过 [Issues](https://github.com/li599198347-svg/aham-survey/issues) 提交 bug 或建议，附上 macOS 版本、复现步骤与必要日志。
