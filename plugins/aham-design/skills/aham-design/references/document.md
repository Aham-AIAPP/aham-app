# Aham 文档规范

本文是 Word 文档和文档网页预览的通用规范。表格的写法见 `table.md`。

取值都在插件根目录的 `tokens.json`，本文只写键名，不抄数值。改取值时改 `tokens.json`，本文不用跟着改。Word 每个元素的引擎实现情况见 aham-word 技能的 `references/word-spec.md`。

## 取值引用方式

- **键名**：写成 `size.word.body` 这样的点分路径，对应 `tokens.json` 里的一个 `$value`。
- **颜色**：写角色名，例如 ink、muted、accent。文档的颜色角色在 `role.document.color`，每个角色指向 `color` 下的一个色阶。
- **线宽**：Word 线宽在 `line.word`，单位是 1/8 磅。网页线宽在 `line.web`，单位是像素。每条线的颜色角色在 `role.document.rule_color`。
- **版面规则**：编号、金额单位、键值表等规则在 aham-word 技能的 `config/layout-rules.json`，本文用规则 id 引用，例如 `numbering`。
- **写作规则**：禁用词、标题写法和句长上限在 aham-word 技能的 `config/writing-rules.json`。

## 设计原则

1. 文字用冷灰色阶，不用纯黑。层级靠字号和字重区分。
2. 蓝色是点缀色，只用于章节编号、提示条上线、引语左线、封面短线和超链接。
3. 一份文件只用一种字体，中文、西文、数字和标题都用它。
4. 表格是三线表，见 `table.md`。
5. 靠留白分区。线条只用在本文列出的位置。
6. 文档固定亮色，不跟随系统深色模式。

## 页面

| 元素 | 写法 | tokens.json 键 |
|---|---|---|
| 纸张 | A4 纵向；章节可单独排成横向节 | `layout.page.paper`、`paper_width_mm`、`paper_height_mm` |
| 页边距 | 上下一组，左右一组 | `layout.page.top_margin_mm`、`bottom_margin_mm`、`left_margin_mm`、`right_margin_mm` |
| 版心宽度 | 纵向和横向各一个值。表格列宽和目录页码位置按它计算 | `layout.page.portrait_body_mm`、`landscape_body_mm` |
| 页眉、页脚距边 | 两个值相同 | `layout.page.header_distance_mm`、`footer_distance_mm` |
| 首页不同 | 有封面时打开，封面不印正文页眉页脚 | — |
| 网页版面 | 正文最大宽度、行长、左右留白、手机断点、章间距 | `layout.web.page_max_px`、`measure_em`、`gutter_px`、`gutter_phone_px`、`phone_breakpoint_px`、`chapter_gap_px` |

不用的写法：分栏；奇偶页不同；页面底色；页面边框。

## 颜色用途

| 角色 | 用途 | tokens.json 键 |
|---|---|---|
| ink | 正文、标题、表格数据、三线表粗线 | `role.document.color.ink` |
| muted | 表头、题注、表注、章节说明、页眉页脚 | `role.document.color.muted` |
| faint | 淡化内容：可选项、已完成项、未选方案、图片来源行 | `role.document.color.faint` |
| line | 表格行间线、提示条下线、页脚上线 | `role.document.color.line` |
| line_soft | 网页表格行间线 | `role.document.color.line_soft` |
| accent | 章节编号、提示条上线和标签、引语左线、封面短线、超链接 | `role.document.color.accent` |
| hot | 规则条和风险条、重点等级、必答标记 | `role.document.color.hot` |
| success、warning | 状态文字，只染文字 | `role.document.color.success`、`warning` |
| party_1 至 party_4 | 参与方圆点和泳道图 | `role.document.party.*` |

- 文字色对白底的对比度不低于 4.5:1，图形色不低于 3:1。aham-design 的 `tests/test_tokens.py` 按 WCAG 公式检查这些取值。
- faint 也要达到 4.5:1，依据版面规则 `faint_contrast`。
- 含义不能只靠颜色表达。状态、等级和参与方都同时写文字。

不用的写法：装饰性彩色；整行、整列或整块铺色；蓝色铺底；把状态色当装饰色。

## 字体与字重

| 介质 | 字体 | tokens.json 键 |
|---|---|---|
| Word、Excel | 文件字体 | `font.family.file` |
| 网页 | 界面字体栈 | `font.family.ui` |
| 网页代码和编码 | 等宽字体栈，只用于代码和编码 | `font.family.code` |

| 位置 | tokens.json 键 |
|---|---|
| Word 标题 | `font.weight.document.heading` |
| Word 正文、表头、表格数据 | `font.weight.document.body`、`table_header`、`table_body` |
| Word 行首标签、强调 | `font.weight.document.row_label`、`emphasis` |
| 网页标题、行首标签、加粗 | `font.weight.web.heading`、`row_label`、`strong` |

不用的写法：中文等宽字体；中文斜体；标题用衬线体；数字换用另一种字体。下划线只用于超链接和填空线。

## 字号

Word 单位是磅，网页单位是像素。

| 角色 | Word | 网页 |
|---|---|---|
| 封面标题 | `size.word.cover_title` | — |
| 文首标题 | `size.word.document_title` | `size.web.document_title`，手机 `document_title_phone` |
| 目录标题 | `size.word.toc_title` | — |
| 章标题 | `size.word.h1` | `size.web.h1` |
| 节标题 | `size.word.h2` | `size.web.h2` |
| 小节标题 | `size.word.h3` | `size.web.h3` |
| 导语 | `size.word.lede` | `size.web.lede` |
| 正文 | `size.word.body` | `size.web.body` |
| 章节说明 | `size.word.summary` | `size.web.note` |
| 表格数据、表头 | `size.word.table`、`table_header` | `size.web.table`、`table_header` |
| 表题、图题、表注 | `size.word.caption` | `size.web.caption` |
| 页眉页脚 | `size.word.header_footer` | — |
| 关键数字的数值 | `size.word.key_value` | `size.web.key_value` |
| 泳道图 | `size.word.swimlane` | `size.web.svg_label` |

`size.word.amount_primary`、`amount_total`、`total_label` 和 `table_compact` 留给业务扩展，通用规范不用。

## 段落与行距

| 元素 | 写法 | tokens.json 键 |
|---|---|---|
| Word 行距 | 用「最小值」，不用倍数 | `layout.word.line_spacing.mode` |
| Word 正文、列表、表格行距 | 三档 | `layout.word.line_spacing.body_pt`、`list_pt`、`table_pt` |
| Word 正文段后 | — | `layout.word.line_spacing.body_space_after_pt` |
| Word 正文排法 | 两端撑满，首行缩进 | `layout.word.paragraph.first_line_indent_chars` |
| 网页正文排法 | 居左，不缩进，行长不超过上限 | `layout.web.measure_em` |
| 中文标点 | 中文句子里的半角标点换成全角 | 版面规则 `cjk_punctuation` |

倍数行距按字体自身的行高计算，换一台电脑就可能变。最小值行距在各处相同。

不用的写法：用空格或全角空格缩进；用连续回车换页；放大加粗的正文冒充标题。

## 标题与编号

- 章节最多三级。Word 套内置样式「标题 1」至「标题 3」，供目录、导航窗格和屏幕阅读器识别。
- 编号写成「1」「1.1」「1.1.1」，按章节顺序生成。章、节的编号用 accent，小节编号用 ink。
- 章标题上方有一条线，Word 取 `line.word.chapter_top`，网页取 `line.web.chapter_top`，颜色见 `role.document.rule_color.chapter_top`。
- 标题段前段后见 `layout.word.heading.*`。标题与下一段同页。
- 标题只用名词短语，末尾不加句号。标题里不用疑问句，不用「你」「您」「请」，依据 `config/writing-rules.json`。
- 章节说明是章标题下一行的短文字，muted 色，不加标签和线，依据版面规则 `section_summary`。

## 列表

- 无序列表符号写成文字「•」。有序编号写成「1.」，下一级写成「（1）」，依据版面规则 `numbering`。
- 正文已自带编号时不再加编号。
- Word 列表的缩进和段后见 `layout.word.list.*`。
- Word 列表符号写成文字，不用 Word 自动编号。自动编号在 LibreOffice 里会换用其他字体显示符号。

## 提示条、风险条和引语

| 元素 | 写法 | tokens.json 键 |
|---|---|---|
| 提示条 | 上方 accent 线，下方 line 线，标签粗体 accent | `line.word.callout_top`、`callout_bottom`；`line.web.*` 同名键 |
| 规则条、风险条 | 同提示条，上线和标签用 hot | `role.document.rule_color.key_top`、`risk_top` |
| 风险条数量 | 全文有上限 | `layout.limits.risk_callouts_per_document` |
| 引语 | 左侧 accent 竖线，加中文引号，不铺底；出处在下方居右 | `line.word.quote_left`、`layout.word.quote.*` |
| 说明条款 | 序号和标签粗体，悬挂缩进 | `layout.word.notes.*` |

风险条上限是通用版式检查。aham_doc 引擎在三处检查它：生成 Word 时超出就报错；生成网页预览时超出就报错；网页审计把超出列为错误。

## 关键数字和图

| 元素 | 写法 | tokens.json 键 |
|---|---|---|
| 关键数字 | 文首一组，每个上方一条 ink 线，标签 muted，数值粗体 | `line.word.key_figure_top`、`layout.word.key_figures.*` |
| 图片 | 嵌入式，居左，不超出版心；多张图并排平分版心 | `layout.word.figure.*` |
| 图题、来源行 | 图题在图下方，muted；来源行在图题下一行，faint | `size.word.caption`、`layout.word.caption.*` |
| 替代文字 | 每张图都写 | — |
| 泳道图 | 每条泳道一个参与方，每列一步，超出步数上限时分段 | `layout.word.swimlane.*` |
| 网页柱状图 | 画布、边距、柱宽和系列上限 | `layout.web.chart.*` |
| 网页 SVG 文字 | 标题、标签和小字 | `size.web.svg_title`、`svg_label`、`svg_small`、`svg_tiny` |

图表配色以灰阶为主，至多一个 accent 高亮。不用三维、阴影和渐变。

## 封面、页眉页脚和目录

- **封面**：logo、标题、accent 短线、信息行、公司名。取值见 `size.word.cover_title`、`line.word.cover_rule` 和 `layout.word.cover.*`。主标题写项目名，副标题写文档类型，依据版面规则 `cover_title`。
- **文首**：正文第一页印文首标题、导语和关键数字。有封面时不再印信息条，依据版面规则 `first_page_info_line`。
- **页眉**：左侧文档标题，右侧 logo，muted 色。取值见 `size.word.header_footer` 和 `layout.word.header_footer.*`。
- **页脚**：左侧公司名和版本，右侧「第 X 页 / 共 Y 页」，上方一条 line 线（`line.word.footer_top`）。页码用域，不手输。
- **目录**：收标题 1 至标题 3，条目可点击。取值见 `size.word.toc_title`、`toc_minor` 和 `layout.word.toc.*`。
- **网页**：没有封面、页眉和页码。文首放标题和导语，页脚放公司名。

## 强调与淡化

- Word 不用加粗、斜体或底纹强调句子。重点句单独成段。
- 网页可以用荧光标记，只标句子里的关键短语。每章上限见 `layout.web.highlight_per_chapter_max`，网页审计检查这个上限。
- 网页内容转成 Word 时，荧光标记改成单独成段。
- 淡化用 faint。

## 介质差异

| 项目 | Word | 网页 | 原因 |
|---|---|---|---|
| 正文排法 | 两端撑满，首行缩进 | 居左，不缩进 | 中文公文习惯与网页阅读习惯不同 |
| 正文字号 | `size.word.body` | `size.web.body` | 纸面和屏幕的阅读距离不同 |
| 页码 | 第 X 页 / 共 Y 页 | 无 | 网页不分页 |
| 版面方向 | 纵向和横向节 | 随屏幕宽度 | 网页没有纸张 |
| 表格行间线颜色 | line | line_soft | 打印时更浅的线看不清 |
| 荧光标记 | 不用 | 每章有上限 | 正式文件会被修改和打印 |
| 字体 | `font.family.file` | `font.family.ui` | 网页按设备字体依次取用 |

## 文档属性与无障碍

- 文档标题属性写文档标题，作者属性写公司名，备注属性清空。
- 标题用内置标题样式，表头行标记为重复表头。
- 导出 PDF 时生成书签并嵌入字体。aham_doc 引擎不导出 PDF，这一项需要手工设置。
- 修订、批注、文档保护、密级和水印按需在 Word 里设置，aham_doc 引擎不处理。

## 取值来源

- 颜色色阶来自 aham-ui。
- Word 字号、线宽和版面规则来自原文档引擎，经设计决策表统一后写入 `tokens.json`。
- 旧版 aham-word 规范的西文 Inter 和数字 Consolas 改为全文一种字体，依据是设计决策表的字体一节。
- 旧版的表头浅灰底和表格文字竖向居中随 Word 引擎换成 aham_doc 而改变，现在是不铺底和靠上。
