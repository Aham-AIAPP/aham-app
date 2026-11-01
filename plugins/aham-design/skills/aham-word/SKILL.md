---
name: aham-word
description: 按 Aham 设计规范生成 Word 文档（.docx）。触发场景：用户要做一份 Word；要把资料整理成 Word 版的方案、报告、需求说明、会议纪要或说明文档；要按统一规范出 docx；要带封面、目录、页码和三线表的正式文档。做法是把内容写成 JSON，由 scripts/build_docx.py 调用 aham_doc 引擎生成；颜色、字体、字号和线宽全部取自 aham-design 插件根目录的 tokens.json，内容里不写格式。PPT、Excel 和网页不用本技能。
---

# Aham Word

本技能把结构化内容排成 Word 文档。格式全部由引擎决定，取值全部来自插件根目录的 `tokens.json`。同一份内容生成两次，得到的文件除时间戳外完全一致。

## 文件位置

| 路径 | 内容 |
|---|---|
| `../../tokens.json` | 设计取值：颜色、字体、字号、线宽、版心。整个 aham-design 插件共用这一份 |
| `scripts/build_docx.py` | 命令行入口：内容 JSON → .docx |
| `scripts/aham_doc/` | 排版引擎。`document.py` 组装整份文档，`word.py` 写各类内容块，`tokens.py` 读取值 |
| `scripts/update_toc_export.py` | 用 LibreOffice 刷新目录和页码域，再导出 PDF |
| `config/layout-rules.json` | 版面规则，每条写明依据和依据强度 |
| `config/writing-rules.json` | 用词和标点规则 |
| `config/brand.json` | 页眉、页脚和封面上的品牌名与 logo |
| `references/word-spec.md` | 影响 Word 排版的元素清单，逐项写明取值、来源和引擎实现情况 |
| `references/content-format.md` | 内容 JSON 的格式 |
| `examples/` | 样张内容、生成脚本和生成好的样张 |

## 生成流程

1. AI 先确认文档类型、读者、章节结构，以及是否需要封面和目录。
2. 客户名、金额、数量、日期、编号等事实，用户没有给出时，AI 向用户询问。没有来源的事实不写进文档。
3. AI 按 `references/content-format.md` 把内容写成 JSON。内容只写文字和结构，不写字体、颜色和字号。
4. 运行 `python3 scripts/build_docx.py 内容.json 输出.docx`。引擎保存后检查 OOXML 属性顺序，检查不通过时删除文件并报错。
5. 需要 PDF 时运行 `python3 scripts/update_toc_export.py 输出.docx 输出.pdf`。这一步同时填好目录页码。
6. 交付前，AI 打开 PDF 或 .docx 逐页查看，确认没有空白页、表格没有超出版心。

## 内容规则

- 同一个数字在文档里出现多次时，在 `numeric_facts` 里声明一次，正文用 `{{fact:编号}}` 引用。
- 关键数字（`meta.key_figures`）最多 4 个。
- 风险条（`tone` 为 `risk` 的提示条）全文最多 2 条，上限取 `layout.limits.risk_callouts_per_document`，超出时生成报错。
- 参与方（`parties`）最多 4 个，颜色按顺序取 `role.document.party`。
- 表格最多 12 列。列宽键只认 `widths_cm`，拼错的宽度键直接报错。
- 表头含「金额」「单价」「总价」「税额」的列靠右排，并在表头补单位。
- 有序编号用「1.」，下一级用「（1）」，依据 GB/T 9704-2012。
- 中文句子里的半角标点由引擎换成全角。

## 取值来源

- 引擎从脚本所在目录逐级向上查找同时含 `tokens.json` 和 `.claude-plugin/plugin.json` 的目录，读取其中的 `tokens.json`。
- 环境变量 `AHAM_DESIGN_TOKENS` 指向另一份 tokens.json 时，引擎改读那一份。
- `tokens.py` 的 `document_style()` 把 tokens.json 换算成引擎使用的文档取值视图。文档颜色经 `role.document` 映射到冷灰色阶和蓝色色阶。
- 引擎代码里没有颜色、字号和版式数值常量。段距、行距、缩进、页边距、页眉页脚距和单元格内边距读 `tokens.json` 的 `layout.page` 和 `layout.word`。测试 `test_engine.py` 逐行检查这一点。

## 扩展点

通用引擎不含任何业务专有的写法。业务技能经下列函数登记自己的写法，不改引擎代码：

| 函数 | 用途 |
|---|---|
| `register_block(类型, 渲染函数)` | 登记新的内容块类型 |
| `register_table_hooks(名称, TableHooks(...))` | 登记表格扩展：`adjust_widths` 改列宽，`render_row` 接管一行的写法，`after_row` 处理写好的一行，`after_table` 做合并单元格等整表处理 |
| `set_svg_rasterizer(函数)` | SVG 没有配 PNG 备用图时，用这个函数生成 PNG。Word 2016 及以后显示 SVG，其他软件显示 PNG |
| `set_svg_styler(函数)` | 嵌入 SVG 前给它加样式 |

`render_row` 收到 `TableRowContext`，可用 `prepare_table_cell`、`table_row_bottom`、`set_cell_fill` 和 `set_cell_borders` 写单元格。合计行、分组行和按供应商合并单元格都按这种方式由业务技能实现，测试里有一个合计行的例子。

## 规范替换

1. 复制 `tokens.json`，按 `references/word-spec.md` 逐项修改取值。
2. 设置 `AHAM_DESIGN_TOKENS=新文件路径`。
3. 修改 `config/brand.json` 和 logo 文件，或调用 `aham_doc.brand.set_brand`。
4. 重新生成样张，与原样张逐页比较。

## 已知限制

- 文件里的字体名是「微软雅黑」。没有安装这一字体的电脑会用其他字体显示，文件内容不变。
- 目录先写入标题文字，页码位置写「［待刷新］」。Word 里更新域，或运行 `update_toc_export.py` 后，才有页码。
- 引擎只输出 Word。HTML 预览、网页样式和图表生成没有迁入本技能。
- 样张只在 LibreOffice 中渲染检查过，没有在 Microsoft Word 中打开核对。

## 依赖

- Python 3（在 3.13 上测试过），`python-docx`（在 1.2.0 上测试过）、`lxml`。
- 导出 PDF 和刷新目录需要 LibreOffice（`soffice` 和 python-uno）。
