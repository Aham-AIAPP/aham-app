# Aham Word 排版规范

本文列出影响 Word 文档外观的元素，逐项写明 Aham 的取值、取值所在的 `tokens.json` 键和引擎的实现情况。改规范时按本文逐项检查，改 `tokens.json` 里对应的键。

## 实现情况标记

- **引擎**：引擎已实现，取值从 `tokens.json` 读取。
- **引擎（代码）**：引擎已实现，取值写在引擎代码 `scripts/aham_doc/word.py` 里。改这类取值要改代码。
- **规范**：本文给出取值或原则，引擎没有实现，需要时手工设置或由业务技能扩展。

颜色写作「角色（色值，tokens 键）」。文档颜色的角色在 `role.document.color`，每个角色指向 `color` 下的冷灰或蓝色色阶。

---

## 0. 设计原则

1. 文字用冷灰色阶，正文和标题是 ink（`#141A26`，`color.gray.18`），不用纯黑。层级靠字号和字重区分。
2. 蓝色只用于章节编号、提示条上线、引语左线和封面短线。文档里的蓝字用 `color.blue.text`（`#2453C7`），它在浅灰底上也有 4.5:1 的对比度。
3. 全文只用微软雅黑一种字体。中文、西文、数字和标题都用它，不用等宽字体，不用斜体。
4. 表格是三线表：表头上下两条正文色线，行间一条浅灰细线，末行一条正文色线。没有竖线，数据区不铺底色。
5. 靠留白分区，线条只用在上面列出的位置。文档固定亮色。

---

## 1. 页面与节

| 元素 | 取值 | tokens.json 键 | 实现 |
|---|---|---|---|
| 纸张 | A4，21.0 × 29.7 cm | `layout.page.paper` | 引擎（代码） |
| 方向 | 纵向。章节写 `orientation: landscape` 时新开横向节 | — | 引擎 |
| 页边距 上 / 下 | 2.54 cm | — | 引擎（代码） |
| 页边距 左 / 右 | 2.5 cm | `layout.page.left_margin_mm`、`right_margin_mm` | 引擎（代码），代码里的数值与 tokens 相同 |
| 版心宽度 | 纵向 160 mm，横向 247 mm | `layout.page.portrait_body_mm`、`landscape_body_mm` | 引擎：目录制表位和表格列宽按它计算 |
| 页眉 / 页脚距边 | 1.2 cm | — | 引擎（代码） |
| 首页不同 | 有封面时开，封面不印正文页眉页脚 | — | 引擎 |
| 分栏、奇偶页不同、行号 | 不用 | — | 规范 |
| 页面底色、页面边框 | 不用 | — | 规范 |

---

## 2. 颜色

| 角色 | 色值 | tokens.json 键 | 用途 |
|---|---|---|---|
| ink | `#141A26` | `role.document.color.ink` → `color.gray.18` | 正文、标题、表格数据、三线表粗线 |
| ink_2 | `#3A4352` | `role.document.color.ink_2` → `color.gray.16` | 次一级文字（通用引擎目前不用） |
| muted | `#5D6675` | `role.document.color.muted` → `color.gray.14` | 表头、图题、表注、章节说明、页眉页脚、封面标签 |
| faint | `#6B7482` | `role.document.color.faint` → `color.gray.13` | 图片来源行、虚线状态标签 |
| line | `#D9DEE5` | `role.document.color.line` → `color.gray.7` | 表格行间线、提示条下线、页脚上线、目录分隔线 |
| tint | `#F6F8FB` | `role.document.color.tint` → `color.gray.1` | 浅底（通用引擎目前不用） |
| accent | `#2453C7` | `role.document.color.accent` → `color.blue.text` | 章节编号、提示条上线和标签、引语左线、封面短线 |
| hot | `#C2410C` | `role.document.color.hot` → `color.semantic.hot` | 规则条和风险条、重点等级、必答标记「★」 |
| success / warning | `#1F7A4D` / `#A15C07` | `role.document.color.success`、`warning` | 状态文字，只染文字 |
| party_1 至 party_4 | `#0E7C74` / `#2453C7` / `#B45309` / `#6B4FBB` | `role.document.party.*` | 参与方圆点和泳道图 |

所有文字色对白底的对比度不低于 4.5:1，参与方颜色不低于 3:1。`tests/test_tokens.py` 按 WCAG 2.x 公式计算并检查。

不用的写法：装饰性彩色；整行、整列或整块铺色；蓝色铺底；把状态色当装饰色。

---

## 3. 字体

| 位置 | 字体 | tokens.json 键 | 实现 |
|---|---|---|---|
| 中文、西文、数字、标题、表格 | 微软雅黑 | `font.family.file` | 引擎 |
| 标题字重 | 粗体（700） | `font.weight.document.heading` | 引擎 |
| 正文、表头、表格数据字重 | 常规（400） | `font.weight.document.body`、`table_header`、`table_body` | 引擎 |

- Word 的字体分中文和西文两路。引擎在每个样式和文字段上同时写 `eastAsia`、`ascii`、`hAnsi`、`cs` 四个槽，并删除主题字体。
- 文字的语言写成西文 `en-US`、中文 `zh-CN`，数字里的千分位逗号后不断行。
- 不用中文等宽字体，不用中文斜体。下划线只用于超链接和填空线。
- 文件里写的是字体名。打开文件的电脑没有微软雅黑时，Word 用其他字体显示；需要各处完全一致时，在 Word 里嵌入字体。

---

## 4. 字号

单位为磅。

| 角色 | 字号 | 字重 | 颜色 | tokens.json 键 |
|---|---|---|---|---|
| 封面标题 | 28 | 粗体 | ink | `size.word.cover_title` |
| 文首标题 | 22 | 粗体 | ink | `size.word.document_title` |
| 目录标题 | 20 | 粗体 | ink | `size.word.toc_title` |
| 章标题（标题 1） | 16 | 粗体 | ink，编号 accent | `size.word.h1` |
| 节标题（标题 2） | 14 | 粗体 | ink，编号 accent | `size.word.h2` |
| 小节标题（标题 3） | 12 | 粗体 | ink | `size.word.h3` |
| 导语 | 11 | 常规 | ink | `size.word.lede` |
| 正文 | 10.5 | 常规 | ink | `size.word.body` |
| 章节说明 | 9.5 | 常规 | muted | `size.word.summary` |
| Word 目录样式 TOC 4 至 TOC 9 | 9.5 | 常规 | ink | `size.word.toc_minor` |
| 表格数据、表头 | 9 | 常规 | ink / muted | `size.word.table`、`table_header` |
| 表题、图题、表注 | 8.5 | 表题粗体，其余常规 | ink / muted | `size.word.caption` |
| 页眉页脚 | 8.5 | 常规 | muted | `size.word.header_footer` |
| 泳道图 | 8.5 | 常规 | ink | `size.word.swimlane` |
| 关键数字的数值 | 12 | 粗体 | ink | `size.word.key_value` |

`size.word.amount_primary`、`amount_total`、`total_label` 和 `table_compact` 留给报价类业务扩展使用，通用引擎不读。表格字号不小于 `layout.word.table_capacity.min_font_pt`（9 磅），测试检查这一点。

---

## 5. 段落

| 元素 | 取值 | tokens.json 键 | 实现 |
|---|---|---|---|
| 正文行距 | 最小值 17 磅 | `layout.word.line_spacing.body_pt` | 引擎 |
| 列表行距 | 最小值 16 磅 | `layout.word.line_spacing.list_pt` | 引擎 |
| 表格行距 | 最小值 15 磅；紧凑表格 13.5 磅 | `layout.word.line_spacing.table_pt`、`layout.word.table.compact.line_pt` | 引擎 |
| 正文段后 | 6 磅 | `layout.word.line_spacing.body_space_after_pt` | 引擎 |
| 正文排法 | 两端撑满 | — | 引擎（代码） |
| 首行缩进 | 2 字符 | — | 引擎（代码） |
| 标题行距 | 1.15 倍 | — | 引擎（代码） |
| 标题段前 / 段后 | 标题 1：18 / 7 磅；标题 2：14 / 5 磅；标题 3：10 / 4 磅 | — | 引擎（代码） |
| 标题与下段同页 | 开 | — | 引擎（代码） |
| 小表整表同页 | 8 行以内的表格不跨页 | `config/layout-rules.json` 的 `keep_small_tables` | 引擎 |
| 中文标点 | 中文句子里的半角标点换成全角 | `config/layout-rules.json` 的 `cjk_punctuation` | 引擎 |
| 分页 | 用段前分页，不插空段落 | — | 引擎 |

行距用「最小值」，不用倍数。倍数行距按字体自身的行高计算，换一台电脑的字体就会变；最小值在各处相同。

不用的写法：用空格或全角空格缩进；用连续回车换页。

---

## 6. 标题层级与编号

- 章节最多三级，分别套 Word 内置样式「标题 1」「标题 2」「标题 3」，供目录和导航窗格识别。引擎实现。
- 编号由引擎按章节顺序生成，写成「1」「1.1」「1.1.1」。编号单独一段文字，标题 1、标题 2 的编号用 accent 色。引擎实现。
- 标题 1 上方有一条 ink 色 1.5 磅线（`line.word.chapter_top`，单位 1/8 磅，值 12）。引擎实现。
- 标题独占一行，末尾不加句号。

---

## 7. 列表

| 元素 | 取值 | 实现 |
|---|---|---|
| 无序列表符号 | 「• 」 | 引擎（代码） |
| 有序编号 | 「1. 」；正文已自带编号时不再加 | 引擎，依据 `config/layout-rules.json` 的 `numbering` |
| 一级 / 二级缩进 | 左缩进 0.78 / 1.48 cm，悬挂 0.38 cm | 引擎（代码） |
| 段后 | 3 磅 | 引擎（代码） |

列表符号写成文字，不用 Word 自动编号。LibreOffice 显示 Word 自动编号的符号时会换用 OpenSymbol 字体。符号写成文字后，所有字符都用微软雅黑。

---

## 8. 表格

| 部位 | 取值 | tokens.json 键 | 实现 |
|---|---|---|---|
| 竖线、外框 | 不画 | — | 引擎 |
| 表头上线、表头下线、末行下线 | ink，0.75 磅 | `line.word.table_frame`、`table_header_bottom` | 引擎 |
| 行间线 | line，0.5 磅 | `line.word.table_row` | 引擎 |
| 表头 | 常规字重、muted 色、无底色、居左 | `font.weight.document.table_header` | 引擎 |
| 金额列 | 靠右，千分位，表头补单位 | `config/layout-rules.json` 的 `amount_unit` | 引擎 |
| 单元格内边距 | 常规：上下 6.5 磅、左右 7 磅；紧凑：上下 4 磅、左右 4.5 磅 | `layout.word.table.regular.*`、`compact.*` | 引擎 |
| 首列左边距、末列右边距 | 0，表格左右边线与正文版心一致 | — | 引擎（代码） |
| 竖向排法 | 靠上 | `layout.word.table.v_align` | 引擎 |
| 表头跨页重复 | 开 | — | 引擎 |
| 宽度 | 固定布局，列宽按版心等比缩放，不超出版心 | `layout.page.portrait_body_mm` | 引擎 |
| 列数上限 | 12 | `layout.word.table_capacity.max_columns` | 引擎 |
| 表题 | 在表格上方，8.5 磅粗体 ink，段前 7 磅、段后 4 磅 | `size.word.caption` | 引擎 |
| 表注 | 在表格下方，8.5 磅 muted | `size.word.caption` | 引擎 |
| 键值表 | 两列，标签在左，无表头行 | `config/layout-rules.json` 的 `key_value_table` | 引擎 |
| 合计行、分组行、合并单元格 | 由业务技能经 `register_table_hooks` 实现 | `line.word.total_top` 等 | 规范 |

不用的写法：竖线、外框、全网格；斑马纹；数据区铺色；数字列居左。

---

## 9. 提示条、引语和说明条款

| 元素 | 写法 | tokens.json 键 | 实现 |
|---|---|---|---|
| 提示条 | 上方 accent 1.5 磅线，下方 line 0.5 磅线；标签粗体 accent | `line.word.callout_top`、`callout_bottom` | 引擎 |
| 规则条、风险条 | 同提示条，上线和标签用 hot 色 | `role.document.rule_color.key_top`、`risk_top` | 引擎 |
| 风险条数量 | 全文不超过 2 条 | `layout.limits.risk_callouts_per_document` | 规范：引擎不检查 |
| 引语 | 左侧 accent 1.5 磅竖线，左缩进 0.45 cm，加中文引号，不填底；出处印在下方居右 | `line.word.quote_left` | 引擎 |
| 说明条款 | 序号和冒号前的标签粗体，悬挂缩进 0.78 cm，ink 色。紧跟表格时用表注字号 | — | 引擎 |
| 章节说明 | 章标题下一行 9.5 磅 muted 文字，不加标签和线 | `config/layout-rules.json` 的 `section_summary` | 引擎 |
| 关键数字 | 最多 4 个，每个上方一条 ink 1.5 磅线，标签 8.5 磅 muted，数值 12 磅粗体 | `line.word.key_figure_top` | 引擎 |

---

## 10. 图片与泳道图

| 元素 | 取值 | 实现 |
|---|---|---|
| 图片排法 | 嵌入式，居左，宽度不超过版心 | 引擎 |
| 多张图 | 并排，平分版心宽度 | 引擎 |
| 图题 | 在图片下方居左，8.5 磅 muted | 引擎 |
| 来源行 | 图题下一行，8.5 磅 faint | 引擎 |
| 替代文字 | 写入图片的标题和描述属性 | 引擎 |
| SVG | 以 PNG 备用图嵌入并挂接 SVG。Word 2016 及以后显示 SVG | 引擎 |
| 泳道图 | 每条泳道一个参与方，每列一步。纵向页每段最多 7 步，横向页 14 步，超出时分段并在表题后加「（续）」 | 引擎，取值 `layout.word.swimlane.*` |
| 图表配色 | 灰阶为主，至多一个蓝色高亮；不用三维、阴影和渐变 | 规范 |

---

## 11. 封面、页眉和页脚

| 元素 | 取值 | tokens.json 键 | 实现 |
|---|---|---|---|
| 封面 logo | 居中，宽 3.6 cm，下方空 48 磅 | `config/brand.json` 的 `logo` | 引擎（代码） |
| 封面标题 | 居中，28 磅粗体 ink，单倍行距 | `size.word.cover_title` | 引擎 |
| 封面短线 | 居中，accent 1.75 磅，左右各缩进 5.4 cm | `line.word.cover_rule` | 引擎 |
| 封面信息行 | 居中，标签 muted、值 ink，10.5 磅 | `size.word.body` | 引擎 |
| 封面页脚 | 居中，公司名，8.5 磅 muted | `size.word.header_footer` | 引擎 |
| 页眉 | 左侧文档标题，8.5 磅 muted；右侧 logo，宽 2.35 cm | `size.word.header_footer` | 引擎 |
| 页脚 | 左侧「公司名｜版本」，右侧「第 X 页 / 共 Y 页」，上方 line 0.5 磅线 | `line.word.footer_top` | 引擎 |
| 页码 | PAGE 和 NUMPAGES 域 | — | 引擎 |
| 页眉中的章节名 | STYLEREF 域 | — | 规范 |

品牌名和 logo 在 `config/brand.json`。没有 logo 文件时，页眉印品牌字标文字，封面在标题上方留 78 磅空白。

不用的写法：手输页码；大面积色块的 logo。

---

## 12. 目录

| 元素 | 取值 | 实现 |
|---|---|---|
| 目录标题 | 「目录」，20 磅粗体 ink，下方 ink 0.75 磅线 | 引擎 |
| 目录域 | TOC 域，收标题 1 至标题 3，条目可点击 | 引擎 |
| 一级条目 | 10.5 磅粗体，条目之间 line 0.5 磅线 | 引擎 |
| 二级、三级条目 | 10.5 磅常规，每级缩进 0.75 cm | 引擎 |
| 条目编号 | 一级、二级 accent，三级 ink | 引擎 |
| 页码 | 靠右，目录样式写空白引导符。LibreOffice 刷新目录后显示点线，Word 里没有核对 | 引擎 |
| 生成时的页码 | 写「［待刷新］」。Word 里更新域，或运行 `scripts/update_toc_export.py` 后才有页码 | 引擎 |
| 图表目录、表格目录 | 按需 | 规范 |

---

## 13. 文前部分

- **封面**：见第 11 节。`meta.cover_fields` 写明时按它印信息行，不写时印客户、项目、版本、日期。
- **文首**：正文第一页。客户名（有时）、文首标题、导语、关键数字。有封面时不再印信息条，依据 `config/layout-rules.json` 的 `first_page_info_line`。
- **文首提示条、文末提示条**：内容 JSON 的 `intro` 和 `closing_note`。
- **摘要、版本历史表**：规范，按需用普通章节和表格写。

---

## 14. 域、脚注和交叉引用

| 元素 | 实现 |
|---|---|
| TOC、PAGE、NUMPAGES | 引擎 |
| 打开文件时自动更新域 | 不开。Word 打开时不弹出更新域的提示，目录页码需要手动更新或用脚本刷新 |
| SEQ 题注编号、REF 交叉引用、DATE、STYLEREF | 规范 |
| 脚注、尾注、参考文献、超链接 | 规范。超链接用 accent 色 |

---

## 15. 文档属性与无障碍

| 元素 | 取值 | 实现 |
|---|---|---|
| 标题属性 | `meta.title` | 引擎 |
| 作者属性 | `config/brand.json` 的 `company` | 引擎 |
| 备注属性 | 清空 | 引擎 |
| 兼容模式 | Word 2013 及以后（compatibilityMode 15） | 引擎 |
| 标题样式 | 内置标题样式，供屏幕阅读器和导航窗格识别 | 引擎 |
| 表头行 | 标记为重复表头 | 引擎 |
| OOXML 属性顺序 | 保存后整理并检查，检查不通过时删除文件并报错 | 引擎 |
| 对比度 | 文字 4.5:1，图形 3:1，不靠颜色单独表达含义 | `tests/test_tokens.py` 检查取值 |
| 导出 PDF | 生成书签、嵌入字体 | 规范 |

---

## 16. 修订与版本

修订、批注、文档保护、密级标注和水印都按需在 Word 里设置，引擎不实现。内部版可在 `meta` 写 `show_workflow_status: true`，封面和页脚会印文档状态。

---

## 不用的写法汇总

- 纯黑文字；装饰性彩色；整行、整列或整块铺色；蓝色铺底。
- 中文等宽字体；中文斜体；标题用衬线体；数字用另一种字体。
- 表格竖线、外框、全网格、斑马纹；数据区铺色；数字列居左。
- 空格缩进；手输页码；放大加粗的正文冒充标题。
- 连续回车换页；文档跟随系统深色模式。

---

取值来源：颜色色阶来自 aham-ui，Word 字号、线宽和版面规则来自原文档引擎的取值，经设计决策表统一后写入 `tokens.json`。
