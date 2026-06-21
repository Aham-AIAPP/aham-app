# Aham Survey — 现场调研工具（macOS）

[![Release](https://img.shields.io/github/v/release/li599198347-svg/aham-survey?color=336EE8)](https://github.com/li599198347-svg/aham-survey/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-336EE8.svg)](LICENSE)
[![Design](https://img.shields.io/badge/Design-Aham%20UI%20v6.1-336EE8.svg)](https://github.com/li599198347-svg/aham-ui)
[![Type](https://img.shields.io/badge/type-macOS%20App-336EE8.svg)](#)

![Aham Survey — 现场调研工具](assets/social-preview.png)

> **Aham 应用矩阵**：[Aham UI](https://github.com/li599198347-svg/aham-ui) · **Aham Survey** · [Aham Voice](https://github.com/li599198347-svg/aham-voice) · [Aham PPT](https://github.com/li599198347-svg/aham-ppt)

把现场调研变成结构化洞察的 macOS 应用。Swift / SwiftUI / SwiftData，本地优先，仅 macOS。边聊边记，结束时调研报告自己长出来——不用回去整理录音和笔记。

## 能做什么

- **项目制调研**：按客户 / 项目建调研，状态分进行中 / 草稿 / 已完成 / 已归档，可复制、归档、导出。
- **行业 + 部门模板**：内置行业模板与部门问卷，按调研范围（ERP / MES / WMS / PLM / QMS / APS / 全面诊断）自动匹配部门与题目。
- **聚焦式问答**：三卡堆叠的问题流，⌘↑ / ⌘↓ 切题，左侧按章节（开场 / 流程 / 痛点 / 期望 / 合规）导航。
- **本地语音**：录音 + 本地 ASR 转写 + 说话人识别（声纹），可一键把转写填入当前问题 / 笔记。
- **AI 增强（自带 Key）**：记录润色、AI 追问建议、客户文档分析、产品 / 工艺 AI 搜索、项目级 AI 增强。支持主流 LLM（比如自带 API Key 的云端模型等）。
- **导出**：Markdown 报告、单部门导出、Obsidian URI。

## 下载

[**↓ 下载最新版 Aham Survey（.dmg）**](https://github.com/li599198347-svg/aham-survey/releases/latest)

仅 Apple Silicon（M 系列）。打开 DMG 后把 `Aham Survey` 拖入「应用程序」。

应用为 ad-hoc 签名，首次打开会被 Gatekeeper 拦截，二选一解除：

- 右键点击 App → **打开** → 再点一次「打开」；或
- 终端执行：`xattr -dr com.apple.quarantine "/Applications/Aham Survey.app"`

## 从源码运行

需 macOS + Xcode 打开 `Aham.xcodeproj` 构建。AI 能力在「设置」里填 LLM API Key（仅存本机）。

## 说明

- 当前仅支持 macOS；跨平台版（Tauri）暂未发布。
- 这是对外公开的示例版：内部行业知识库（方法论 / 售前框架等文档）已从代码与 git 历史中移除。
- 功能清单整理自源码盘点，若与最新代码不一致以代码为准。

## 版本与许可

- 版本与下载：[Releases](https://github.com/li599198347-svg/aham-survey/releases)
- 变更记录：[CHANGELOG.md](CHANGELOG.md)（Keep a Changelog · SemVer）
- 参与贡献：[CONTRIBUTING.md](CONTRIBUTING.md)
- 许可：[MIT](LICENSE)

---

## 关于 Aham

> **把灵光一现，做成能用的 AI 工具。**

Aham 来自 *aha moment*。每个工具只把一件事做利落。

| 应用 | 一句话 |
|---|---|
| [Aham UI](https://github.com/li599198347-svg/aham-ui) | 供 AI 消费的设计系统——写一次规范，AI 产出处处一致 |
| [Aham Survey](https://github.com/li599198347-svg/aham-survey) | 现场调研工具（macOS）——聊一圈，调研结果自己长出来 |
| [Aham Voice](https://github.com/li599198347-svg/aham-voice) | 录音转写与会议纪要（macOS）——录一段会，纪要已经写好 |
| [Aham PPT](https://github.com/li599198347-svg/aham-ppt) | 咨询级 AI PPT 制作技能——丢一堆素材，幻灯片出来了 |
