# 网页规范

本文写给生成阅读型网页的 AI。阅读型网页指网页提案、方案说明、调研报告、周报这类单页网页。读者在浏览器里从上往下读，也可能打印。

业务管理系统的界面按 [app.md](app.md) 做。本文的取值都写成 [tokens.json](../../../tokens.json) 的键名，数值以 tokens.json 为准。

## 风格

页面用工程线描风格：层次靠线、字重和留白，不靠色块和阴影。

- 不用卡片。正文、要点和数字都不套带底色、圆角或阴影的方框。
- 分组靠章标题、间距和细线。一组内容和下一组之间留出间距，不画框。
- 线只用 `line.web.*` 的线宽，颜色按 `role.document.rule_color.*` 取。
- 页面不用阴影。`shadow.*` 只给界面的浮层。
- 色块只有三处：荧光标记、重点提示底色、泳道图隔行。

线条的用法：

| 线 | 线宽 | 颜色 |
|---|---|---|
| 章标题上方粗线 | `line.web.chapter_top` | `rule_color.chapter_top`，即 `role.document.color.ink` |
| 表格顶线和底线 | `line.web.table_frame` | `rule_color.table_frame`（ink） |
| 表头下方线 | `line.web.table_header_bottom` | `rule_color.table_header_bottom`（ink） |
| 表格行间线 | `line.web.table_row` | `rule_color.table_row`，即 `role.document.color.line` |
| 合计行上方线 | `line.web.total_top` | `rule_color.total_top`（ink） |
| 提示条上方色线 | `line.web.callout_top` | `rule_color.callout_top`（accent）；规则条和风险条用 `rule_color.key_top`、`rule_color.risk_top`（hot） |
| 提示条下方分隔线 | `line.web.callout_bottom` | `rule_color.callout_bottom`（line） |
| 引语左侧竖线 | `line.web.quote_left` | `rule_color.quote_left`（accent） |
| 关键数字上方线 | `line.web.key_figure_top` | `rule_color.key_figure_top`（ink） |

图示也画成线描：

- 流程图、泳道图、结构图用细线框和箭头，框内不铺底色。
- 框的圆角用 `layout.web.radius_px`，它引用 `radius.control`。
- 泳道图的隔行可以用 `role.document.color.tint` 铺浅底。
- 图里的分类色按 `role.document.party.*` 取，一张图最多用四种。

## 版面

正文只有一栏。

| 项目 | 键名 |
|---|---|
| 正文最大宽度 | `layout.web.page_max_px` |
| 行长上限 | `layout.web.measure_em` |
| 左右留白 | `layout.web.gutter_px`；手机用 `layout.web.gutter_phone_px` |
| 手机版断点 | `layout.web.phone_breakpoint_px` |
| 章与章的间距 | `layout.web.chapter_gap_px` |
| 侧栏宽 | `layout.web.aside_px` |

- 侧栏只放章节目录。宽屏时目录固定在正文左侧，正文仍是一栏。
- 窄于 `layout.web.phone_breakpoint_px` 时不显示侧栏，目录放到文首。
- 表格比正文宽时，表格自己横向滚动，页面不出现横向滚动条。
- 打印时去掉侧栏和按钮，只留正文。

## 字体

字体只用 Windows 和 Mac 都自带的字体，不加载网络字体。

| 用途 | 键名 | 实际用到的字体 |
|---|---|---|
| 正文、标题、表格 | `font.family.ui` | Windows 微软雅黑；Mac 苹方或冬青黑体；Linux Noto Sans CJK SC |
| 代码块 | `font.family.code` | Windows Consolas；Mac SF Mono 或 Menlo |

- 字重只用两档：400 和 600。标题、表格行首和正文强调分别取 `font.weight.web.heading`、`font.weight.web.row_label`、`font.weight.web.strong`。
- 数字列开启等宽数字（`font-variant-numeric: tabular-nums`），不换字体。
- 等宽字体只给代码块，金额和编号不用。

字号取 `size.web.*`，单位 px：

| 用途 | 键名 |
|---|---|
| 文首标题 | `size.web.document_title`；手机用 `size.web.document_title_phone` |
| 文首导语 | `size.web.lede` |
| 一级、二级、三级标题 | `size.web.h1`、`size.web.h2`、`size.web.h3` |
| 正文 | `size.web.body` |
| 表格正文、表头 | `size.web.table`、`size.web.table_header` |
| 图注表注、说明、标签 | `size.web.caption`、`size.web.note`、`size.web.label` |
| 关键数字、主金额 | `size.web.key_value`、`size.web.amount_primary` |

## 颜色

文字和线的颜色取 `role.document.color.*`。这一组引用 `color.gray.*`、`color.blue.*` 和 `color.semantic.*`。

| 用途 | 键名 |
|---|---|
| 正文和标题 | `role.document.color.ink` |
| 次级文字 | `role.document.color.ink_2` |
| 次要文字、表头 | `role.document.color.muted` |
| 来源、淡化行 | `role.document.color.faint` |
| 章节编号、链接、提示条色线 | `role.document.color.accent` |
| 重点和风险提示 | `role.document.color.hot`，底色 `role.document.color.hot_bg` |
| 完成、待办 | `role.document.color.success`、`role.document.color.warning` |
| 荧光标记 | `role.document.color.highlight` |

- 蓝字一律用 `role.document.color.accent`（`color.blue.text`）。`color.blue.base` 在浅底上低于 4.5:1，只给图形和按钮。
- 需要读的文字不低于 4.5:1。`color.gray.13` 是能写文字的最浅一档。
- 荧光标记每章最多 `layout.web.highlight_per_chapter_max` 处，只标结论句。
- `color.semantic.hot` 和分类色 `color.categorical.6` 色相接近，同一张图里不同时出现。

## 表格

- 用三线表：顶线、表头下方线、底线。行间线用 `role.document.color.line`。
- 表头文字用 `role.document.color.muted`，不铺底色。
- 表格行首可以加粗，取 `font.weight.web.row_label`。
- 数字靠右，同一列的小数位数一致。合计行上方加一条 `line.web.total_top`。
- 表格不用斑马纹，不给单元格上色。要强调一行时，在行首写状态文字。

## 交付前自查

- 页面里没有卡片、阴影和整块底色。
- 正文只有一栏，手机宽度下没有横向滚动条。
- 字体只有 `font.family.ui` 和 `font.family.code` 两套，没有引用网络字体。
- 颜色、字号、线宽、间距都能在 tokens.json 里找到对应的键。
- 示例数据一律虚构。
