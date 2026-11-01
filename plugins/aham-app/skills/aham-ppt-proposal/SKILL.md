---
name: aham-ppt-proposal
description: >
  把材料做成方案级、汇报级的 PPT。用户说「帮我做PPT」「做演示文稿」「做一个汇报」「根据这份资料做PPT」
  「做客户方案PPT」「制作幻灯片」「做个路演 deck」「竞标方案PPT」时触发，只有一句话需求也触发。
  八个阶段：受众与规范 → 材料解析 → 论点提炼 → 叙事骨架 → 页面规划 → 样页确认 → 逐页设计 → 质检交付。
  页面写成 HTML 幻灯片，网页预览确认后导出可编辑 PPTX。画页面、导出和视觉检查调用 aham-design 插件的 aham-ppt 引擎。
  只改现成 pptx 里的错字、只写 Word 或 Excel、只说口头汇报进展时不触发。
---

# Aham PPT 方案流程

本技能定做 PPT 的流程和文字规则。页面怎么画、怎么导出、视觉怎么查，全部由 aham-design 插件的 aham-ppt 引擎负责。
本技能不复制引擎文件。

## 两个目录

| 记号 | 目录 | 怎样得到 |
| --- | --- | --- |
| `<技能>` | 本技能的目录 | Claude Code 加载本技能时，`${CLAUDE_SKILL_DIR}` 就是这个目录 |
| `<引擎>` | aham-design 插件的 `skills/aham-ppt` | 运行 `python3 "${CLAUDE_SKILL_DIR}/scripts/find_engine.py"`，输出就是这个目录 |

第一阶段开始前运行一次 `find_engine.py`，把 `<引擎>` 的路径记进基线，后续命令都用这个路径。

- aham-app 和 aham-design 装在不同目录。本技能运行时 `CLAUDE_PLUGIN_ROOT` 指向 aham-app，所以要靠 `find_engine.py` 查找 aham-design。
- 查找顺序：环境变量 `AHAM_DESIGN_ROOT`；与 aham-app 同级的 `aham-design` 目录；Claude Code 安装记录 `installed_plugins.json` 里的 `installPath`；插件缓存里同一市场下版本最高的 `aham-design`。
- 每个候选目录都核对插件名、主版本号 1 和 `skills/aham-ppt/SKILL.md`。
- 找不到时脚本列出查过的位置并报错。这时请用户安装 aham-design，或把 `AHAM_DESIGN_ROOT` 设为它的插件根目录。

## 依赖

- 引擎的依赖按 `<引擎>/SKILL.md` 安装：Node.js 包 pptxgenjs、playwright，Python 包 python-pptx。
- 本技能的 Python 依赖：`pip install -r "${CLAUDE_SKILL_DIR}/requirements.txt"`，用于读材料提纲和检查 PPTX。
- LibreOffice 可选，用于导出 PDF 和抽查渲染。没有时交付物不含 PDF，并在交付说明里写明。

## 阶段与文件

每个阶段开始前读对应的阶段文件，按文件里的停等点、步骤和完成卡执行。八个阶段按顺序进行。
阶段共用的动作、完成卡格式和工作区文件见 `phase-common.md`，在第一阶段读一次。

| # | 阶段 | 阶段文件 | 同时读 |
| --- | --- | --- | --- |
| 1 | 受众与规范 | `phase-01.md` | `phase-common.md`、`<引擎>/references/style-tokens.md` |
| 2 | 材料解析 | `phase-02.md` | — |
| 3 | 论点提炼 | `phase-03.md` | — |
| 4 | 叙事骨架 | `phase-04.md` | `wording-rules.md` |
| 5 | 页面规划 | `phase-05.md` | `<引擎>/references/design-principles.md`、`<引擎>/references/style-elements.md` |
| 6 | 样页确认 | `phase-06.md` | `<引擎>/references/html-slides.md`、`writing-order.md`、`<引擎>/assets/examples/README.md` |
| 7 | 逐页设计 | `phase-07.md` | 每章开工前重读 `<引擎>/references/design-principles.md` 第一节和范例库说明 |
| 8 | 质检交付 | `phase-08.md` | — |

不带 `<引擎>` 的文件都在本技能的 `references/` 下。已读的文件在后续阶段不重读，表里写明重读的除外。

按条件读的文件：

| 文件 | 条件 |
| --- | --- |
| `solution-deck.md` | 第一阶段把文稿类型定为方案 |
| `coach-engine.md` | 第一阶段末尾读第一、二节做档位检测；档位为引导或教练时，每个阶段读第三节对应的引导序列 |

## 脚本

| 脚本 | 用途 |
| --- | --- |
| `scripts/find_engine.py` | 查找引擎目录 |
| `scripts/extract_outline.py` | 把 PDF、Word、PPT、Excel、Markdown 材料转成提纲 |
| `scripts/check_deck.py` | PPTX 自查。依次调用引擎的视觉检查和本技能的文字检查 `deck_text.py`，合成一份报告 |
| `scripts/check_deck.example.json` | 项目配置里文字检查的键：术语表、观察词、标题形式。视觉检查的键见 `<引擎>/assets/tools/check_deck_visual.example.json` |

## 规则优先级

- 文字按 `wording-rules.md`。方案类的标题、子标题和页面短句按 `solution-deck.md`。
- 数值按 `<引擎>/references/style-tokens.md`，元素按 `<引擎>/references/style-elements.md`，构图按 `<引擎>/references/design-principles.md`。
- 用户在本次对话里的要求优先于以上文件，记进基线的修正记录。

## 常见错误

1. 序号写阿拉伯数字，不用 ①②③；对错写 √ ×。PPT 字体缺这些字符时显示方框。
2. 没有软件界面截图时画占位框并在页脚标「示意」，不画假界面。
3. 开工时建术语表，同一事物只用一个名称。客户评审过的架构图作为定稿，其他页与它一致。
4. 数字只取自信息清单，不编造。缺的数字记进基线的待确认清单，页面不写「待确认」。
