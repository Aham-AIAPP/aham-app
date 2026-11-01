# 网页内容格式

网页渲染器 `aham_doc.html` 读取一个 JSON 对象，输出单文件 HTML。颜色、字体、字号、线宽和版面全部取自 `tokens.json`，内容里不写格式。

两种用法：

- Word 内容的网页预览：`python3 scripts/build_preview.py 内容.json 输出.html`。读的是 `references/content-format.md` 的 Word 内容，与 `build_docx.py` 同一份文件。示例见 `examples/aham-word-demo.html`。
- 直接写网页内容：`python3 scripts/build_html.py 内容.json 输出.html [--fragment]`。内容按本文的格式写，图片和 SVG 放在内容文件所在目录。

生成后运行 `python3 scripts/audit_html.py 输出.html` 检查色值、字体、外部资源、荧光标记、风险条和用词。

## 1 顶层字段

| 字段 | 必填 | 内容 |
|---|---|---|
| `meta` | 是 | 文首信息，见第 2 节 |
| `keys` | 否 | 文首关键数字，最多 4 个，每项 `label` 和 `value` |
| `parties` | 否 | 参与方，最多 4 个，写法同 Word 内容的 `parties` |
| `toolbar` | 否 | `links` 里第一个链接显示为工具条主按钮 |
| `chapters` | 是 | 章节列表，每章 `id`、`title`、`blocks`；`number` 指定章编号，空字符串不编号；`toc_sub: true` 时目录列出本章小节 |
| `toc` | 否 | 写 `false` 时不出目录 |

小节标题和场景按「章号.序号」自动编号。章节有 4 章及以上且 `toc` 不为 `false` 时出目录。

## 2 meta

| 字段 | 内容 |
|---|---|
| `title` | 文档标题，必填 |
| `customer`、`doc_kind` | 标题上方的一行小字，两项用「·」连接；都不写时不印这一行 |
| `lede` | 导语 |
| `project`、`author`、`version`、`date` | 信息行；日期写 YYYY-MM-DD |
| `items` | 信息行的自定义顺序，每项 `label` 和 `value`；写了就不用上一行的字段 |
| `bar_subtitle` | 工具条标题后的灰字，缺省取 `doc_kind` |
| `footer_note` | 页尾右侧的说明 |
| `page_title` | 浏览器标签页标题，缺省取 `title` |

页尾左侧印 `config/brand.json` 的公司名和英文品牌名。

## 3 内容块

文字里写 `==重点短语==` 生成荧光标记，每章不超过 `layout.web.highlight_per_chapter_max` 处。文字里的「★」印成重点色的必答标记。

| type | 字段 | 说明 |
|---|---|---|
| `paragraph` | `text`；`muted` | `muted: true` 时用次要色小字 |
| `heading` | `level` 2 或 3、`title`；`number`、`tag`、`tag_text` | 小节标题。写 `number` 时用指定编号 |
| `list` | `items`；`ordered` | 有序列表编号写成「1.」；条目可写 `{"text": "…", "faint": true}` |
| `quote` | `text`；`source` | 引语，出处另起一行 |
| `callout` | `tone`、`label`、`text` | `tone` 取 `lead` 提示条、`key` 规则条、`risk` 风险条；风险条全文不超过 `layout.limits.risk_callouts_per_document` 条 |
| `table` | `columns`、`rows`；`caption`、`amount_cols`、`row_header`、`alignments`、`filter`、`faint_values`、`id`、`layout` | 三线表，见第 4 节 |
| `figure` | `path`、`caption`；`source`、`alt`、`max_width` | 图片以 data URI 内嵌 |
| `figures` | `items` | 两张图左右排列，每项同 `figure` |
| `svg` | `path`、`caption`；`source` | 内联 SVG 图，见第 5 节 |
| `swimlane` | `steps`；`caption` | 泳道图，每步 `[执行方, 角色, 操作]` |
| `anatomy` | `parts`、`caption`；`separator`、`alt` | 编码结构图，`parts` 每项 `code`、`label`、`key` |
| `notes` | `items`；`title` | 说明条款，「标签：正文」的标签加粗 |
| `columns` | `items` | 分工栏，每栏 `title`、`party`、`items` |
| `legend` | `labels` | 参与方图例 |
| `with_aside` | `blocks`、`aside` | 正文加右侧旁注；旁注写 `tone` 时显示为提示样式 |
| `scenes` | `items`；`index`、`switch_all` | 折叠场景，见第 6 节 |
| `checklist` | `items`；`id`、`store_key`、`progress_label` | 待确认清单，每项 `text`、`party`、`required`。勾选状态只存在读者本机浏览器 |
| `codebox` | `text`；`label` | 整段可复制的文字，右上角有「复制全文」按钮 |

## 4 表格

- 行可以直接写数组，也可以写对象 `{"cells": [...], "kind": "faint", "key": "…"}`。通用渲染器的 `kind` 只有 `row` 和 `faint`。
- 首列缺省是行首标签列并加粗；`row_header: false` 时不加粗。
- 数值列和金额列写进 `amount_cols`，居右。
- 单元格可写对象：`{"tag": "solid", "text": "已确认"}`、`{"party": "实施方", "text": "…"}`、`{"level": "hot", "text": "重点"}`、`{"required": true, "text": "…"}`、`{"strike": true, "text": "…"}`、`{"faint": true, "text": "…"}`。表头也可以写 `party` 对象。
- `filter` 生成行筛选按钮：`{"label": "按等级筛选", "options": [{"key": "hot", "label": "重点"}]}`，各行用 `key` 对应。
- `layout: "key_value"` 时排成键值表，每行 `[标签, 值]`。

## 5 SVG 图

SVG 里不写色值、字体和字号，只用下列类。颜色和字号由 `web/base.css` 的 `.flow` 规则给出。

| 类 | 用途 |
|---|---|
| `bx`、`bx-a` | 普通方框、主色方框 |
| `ln`、`ln-a` | 实线、主色虚线 |
| `ah`、`ah-a` | 箭头 |
| `t1`、`t1a` | 方框标题、主色方框标题 |
| `t2`、`t2b` | 次要色说明、次级说明 |
| `t3`、`t3a`、`t4a` | 小字、主色小字、更小的主色字 |
| `pt-1` 至 `pt-4` | 参与方颜色 |

分组柱状图用 `python3 scripts/bar_chart.py 数据.json 输出.svg` 生成，画布和柱宽取 `layout.web.chart`。同一张图要在 Word 里用时，`aham_doc.webstyle.standalone_svg` 把类名规则抄进 SVG。

## 6 场景

- `items` 每项写 `id`、`title`，再写 `steps`、`matrix`、`table`、`blocks` 中的一种。
- `steps` 每步写执行方、角色、操作。超过 7 步时页面提示横向滑动，并提供步骤表视图。
- `matrix` 每行写情况名称和各泳道的操作，写「不涉及」的格子淡化。
- `blocks` 放段落、列表、引语、提示条或表格；不能放小节标题、场景、旁注或待确认清单。
- `open: false` 时折叠段默认收起；打印时全部展开。

## 7 扩展点

业务专有的写法由调用方登记，引擎不导入调用方脚本：

| 函数 | 用途 |
|---|---|
| `html.register_block(类型, 渲染函数, required=(必填字段,))` | 登记新的内容块，例如金额汇总 |
| `html.register_row(类型, 渲染函数)` | 登记新的表格行，例如合计行、分组行 |
| `html.register_stylesheet(名称, CSS)` | 登记附加样式，只引用 `:root` 变量 |
| `preview.register_block(类型, 转换函数)` | 登记 Word 内容块在网页预览里的写法 |
