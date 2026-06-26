# Aham Survey — 现场调研工具（macOS）

[![Release](https://img.shields.io/github/v/release/li599198347-svg/aham-survey?color=336EE8)](https://github.com/li599198347-svg/aham-survey/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-336EE8.svg)](LICENSE)
[![Design](https://img.shields.io/badge/Design-Aham%20UI%20v6.1-336EE8.svg)](https://github.com/li599198347-svg/aham-ui)
[![Type](https://img.shields.io/badge/type-macOS%20App-336EE8.svg)](#)

![Aham Survey — 现场调研工具](assets/social-preview.png)

## 为什么做这个工具

做 ERP / MES / WMS 这类信息化项目的售前与实施调研，现场往往是一边聊一边手记，回去再对着录音和零散笔记重新整理——既费时，又容易漏掉关键细节、丢掉部门之间的对应关系。通用的笔记或录音工具能记下来，但记完还是一堆原始素材，离一份能交付的调研结果还差一整道整理活。

这个工具为此而做：它不止于「记下来」，而是把现场调研的全流程结构化——按项目、按行业部门组织问卷，边问边记、本地转写，把对话和笔记沉淀成有结构、可导出的调研成果。

---

## 定位

不是又一个录音笔记本，而是一套为调研场景打磨的结构化工作台：

- **专业** — 围绕真实售前 / 实施调研流程设计：项目、行业模板、部门问卷、聚焦式问答，按顾问的做法走。
- **结构化** — 调研不是一堆散记，而是按项目 / 部门 / 章节组织的成果，结束即可导出报告。
- **本地优先** — 数据存在本机（SwiftData），AI 用自带 Key，录音转写与说话人识别也在本地完成。
- **一致** — 与整个 Aham 系列共用 Aham UI v6.1 设计语言，亮 / 暗双色，界面克制统一。

> 简言之：把现场对话，做成能交付的结构化调研结果，而不是停在原始录音和笔记。

---

## 能做什么

- **项目制调研**：按客户 / 项目建调研，状态分进行中 / 草稿 / 已完成 / 已归档，可复制、归档、导出。
- **行业 + 部门模板**：内置行业模板与部门问卷，按调研范围（ERP / MES / WMS / PLM / QMS / APS / 全面诊断）自动匹配部门与题目。
- **聚焦式问答**：三卡堆叠的问题流，⌘↑ / ⌘↓ 切题，左侧按章节（开场 / 流程 / 痛点 / 期望 / 合规）导航。
- **本地语音**：录音 + 本地 ASR 转写 + 说话人识别（声纹），可一键把转写填入当前问题 / 笔记。
- **AI 增强（自带 Key）**：记录润色、AI 追问建议、客户文档分析、产品 / 工艺 AI 搜索、项目级 AI 增强。支持主流 LLM（比如自带 API Key 的云端模型等）。
- **导出**：Markdown 报告、单部门导出、Obsidian URI。

---

## 预览

> 同一套 Aham UI v6.1 设计语言 · 亮 / 暗双色。

<table>
  <tr>
    <td width="50%"><img src="assets/shots/survey-light.png" alt="Aham Survey · 亮色"></td>
    <td width="50%"><img src="assets/shots/survey-dark.png" alt="Aham Survey · 暗色"></td>
  </tr>
  <tr>
    <td align="center">亮色 · 部门分栏 + 聚焦式问答 + 顾问记录</td>
    <td align="center">暗色 · 实时录音转写 + 部门进度</td>
  </tr>
</table>

---

## 下载

[**↓ 下载最新版 Aham Survey（.dmg）**](https://github.com/li599198347-svg/aham-survey/releases/latest)

仅 Apple Silicon（M 系列）。打开 DMG 后把 `Aham Survey` 拖入「应用程序」。

应用为 ad-hoc 签名，首次打开会被 Gatekeeper 拦截，二选一解除：

- 右键点击 App → **打开** → 再点一次「打开」；或
- 终端执行：`xattr -dr com.apple.quarantine "/Applications/Aham Survey.app"`

AI 能力在「设置」里填 LLM API Key（仅存本机）。

**从源码运行**：需 macOS + Xcode 打开 `Aham.xcodeproj` 构建。

## 说明

- 当前仅支持 macOS；跨平台版（Tauri）暂未发布。
- 这是对外公开的示例版：内部行业知识库（方法论 / 售前框架等文档）已从代码与 git 历史中移除。
- 功能清单整理自源码盘点，若与最新代码不一致以代码为准。

---

## 更新记录

[Releases](https://github.com/li599198347-svg/aham-survey/releases) · [CHANGELOG](CHANGELOG.md)（Keep a Changelog · SemVer） · [CONTRIBUTING](CONTRIBUTING.md) · [MIT](LICENSE)

## 关于 Aham

> 把灵光一现，做成能用的 AI 工具。Aham 来自 *aha moment*，每个工具只把一件事做利落。

| 应用 | 一句话 |
|---|---|
| [Aham UI](https://github.com/li599198347-svg/aham-ui) | 供 AI 消费的设计系统——写一次规范，AI 产出处处一致 |
| **Aham Survey** | 现场调研工具（macOS）——本地优先，把现场对话做成结构化调研成果 |
| [Aham Voice](https://github.com/li599198347-svg/aham-voice) | 录音转写与会议纪要（macOS）——本地离线转写，纪要走你自己的模型 |
| [Aham PPT](https://github.com/li599198347-svg/aham-ppt) | 克制的 AI PPT 制作技能——把素材做成方案级 PPT |
