# Aham 表格规范

本文是 Word、Excel 和网页表格的通用规范。文档其他元素见 `document.md`。

取值都在插件根目录的 `tokens.json`，本文只写键名，不抄数值。颜色写角色名，角色在 `role.document.color`。版面规则在 aham-word 技能的 `config/layout-rules.json`，本文用规则 id 引用。

## 实现情况

- **Word**：aham_doc 引擎实现本文的 Word 写法，取值从 `tokens.json` 读取。
- **网页**：aham_doc 的网页渲染器实现本文的网页写法。网页单元格内边距和行高写在 `scripts/aham_doc/web/base.css`，`tokens.json` 里没有对应键。
- **Excel**：aham-design 目前没有 Excel 引擎。本文的 Excel 写法是规范，生成 Excel 的技能按本文和 `tokens.json` 的 `size.excel`、`line.excel`、`layout.excel` 实现。

## 三线表

全部表格用三线表，依据版面规则 `table_style`。

| 部位 | 颜色 | Word 线宽 | Excel 线型 | 网页线宽 |
|---|---|---|---|---|
| 表头上线 | `role.document.rule_color.table_frame` | `line.word.table_frame` | `line.excel.table_frame` | `line.web.table_frame` |
| 表头下线 | `role.document.rule_color.table_header_bottom` | `line.word.table_header_bottom` | `line.excel.table_header_bottom` | `line.web.table_header_bottom` |
| 行间线 | Word 和 Excel 用 line，网页用 line_soft | `line.word.table_row` | `line.excel.table_row` | `line.web.table_row` |
| 末行下线 | `role.document.rule_color.table_frame` | `line.word.table_frame` | `line.excel.table_frame` | `line.web.table_frame` |

- 不画竖线，不画外框。
- 表头不铺底色，数据区不铺底色，不用斑马纹。
- 行间线不细于版面规则 `table_style` 的 `row_rule_min_pt`。
- 首列左侧和末列右侧不留内边距，表格左右边线与正文版心齐平。

## 字号和字重

| 位置 | Word | Excel | 网页 |
|---|---|---|---|
| 表格数据 | `size.word.table` | `size.excel.table` | `size.web.table` |
| 表头 | `size.word.table_header` | `size.excel.header` | `size.web.table_header` |
| 表题 | `size.word.caption` | `size.excel.caption` | `size.web.caption` |
| 表注 | `size.word.caption` | `size.excel.note` | `size.web.note` |

- 表头用 muted 色、常规字重、居左。字重见 `font.weight.document.table_header`。
- 表格数据用 ink 色、常规字重。字重见 `font.weight.document.table_body`。
- 行首标签列在内容声明时加粗。Word 字重见 `font.weight.document.row_label`，网页见 `font.weight.web.row_label`。
- Word 表格字号不小于 `layout.word.table_capacity.min_font_pt`。Excel 字号不小于 `layout.excel.minimum_readability.font_pt`。
- 表格文字和正文用同一种字体，数字不换用等宽字体。

## 表题和表注

- 表题在表格上方，粗体 ink。表题只写表名，不写「表 1」这样的编号。
- 表注在表格下方，muted 色。Word 段距见 `layout.word.caption.*` 和 `layout.word.notes.*`。
- 分类计数写进表题或表注，例如「重点 2 项、一般 4 项」。

## 密度和行距

| 项目 | Word 常规 | Word 紧凑 |
|---|---|---|
| 上下内边距 | `layout.word.table.regular.cell_vertical_pt` | `layout.word.table.compact.cell_vertical_pt` |
| 左右内边距 | `layout.word.table.regular.cell_side_pt` | `layout.word.table.compact.cell_side_pt` |
| 行距（最小值） | `layout.word.table.regular.line_pt` | `layout.word.table.compact.line_pt` |

- 默认用常规版。行数多的长表用紧凑版，内容里写 `"density": "compact"`。
- Word 单元格文字靠上，见 `layout.word.table.v_align`。网页单元格文字也靠上。
- Excel 单元格没有内边距。单行的行竖向居中；多行的行整行靠上，序号、名称和金额与内容第一行在同一条水平线上。

## 宽度和分页

| 项目 | 写法 | tokens.json 键 |
|---|---|---|
| Word 表宽 | 固定布局，列宽按版心等比缩放，不超出版心 | `layout.page.portrait_body_mm`、`landscape_body_mm` |
| Word 列数上限 | 超出时报错 | `layout.word.table_capacity.max_columns` |
| Word 行数上限 | 超出时报错 | `layout.word.table_capacity.hard_max_rows` |
| Word 跨页 | 重复表头 | `layout.word.table_capacity.overflow_policy` |
| Word 小表 | 行数在上限以内的表格不跨页 | 版面规则 `keep_small_tables` |
| Excel 内容宽度 | 按屏幕宽度排。窄列按字号放宽，放得下一行表头；文字列按比例分剩余宽度 | `layout.excel.screen_width_px`、`layout.excel.minimum_readability.column_px` |
| Excel 行高 | 表头、正文、表注各有取值，正文行高按行数计算并有上下限 | `layout.excel.row_height_px.*` |
| 网页 | 窄屏时表格在容器内横向滚动 | `layout.web.phone_breakpoint_px` |

列数多的表格先考虑拆表或改用横向节，再考虑紧凑版。

## 特殊列

| 列 | 写法 | 依据 |
|---|---|---|
| 金额列 | 居右，千分位，保留两位小数，例如 780,800.00 | — |
| 金额单位 | 单位写进表头，单元格只放数字，数字后不写「元」 | 版面规则 `amount_unit` 的 `in_header`、`header_suffix`、`after_number` |
| 金额标签 | 键值表和汇总的标签里写单位和计税口径 | 版面规则 `amount_unit` 的 `in_label`、`label_suffix` |
| 数量、比例等数字列 | 居右 | 旧版 aham-word 规范的数字列写法 |
| 日期列 | YYYY-MM-DD，例如 2026-10-20 | — |
| 序号列 | 两位数字，例如 01 | — |
| 等级列 | 等级前加一条短横线；重点等级用 hot 加粗，其余用 muted | — |
| 状态列 | 写成状态标签，标签里写文字 | — |
| 参与方列 | 名称前加参与方圆点，颜色见 `role.document.party.*` | — |

- Word 引擎按表头识别金额列，识别词是「金额」「单价」「总价」「税额」。识别出的金额列自动居右，数字自动加千分位和两位小数，表头补单位。识别词在 `scripts/aham_doc/word.py` 的 `MONEY_HEADER_MARKERS`。
- 网页预览沿用同一套识别。直接写网页内容时，金额列在 `amount_cols` 里声明。
- 网页的数字列用等宽数字（`font-variant-numeric: tabular-nums`），字体不变。
- 金额以外的数字列，Word 和网页内容用 `alignments` 声明居右。
- 日期和序号的写法由内容负责，引擎不改写。
- 等级、状态和参与方由表格的 `marks` 声明，单元格仍写纯文字。

## 键值表

基本信息用键值表，依据版面规则 `key_value_table`。

- 两列：标签在左，值在右。不设表头行。
- 标签列宽见 `layout.word.table.key_value.label_cm`，单元格边距见 `layout.word.table.key_value.*`。
- 键值表也用三线表的线。

## Excel 专用写法

| 项目 | 写法 | tokens.json 键 |
|---|---|---|
| 线型 | 三条框线和行间线都用细线 | `line.excel.*` |
| 线色 | 与 Word 相同的颜色角色 | `role.document.rule_color.*` |
| 字体 | 文件字体 | `font.family.file` |
| 页标题 | 第一行，加粗 | `size.excel.title`、`layout.excel.row_height_px.title` |
| 页眉页脚 | — | `size.excel.header_footer` |
| 显示比例 | — | `layout.excel.zoom` |
| 打印纸张 | A4，宽度缩到 1 页，高度不限 | `layout.excel.print.paper`、`fit_to_width`、`fit_to_height` |
| 打印表头 | 每页重复表头行 | `layout.excel.print.repeat_header` |
| 打印区域 | 每个页签都设打印区域 | `layout.excel.print.print_area_required` |
| 页边距 | 单位英寸 | `layout.excel.margins_in.*` |

- 金额用数字格式 `#,##0.00`，单元格里存数字，不存文字。
- 序号用数字格式 `00`，单元格里存数字。
- 日期用数字格式 `yyyy-mm-dd`，单元格里存日期。
- 对外发送的表不设筛选，筛选按钮会压住表头文字。内部使用的表可以保留筛选。
- 超链接用 accent 加下划线。需要填写的输入值用 accent，不加下划线。

## 业务扩展

合计行、分组行、作废行和合并单元格不属于通用表格。

- Word 由业务技能用 `register_table_hooks` 实现，网页用 `register_row` 实现。
- 合计行上线的取值留在 `line.word.total_top`、`line.web.total_top` 和 `line.excel.total_top`，颜色见 `role.document.rule_color.total_top`。
- 报价表的金额汇总、主报价合计和分组明细行属于业务模板，不在本文范围。

## 不用的写法

- 竖线、外框、全网格。
- 斑马纹；表头铺底色；数据区铺色；红黄绿色块单元格。
- 金额列或数量列居左；数字后写单位；同一列混用不同小数位数。
- 用空格或空行调整列宽和行高。
- 列宽总和超出版心。

## 取值来源

- 三线表依据 GB/T 7713.1-2006，见版面规则 `table_style` 的 `basis`。
- 金额单位写进标题依据 ISO 24896 和 IBCS，见版面规则 `amount_unit` 的 `basis`。
- 旧版 aham-word 规范的数字列 Consolas 已经替换，依据是设计决策表的字体一节。
- 旧版的表头浅灰底和单元格竖向居中也已替换。Word 引擎换成现在的 aham_doc 后，这两项随引擎改为不铺底和靠上。
