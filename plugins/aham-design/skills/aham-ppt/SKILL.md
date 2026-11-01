---
name: aham-ppt
description: >
  Aham PPT 排版引擎和视觉规范：用组件把页面写成 1920×1080 的 HTML 幻灯片，网页预览，排版检查，导出可编辑 PPTX，
  再检查 PPTX 的字号和颜色。字号、颜色、线宽、圆角和页面框架全部取自 aham-design 插件根目录的 tokens.json。
  触发场景：要按 Aham 规范画一页或几页幻灯片；要把 HTML 幻灯片导出成可编辑 PPTX；要检查 PPT 页面的字号、对比度、
  文字溢出和配色；要查 PPT 的固定数值、元素画法或构图原则。
  从材料开始做一整份方案或汇报 PPT（受众、论点、叙事、规划、样页、质检）时用 aham-app 的 aham-ppt-proposal，
  它按阶段调用本引擎。Word、Excel 和网页不用本技能。
---

# Aham PPT 引擎

本技能只管页面怎么画、怎么导出、怎么查视觉问题。写什么、按什么顺序写，由调用它的流程技能决定。

## 依赖

- Node.js：在 `assets/html2pptx/` 运行 `npm install`，安装 pptxgenjs 和 playwright。环境已有 playwright 时只装 pptxgenjs。
  预览、检查和导出要用 Playwright 的 Chromium。
- Python：`pip install -r requirements.txt`，安装 python-pptx，用于视觉检查。

## 文件位置

技能目录记作 `<引擎>`。Claude Code 加载本技能时，`${CLAUDE_SKILL_DIR}` 就是这个目录。

| 路径 | 内容 |
| --- | --- |
| `../../tokens.json` | 设计取值，aham-design 插件共用这一份。PPT 用 `color.ppt`、`size.ppt`、`layout.ppt`，字体用 `font.family` |
| `assets/html2pptx/tokens.js` | 读 tokens.json，换算成组件用的常量。本身不写数值 |
| `assets/html2pptx/components.js` | 页面组件：文字、方框、连线、编号、图表、图标和页面框架 |
| `assets/html2pptx/preview.js` | 把幻灯片目录合成单文件预览页 |
| `assets/html2pptx/check_slides.js` | 在浏览器里排版后检查溢出、重叠、字号、对比度、压线和空白 |
| `assets/html2pptx/html2pptx.js` | 导出可编辑 PPTX |
| `assets/html2pptx/demo/build.js` | 五页虚构内容的组件用法示例 |
| `assets/tools/check_deck_visual.py` | 读 PPTX，检查字号下限、字号层级、强调色、图例和色表 |
| `assets/tools/check_deck_visual.example.json` | 视觉检查的配置示例，色值与 tokens.json 一致 |
| `assets/examples/` | 范例库：用户评审定稿的合格页和被否定的不合格页 |
| `references/style-tokens.md` | 固定数值：每个常量对应的 tokens.json 键名、取值和用途 |
| `references/style-elements.md` | 元素：每种元素表达的关系和适用条件 |
| `references/design-principles.md` | 构图原则和内容结构的画法 |
| `references/html-slides.md` | HTML 幻灯片的写法、导出约束、组件清单和命令 |

## 取值来源

- tokens.js 和 check_deck_visual.py 用同一种办法找 tokens.json：先看环境变量 `AHAM_DESIGN_TOKENS`；没有时从脚本所在目录逐级向上，取第一个同时有 `tokens.json` 和 `.claude-plugin/plugin.json` 的目录。
- 引擎随插件安装在 `<插件根>/skills/aham-ppt/`，向上查找总能到达插件根。这一办法不依赖当前工作目录，也不依赖 `CLAUDE_PLUGIN_ROOT`。从 aham-app 的技能调用本引擎时，`CLAUDE_PLUGIN_ROOT` 指向 aham-app，所以引擎不读它。
- 引擎代码里没有色值、字号和画布尺寸，插件测试 `tests/test_ppt_tokens.py` 检查这一点，并检查 `style-tokens.md` 的表格与 tokens.json 一致。

## 命令

```bash
E="${CLAUDE_SKILL_DIR}"
node "$E/assets/html2pptx/preview.js" deck/ deck/preview.html --title "预览"
node "$E/assets/html2pptx/check_slides.js" deck/ --png deck/png --sheet deck/总览.png
node "$E/assets/html2pptx/html2pptx.js" deck/ 输出.pptx --title "标题" --author "〈作者〉"
python3 "$E/assets/tools/check_deck_visual.py" 输出.pptx --config 项目配置.json
```

页面写法和每个命令的说明见 `references/html-slides.md`。`check_slides.js` 的 ERROR 必须改完，WARNING 逐条改或写明保留理由。

## 风格的三层

| 层 | 文件 | 约束 |
| --- | --- | --- |
| 固定数值 | `style-tokens.md`，取值在插件根的 tokens.json | 字号、颜色、线宽、圆角和页面框架全册不变 |
| 元素 | `style-elements.md`，画法在 `components.js` | 每种元素表达一种关系，按适用条件选用 |
| 构图 | `design-principles.md`、范例库 `assets/examples/` | 按本页内容设计，同类页不照抄构图 |

## 常见错误

1. 序号写阿拉伯数字，不用 ①②③；对错写 √ ×。PPT 字体缺这些字符时显示方框。
2. 没有软件界面截图时画占位框，并在页脚标「示意」，不画假界面。
3. 组件没有的元素在生成脚本里自己画时，数值仍取 `C`、`FS`、`LW`，不写新色值。
